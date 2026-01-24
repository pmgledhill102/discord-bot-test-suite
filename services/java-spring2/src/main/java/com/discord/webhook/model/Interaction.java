package com.discord.webhook.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.Map;

@JsonIgnoreProperties(ignoreUnknown = true)
public class Interaction {

  public static final int TYPE_PING = 1;
  public static final int TYPE_APPLICATION_COMMAND = 2;

  private int type;

  private String id;

  @JsonProperty("application_id")
  private String applicationId;

  private String token;

  private Map<String, Object> data;

  @JsonProperty("guild_id")
  private String guildId;

  @JsonProperty("channel_id")
  private String channelId;

  private Map<String, Object> member;

  private Map<String, Object> user;

  private String locale;

  @JsonProperty("guild_locale")
  private String guildLocale;

  public int getType() {
    return type;
  }

  public void setType(int type) {
    this.type = type;
  }

  public String getId() {
    return id;
  }

  public void setId(String id) {
    this.id = id;
  }

  public String getApplicationId() {
    return applicationId;
  }

  public void setApplicationId(String applicationId) {
    this.applicationId = applicationId;
  }

  public String getToken() {
    return token;
  }

  public void setToken(String token) {
    this.token = token;
  }

  public Map<String, Object> getData() {
    return data;
  }

  public void setData(Map<String, Object> data) {
    this.data = data;
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

  public Map<String, Object> getMember() {
    return member;
  }

  public void setMember(Map<String, Object> member) {
    this.member = member;
  }

  public Map<String, Object> getUser() {
    return user;
  }

  public void setUser(Map<String, Object> user) {
    this.user = user;
  }

  public String getLocale() {
    return locale;
  }

  public void setLocale(String locale) {
    this.locale = locale;
  }

  public String getGuildLocale() {
    return guildLocale;
  }

  public void setGuildLocale(String guildLocale) {
    this.guildLocale = guildLocale;
  }

  public Interaction createSanitizedCopy() {
    Interaction sanitized = new Interaction();
    sanitized.setType(this.type);
    sanitized.setId(this.id);
    sanitized.setApplicationId(this.applicationId);
    // Token is intentionally NOT copied - sensitive data
    sanitized.setData(this.data);
    sanitized.setGuildId(this.guildId);
    sanitized.setChannelId(this.channelId);
    sanitized.setMember(this.member);
    sanitized.setUser(this.user);
    sanitized.setLocale(this.locale);
    sanitized.setGuildLocale(this.guildLocale);
    return sanitized;
  }
}
