package com.discord.webhook.model;

import io.micronaut.core.annotation.Introspected;
import io.micronaut.serde.annotation.Serdeable;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.HashMap;
import java.util.Map;

@Serdeable
@Introspected
@JsonIgnoreProperties(ignoreUnknown = true)
public class Interaction {
    public static final int TYPE_PING = 1;
    public static final int TYPE_APPLICATION_COMMAND = 2;
    public static final int TYPE_MESSAGE_COMPONENT = 3;
    public static final int TYPE_AUTOCOMPLETE = 4;
    public static final int TYPE_MODAL_SUBMIT = 5;

    private String id;
    private int type;

    @JsonProperty("application_id")
    private String applicationId;

    @JsonProperty("guild_id")
    private String guildId;

    @JsonProperty("channel_id")
    private String channelId;

    private Map<String, Object> member;
    private Map<String, Object> user;
    private String token;
    private int version;
    private Map<String, Object> data;

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public int getType() { return type; }
    public void setType(int type) { this.type = type; }

    public String getApplicationId() { return applicationId; }
    public void setApplicationId(String applicationId) { this.applicationId = applicationId; }

    public String getGuildId() { return guildId; }
    public void setGuildId(String guildId) { this.guildId = guildId; }

    public String getChannelId() { return channelId; }
    public void setChannelId(String channelId) { this.channelId = channelId; }

    public Map<String, Object> getMember() { return member; }
    public void setMember(Map<String, Object> member) { this.member = member; }

    public Map<String, Object> getUser() { return user; }
    public void setUser(Map<String, Object> user) { this.user = user; }

    public String getToken() { return token; }
    public void setToken(String token) { this.token = token; }

    public int getVersion() { return version; }
    public void setVersion(int version) { this.version = version; }

    public Map<String, Object> getData() { return data; }
    public void setData(Map<String, Object> data) { this.data = data; }

    public Interaction createSanitizedCopy() {
        Interaction copy = new Interaction();
        copy.setId(this.id);
        copy.setType(this.type);
        copy.setApplicationId(this.applicationId);
        copy.setGuildId(this.guildId);
        copy.setChannelId(this.channelId);
        copy.setMember(this.member != null ? new HashMap<>(this.member) : null);
        copy.setUser(this.user != null ? new HashMap<>(this.user) : null);
        copy.setVersion(this.version);
        copy.setData(this.data != null ? new HashMap<>(this.data) : null);
        // Token is intentionally NOT copied
        return copy;
    }
}
