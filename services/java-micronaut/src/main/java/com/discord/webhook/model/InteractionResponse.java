package com.discord.webhook.model;

import io.micronaut.core.annotation.Introspected;
import io.micronaut.serde.annotation.Serdeable;

@Serdeable
@Introspected
public class InteractionResponse {
    public static final int TYPE_PONG = 1;
    public static final int TYPE_CHANNEL_MESSAGE = 4;
    public static final int TYPE_DEFERRED_CHANNEL_MESSAGE = 5;
    public static final int TYPE_DEFERRED_UPDATE_MESSAGE = 6;
    public static final int TYPE_UPDATE_MESSAGE = 7;

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

    public int getType() { return type; }
    public void setType(int type) { this.type = type; }

    public ResponseData getData() { return data; }
    public void setData(ResponseData data) { this.data = data; }

    @Serdeable
    @Introspected
    public static class ResponseData {
        private String content;
        private Integer flags;

        public ResponseData() {}

        public ResponseData(String content) {
            this.content = content;
        }

        public String getContent() { return content; }
        public void setContent(String content) { this.content = content; }

        public Integer getFlags() { return flags; }
        public void setFlags(Integer flags) { this.flags = flags; }
    }
}
