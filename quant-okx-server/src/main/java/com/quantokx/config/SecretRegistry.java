package com.quantokx.config;

import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 全局密钥注册表（多租户脱敏用）：
 * 各用户的 ConfigStore 在启动与每次更新时把自己的密钥登记进来，
 * SecretScrubber 据此把日志/异常里的密钥替换成 ****。
 */
@Component
public class SecretRegistry {

    private final Set<String> secrets = ConcurrentHashMap.newKeySet();

    /** 登记一个密钥（太短的忽略，避免误伤正常文本） */
    public void register(String v) {
        if (v != null && v.length() >= 4) {
            secrets.add(v);
        }
    }

    /** 当前所有已知密钥 */
    public List<String> all() {
        return List.copyOf(secrets);
    }
}