package controllers

import org.apache.pekko.util.ByteString
import play.api.libs.json.*
import play.api.mvc.*
import services.{PubSubService, SignatureService}

import javax.inject.*
import scala.concurrent.{ExecutionContext, Future}
import scala.util.{Failure, Success, Try}

/** Discord interaction controller.
  *
  * Handles Discord webhook interactions:
  *   - Validates Ed25519 signatures
  *   - Responds to Ping (type=1) with Pong (type=1)
  *   - Responds to Slash commands (type=2) with Deferred (type=5)
  *   - Publishes sanitized slash command payloads to Pub/Sub
  */
@Singleton
class InteractionController @Inject() (
  val controllerComponents: ControllerComponents,
  signatureService: SignatureService,
  pubSubService: PubSubService
)(implicit ec: ExecutionContext)
    extends BaseController:

  // Interaction types
  private val InteractionTypePing = 1
  private val InteractionTypeApplicationCommand = 2

  // Response types
  private val ResponseTypePong = 1
  private val ResponseTypeDeferredChannelMessage = 5

  /** Health check endpoint. */
  def health: Action[AnyContent] = Action {
    Ok(Json.obj("status" -> "ok"))
  }

  /** Handle Discord interaction webhook. */
  def handleInteraction: Action[RawBuffer] = Action(parse.raw) { request =>
    // Get raw body for signature verification
    val bodyBytes = request.body.asBytes().getOrElse(ByteString.empty)
    val bodyString = bodyBytes.utf8String

    // Get signature headers
    val signature = request.headers.get("X-Signature-Ed25519").getOrElse("")
    val timestamp = request.headers.get("X-Signature-Timestamp").getOrElse("")

    // Validate signature
    if !signatureService.validateSignature(signature, timestamp, bodyString) then
      Unauthorized(Json.obj("error" -> "invalid signature"))
    else
      // Parse interaction - handle malformed JSON gracefully
      Try(Json.parse(bodyString)) match
        case Success(json) =>
          json.validate[JsObject] match
            case JsSuccess(interaction, _) =>
              handleInteractionByType(interaction)
            case JsError(_) =>
              BadRequest(Json.obj("error" -> "invalid JSON"))
        case Failure(_) =>
          BadRequest(Json.obj("error" -> "invalid JSON"))
  }

  private def handleInteractionByType(interaction: JsObject): Result =
    (interaction \ "type").asOpt[Int] match
      case Some(InteractionTypePing) =>
        handlePing()
      case Some(InteractionTypeApplicationCommand) =>
        handleApplicationCommand(interaction)
      case _ =>
        BadRequest(Json.obj("error" -> "unsupported interaction type"))

  /** Handle Ping interaction - respond with Pong. Do NOT publish to Pub/Sub. */
  private def handlePing(): Result =
    Ok(Json.obj("type" -> ResponseTypePong))

  /** Handle Application Command (slash command) interaction. */
  private def handleApplicationCommand(interaction: JsObject): Result =
    // Publish to Pub/Sub in background (if configured)
    Future {
      pubSubService.publish(interaction)
    }

    // Respond with deferred response (non-ephemeral)
    Ok(Json.obj("type" -> ResponseTypeDeferredChannelMessage))
