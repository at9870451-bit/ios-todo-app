package com.quantokx.config;

import com.quantokx.store.ConfigStore;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * 密钥脱敏工具：任何要写进日志、异常消息、接口返回的文本，先过这里。
 * 把当前生效的所有密钥（OKX key/secret/passphrase、AI key，含环境变量来源）替换成 ****。
 */
@Component
public class SecretScrubber {

    private static final String MASK = "****";

    private final ConfigStore configStore;

    public SecretScrubber(ConfigStore configStore) {
        this.configStore = configStore;
    }

    public String scrub(String message) {
        if (message == null || message.isEmpty()) {
            return message;
        }
        String out = message;
        List<String> secrets = configStore.secretCandidates();
        for (String s : secrets) {
            if (out.contains(s)) {
                out = out.replace(s, MASK);
            }
        }
        return out;
    }
}
