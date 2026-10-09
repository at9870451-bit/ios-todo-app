package com.quantokx.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 启动级配置（application.yml 的 quantokx.* 前缀）。
 * 与运行时可热更新的 AppConfig 区分：这里放的是「改一次要重启」的内容。
 */
@Component
@ConfigurationProperties(prefix = "quantokx")
public class QuantOkxProperties {

    /** 前端 X-Auth-Token 鉴权令牌，默认 changeme（生产必须改） */
    private String authToken = "changeme";

    /** 对外版本号（GET /api/health） */
    private String version = "1.0.0";

    /** 配置持久化目录（./data/config.json，权限 600） */
    private String dataDir = "./data";

    /** OKX 接口基础地址 */
    private String baseUrl = "https://www.okx.com";

    /** @Scheduled 调度心跳（毫秒），引擎据此判断是否到了下一轮轮询 */
    private long pollPulseMillis = 1000L;

    public String getAuthToken() {
        return authToken;
    }

    public void setAuthToken(String authToken) {
        this.authToken = authToken;
    }

    public String getVersion() {
        return version;
    }

    public void setVersion(String version) {
        this.version = version;
    }

    public String getDataDir() {
        return dataDir;
    }

    public void setDataDir(String dataDir) {
        this.dataDir = dataDir;
    }

    public String getBaseUrl() {
        return baseUrl;
    }

    public void setBaseUrl(String baseUrl) {
        this.baseUrl = baseUrl;
    }

    public long getPollPulseMillis() {
        return pollPulseMillis;
    }

    public void setPollPulseMillis(long pollPulseMillis) {
        this.pollPulseMillis = pollPulseMillis;
    }
}
