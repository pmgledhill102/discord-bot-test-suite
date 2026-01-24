package com.discord.webhook.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import io.quarkus.runtime.annotations.RegisterForReflection;

@RegisterForReflection
@JsonInclude(JsonInclude.Include.NON_NULL)
public class InteractionResponse {
  private int type;
  private ResponseData data;

  public InteractionResponse() {}

  public InteractionResponse(int type) {
    this.type = type;
  }

  public InteractionResponse(int type, ResponseData data) {
    this.type = type;
    this.data = data;
  }

  public int getType() {
    return type;
  }

  public void setType(int type) {
    this.type = type;
  }

  public ResponseData getData() {
    return data;
  }

  public void setData(ResponseData data) {
    this.data = data;
  }

  public static InteractionResponse pong() {
    return new InteractionResponse(1);
  }

  public static InteractionResponse deferredChannelMessage() {
    return new InteractionResponse(5);
  }

  public static InteractionResponse channelMessage(String content) {
    return new InteractionResponse(4, new ResponseData(content));
  }

  @RegisterForReflection
  @JsonInclude(JsonInclude.Include.NON_NULL)
  public static class ResponseData {
    private String content;
    private Integer flags;

    public ResponseData() {}

    public ResponseData(String content) {
      this.content = content;
    }

    public String getContent() {
      return content;
    }

    public void setContent(String content) {
      this.content = content;
    }

    public Integer getFlags() {
      return flags;
    }

    public void setFlags(Integer flags) {
      this.flags = flags;
    }
  }
}
