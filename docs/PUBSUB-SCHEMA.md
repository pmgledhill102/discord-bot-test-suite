# PUBSUB-SCHEMA.md - Pub/Sub Message Specification

This document defines the schema for messages published to Pub/Sub when handling Discord slash command interactions.

## Overview

When a service receives a valid slash command (interaction type=2), it publishes a sanitized version of the interaction payload to Pub/Sub for downstream processing. Sensitive fields are redacted before publishing.

## Message Format

### Pub/Sub Message Structure

```json
{
  "data": "<base64-encoded JSON payload>",
  "attributes": {
    "interaction_id": "<interaction ID>",
    "interaction_type": "2",
    "application_id": "<application ID>",
    "guild_id": "<guild ID or empty>",
    "channel_id": "<channel ID>",
    "command_name": "<slash command name>",
    "timestamp": "<ISO 8601 timestamp>"
  }
}
```

### Decoded Data Payload

The `data` field contains a base64-encoded JSON object with the sanitized interaction:

```json
{
  "type": 2,
  "id": "interaction-id",
  "application_id": "application-id",
  "data": {
    "id": "command-id",
    "name": "command-name",
    "options": [
      {
        "name": "option-name",
        "type": 3,
        "value": "option-value"
      }
    ]
  },
  "guild_id": "guild-id",
  "channel_id": "channel-id",
  "member": {
    "user": {
      "id": "user-id",
      "username": "username",
      "discriminator": "0",
      "global_name": "display-name",
      "avatar": "avatar-hash"
    },
    "roles": ["role-id-1", "role-id-2"],
    "joined_at": "2023-01-01T00:00:00.000000+00:00",
    "nick": "nickname"
  },
  "locale": "en-US",
  "guild_locale": "en-US"
}
```

## Sensitive Data Redaction

The following fields MUST be removed or redacted before publishing:

| Field | Location | Action |
|-------|----------|--------|
| `token` | Root level | **Remove entirely** |
| `X-Signature-Ed25519` | HTTP header | Never include |
| `X-Signature-Timestamp` | HTTP header | Never include |
| Raw request body | N/A | Never log or include |

### Fields That Are Safe to Include

| Field | Description |
|-------|-------------|
| `type` | Interaction type (always 2 for slash commands) |
| `id` | Unique interaction ID |
| `application_id` | Bot application ID |
| `data` | Command data (name, options) |
| `guild_id` | Server ID (may be empty for DMs) |
| `channel_id` | Channel ID |
| `member` | Member info (user, roles, nickname) |
| `user` | User info (for DM interactions) |
| `locale` | User's locale |
| `guild_locale` | Server's locale |

## Message Attributes

Attributes provide metadata for filtering and routing without parsing the message body:

| Attribute | Type | Description |
|-----------|------|-------------|
| `interaction_id` | string | Unique interaction ID |
| `interaction_type` | string | Always "2" for slash commands |
| `application_id` | string | Bot application ID |
| `guild_id` | string | Server ID (empty string for DMs) |
| `channel_id` | string | Channel ID |
| `command_name` | string | Name of the slash command invoked |
| `timestamp` | string | ISO 8601 timestamp of when message was published |

## Example

### Input: Discord Slash Command Interaction

```json
{
  "type": 2,
  "id": "1234567890",
  "application_id": "9876543210",
  "token": "SENSITIVE_TOKEN_HERE",
  "data": {
    "id": "cmd-123",
    "name": "ping",
    "options": []
  },
  "guild_id": "111222333",
  "channel_id": "444555666",
  "member": {
    "user": {
      "id": "user-789",
      "username": "testuser",
      "discriminator": "0",
      "global_name": "Test User",
      "avatar": "abc123"
    },
    "roles": ["role-1"],
    "joined_at": "2023-06-15T10:30:00.000000+00:00",
    "nick": null
  },
  "locale": "en-US",
  "guild_locale": "en-US"
}
```

### Output: Published Pub/Sub Message

**Attributes:**
```json
{
  "interaction_id": "1234567890",
  "interaction_type": "2",
  "application_id": "9876543210",
  "guild_id": "111222333",
  "channel_id": "444555666",
  "command_name": "ping",
  "timestamp": "2026-01-20T15:30:00Z"
}
```

**Data (base64-decoded):**
```json
{
  "type": 2,
  "id": "1234567890",
  "application_id": "9876543210",
  "data": {
    "id": "cmd-123",
    "name": "ping",
    "options": []
  },
  "guild_id": "111222333",
  "channel_id": "444555666",
  "member": {
    "user": {
      "id": "user-789",
      "username": "testuser",
      "discriminator": "0",
      "global_name": "Test User",
      "avatar": "abc123"
    },
    "roles": ["role-1"],
    "joined_at": "2023-06-15T10:30:00.000000+00:00",
    "nick": null
  },
  "locale": "en-US",
  "guild_locale": "en-US"
}
```

Note: The `token` field is completely absent from the output.

## Validation Rules

Contract tests verify:

1. **Token redaction**: The `token` field must NOT appear in the published message
2. **Required attributes**: All message attributes must be present
3. **Valid JSON**: The data payload must be valid JSON when decoded
4. **Type preservation**: Field types must match the original (numbers stay numbers, etc.)
5. **Completeness**: All non-sensitive fields from the original interaction should be present

## Topic Configuration

| Environment | Topic Name Pattern |
|-------------|-------------------|
| Production | `projects/{project}/topics/discord-interactions` |
| Testing | `projects/{project}/topics/test-{unique-id}` |

Tests use unique topic names per test to enable parallel execution without interference.
