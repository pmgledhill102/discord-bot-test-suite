package com.discord.webhook.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.util.Map;

@JsonInclude(JsonInclude.Include.NON_NULL)
public class InteractionResponse {

  public static final int TYPE_PONG = 1;
  public static final int TYPE_DEFERRED_CHANNEL_MESSAGE = 5;

  private int type;
  private Map<String, Object> data;

  public InteractionResponse() {}

  public InteractionResponse(int type) {
    this.type = type;
  }

  public int getType() {
    return type;
  }

  public void setType(int type) {
    this.type = type;
  }

  public Map<String, Object> getData() {
    return data;
  }

  public void setData(Map<String, Object> data) {
    this.data = data;
  }
}
