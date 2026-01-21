package com.discord.webhook.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import io.quarkus.runtime.annotations.RegisterForReflection;
import java.util.Map;

@RegisterForReflection
@JsonIgnoreProperties(ignoreUnknown = true)
public class Interaction {
    private String id;
    private int type;

    @JsonProperty("application_id")
    private String applicationId;

    @JsonProperty("guild_id")
    private String guildId;

    @JsonProperty("channel_id")
    private String channelId;

    private Map<String, Object> data;
    private String token;

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public int getType() {
        return type;
    }

    public void setType(int type) {
        this.type = type;
    }

    public String getApplicationId() {
        return applicationId;
    }

    public void setApplicationId(String applicationId) {
        this.applicationId = applicationId;
    }

    public String getGuildId() {
        return guildId;
    }

    public void setGuildId(String guildId) {
        this.guildId = guildId;
    }

    public String getChannelId() {
        return channelId;
    }

    public void setChannelId(String channelId) {
        this.channelId = channelId;
    }

    public Map<String, Object> getData() {
        return data;
    }

    public void setData(Map<String, Object> data) {
        this.data = data;
    }

    public String getToken() {
        return token;
    }

    public void setToken(String token) {
        this.token = token;
    }

    public Interaction createSanitizedCopy() {
        Interaction copy = new Interaction();
        copy.id = this.id;
        copy.type = this.type;
        copy.applicationId = this.applicationId;
        copy.guildId = this.guildId;
        copy.channelId = this.channelId;
        copy.data = this.data;
        // Deliberately exclude token
        return copy;
    }
}
