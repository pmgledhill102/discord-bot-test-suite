package services

import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import play.api.{Configuration, Logging}

import java.nio.charset.StandardCharsets
import javax.inject.*
import scala.util.Try

/** Service for validating Discord Ed25519 signatures. */
@Singleton
class SignatureService @Inject() (config: Configuration) extends Logging:

  private val publicKey: Option[Ed25519PublicKeyParameters] =
    config.getOptional[String]("discord.publicKey").flatMap { hex =>
      Try {
        val bytes = hexToBytes(hex)
        new Ed25519PublicKeyParameters(bytes, 0)
      }.toOption
    }

  if publicKey.isEmpty then
    logger.error("DISCORD_PUBLIC_KEY environment variable is required")

  /** Validate Discord Ed25519 signature.
    *
    * @param signatureHex
    *   Hex-encoded Ed25519 signature
    * @param timestamp
    *   Unix timestamp string
    * @param body
    *   Raw request body string
    * @return
    *   true if signature is valid, false otherwise
    */
  def validateSignature(
      signatureHex: String,
      timestamp: String,
      body: String
  ): Boolean =
    publicKey match
      case None => false
      case Some(key) =>
        if signatureHex.isEmpty || timestamp.isEmpty then false
        else
          // Check timestamp (must be within 5 seconds)
          val validTimestamp = Try {
            val ts = timestamp.toLong
            val now = System.currentTimeMillis() / 1000
            now - ts <= 5
          }.getOrElse(false)

          if !validTimestamp then false
          else verifySignature(key, signatureHex, timestamp, body)

  private def verifySignature(
      key: Ed25519PublicKeyParameters,
      signatureHex: String,
      timestamp: String,
      body: String
  ): Boolean =
    Try {
      val signatureBytes = hexToBytes(signatureHex)
      val message = (timestamp + body).getBytes(StandardCharsets.UTF_8)

      val verifier = new Ed25519Signer()
      verifier.init(false, key)
      verifier.update(message, 0, message.length)
      verifier.verifySignature(signatureBytes)
    }.getOrElse(false)

  private def hexToBytes(hex: String): Array[Byte] =
    hex.grouped(2).map(Integer.parseInt(_, 16).toByte).toArray
