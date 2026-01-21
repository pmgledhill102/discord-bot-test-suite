// Discord webhook service implementation using Scala and Play Framework.
//
// This service handles Discord interactions webhooks:
// - Validates Ed25519 signatures on incoming requests
// - Responds to Ping (type=1) with Pong (type=1)
// - Responds to Slash commands (type=2) with Deferred (type=5)
// - Publishes sanitized slash command payloads to Pub/Sub

name := "discord-webhook-service"
organization := "com.example"
version := "1.0.0"
scalaVersion := "3.3.4"

lazy val root = (project in file("."))
  .enablePlugins(PlayScala)
  .disablePlugins(PlayLayoutPlugin)
  .settings(
    // Use standard Play layout
    Compile / scalaSource := baseDirectory.value / "app",
    Compile / resourceDirectory := baseDirectory.value / "conf",

    libraryDependencies ++= Seq(
      guice,
      // Ed25519 signature verification
      "org.bouncycastle" % "bcprov-jdk18on" % "1.79",
      // Google Cloud Pub/Sub
      "com.google.cloud" % "google-cloud-pubsub" % "1.135.0",
      // JSON handling (Play JSON is included)
      "org.playframework" %% "play-json" % "3.0.4"
    ),

    // Disable unused Play features for minimal footprint
    PlayKeys.devSettings ++= Seq(
      "play.server.http.idleTimeout" -> "infinite"
    )
  )

// Assembly settings for creating a fat JAR
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", "services", _*) => MergeStrategy.concat
  case PathList("META-INF", _*) => MergeStrategy.discard
  case "reference.conf" => MergeStrategy.concat
  case "application.conf" => MergeStrategy.concat
  case _ => MergeStrategy.first
}
