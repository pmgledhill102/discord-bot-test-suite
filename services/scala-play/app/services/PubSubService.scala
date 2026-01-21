package services

import com.google.api.gax.core.{CredentialsProvider, NoCredentialsProvider}
import com.google.api.gax.grpc.GrpcTransportChannel
import com.google.api.gax.rpc.{FixedTransportChannelProvider, TransportChannelProvider}
import com.google.cloud.pubsub.v1.{Publisher, TopicAdminClient, TopicAdminSettings}
import com.google.protobuf.ByteString
import com.google.pubsub.v1.{PubsubMessage, TopicName}
import io.grpc.ManagedChannelBuilder
import play.api.libs.json.*
import play.api.{Configuration, Logging}

import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit
import javax.inject.*
import scala.jdk.CollectionConverters.*
import scala.util.Try

/** Service for publishing interactions to Google Cloud Pub/Sub. */
@Singleton
class PubSubService @Inject() (config: Configuration) extends Logging:

  private val projectId: Option[String] =
    config.getOptional[String]("gcp.projectId")
  private val topicName: Option[String] =
    config.getOptional[String]("pubsub.topic")
  private val emulatorHost: Option[String] =
    sys.env.get("PUBSUB_EMULATOR_HOST")

  private val publisher: Option[Publisher] = for
    project <- projectId
    topic <- topicName
  yield createPublisher(project, topic)

  private def createPublisher(project: String, topic: String): Publisher =
    val topicNameObj = TopicName.of(project, topic)

    val builder = Publisher.newBuilder(topicNameObj)

    emulatorHost match
      case Some(host) =>
        logger.info(s"Using Pub/Sub emulator at $host")
        // Configure for emulator (no credentials, insecure channel)
        val channel = ManagedChannelBuilder.forTarget(host).usePlaintext().build()
        val channelProvider: TransportChannelProvider =
          FixedTransportChannelProvider.create(GrpcTransportChannel.create(channel))
        val credentialsProvider: CredentialsProvider = NoCredentialsProvider.create()

        builder
          .setChannelProvider(channelProvider)
          .setCredentialsProvider(credentialsProvider)

        // Create topic if it doesn't exist (for emulator)
        ensureTopicExists(project, topic, channelProvider, credentialsProvider)

      case None =>
        // Use default credentials for production

    logger.info(s"Pub/Sub configured: $topicNameObj")
    builder.build()

  private def ensureTopicExists(
      project: String,
      topic: String,
      channelProvider: TransportChannelProvider,
      credentialsProvider: CredentialsProvider
  ): Unit =
    Try {
      val settings = TopicAdminSettings
        .newBuilder()
        .setTransportChannelProvider(channelProvider)
        .setCredentialsProvider(credentialsProvider)
        .build()
      val adminClient = TopicAdminClient.create(settings)
      try
        val topicNameObj = TopicName.of(project, topic)
        try adminClient.getTopic(topicNameObj)
        catch
          case _: com.google.api.gax.rpc.NotFoundException =>
            adminClient.createTopic(topicNameObj)
            logger.info(s"Created topic: $topicNameObj")
      finally adminClient.close()
    }.recover { case e: Exception =>
      logger.warn(s"Failed to ensure topic exists: ${e.getMessage}")
    }

  /** Publish sanitized interaction to Pub/Sub.
    *
    * @param interaction
    *   The interaction JSON object (will be sanitized before publishing)
    */
  def publish(interaction: JsObject): Unit =
    publisher match
      case None => // Pub/Sub not configured
      case Some(pub) =>
        Try {
          val sanitized = sanitizeInteraction(interaction)
          val data = ByteString.copyFromUtf8(Json.stringify(sanitized))

          val attributes = buildAttributes(interaction)

          val message = PubsubMessage
            .newBuilder()
            .setData(data)
            .putAllAttributes(attributes.asJava)
            .build()

          val future = pub.publish(message)
          // Wait for publish to complete (with timeout)
          future.get(10, TimeUnit.SECONDS)
        }.recover { case e: Exception =>
          logger.error(s"Failed to publish to Pub/Sub: ${e.getMessage}")
        }

  /** Sanitize interaction for Pub/Sub (remove sensitive fields like token). */
  private def sanitizeInteraction(interaction: JsObject): JsObject =
    // Copy only safe fields (explicitly exclude "token")
    val safeFields = Seq(
      "type",
      "id",
      "application_id",
      "data",
      "guild_id",
      "channel_id",
      "member",
      "user",
      "locale",
      "guild_locale"
    )

    val sanitizedFields = safeFields.flatMap { field =>
      (interaction \ field).asOpt[JsValue].map(field -> _)
    }

    JsObject(sanitizedFields)

  /** Build Pub/Sub message attributes. */
  private def buildAttributes(interaction: JsObject): Map[String, String] =
    val base = Map(
      "interaction_id" -> (interaction \ "id").asOpt[String].getOrElse(""),
      "interaction_type" -> (interaction \ "type")
        .asOpt[Int]
        .map(_.toString)
        .getOrElse(""),
      "application_id" -> (interaction \ "application_id")
        .asOpt[String]
        .getOrElse(""),
      "guild_id" -> (interaction \ "guild_id").asOpt[String].getOrElse(""),
      "channel_id" -> (interaction \ "channel_id").asOpt[String].getOrElse(""),
      "timestamp" -> DateTimeFormatter.ISO_INSTANT.format(Instant.now())
    )

    // Add command name if available
    val commandName = (interaction \ "data" \ "name").asOpt[String]
    commandName.fold(base)(name => base + ("command_name" -> name))

  /** Shutdown the publisher gracefully. */
  def shutdown(): Unit =
    publisher.foreach { pub =>
      pub.shutdown()
      pub.awaitTermination(10, TimeUnit.SECONDS)
    }
