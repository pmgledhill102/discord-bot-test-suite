package com.discord.webhook.model;

public class InteractionResponse {

  public static final int TYPE_PONG = 1;
  public static final int TYPE_DEFERRED_CHANNEL_MESSAGE = 5;

  private int type;

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
}
