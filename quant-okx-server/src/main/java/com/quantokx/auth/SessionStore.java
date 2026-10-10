package com.quantokx.auth;

import org.springframework.stereotype.Component;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 会话令牌（内存态，重启即失效——重启后用户重新登录即可）。
 * token = 32 字节随机 hex；有效期 7 天。
 */
@Component
public class SessionStore {

    private static final long TTL_SECONDS = 7L * 24 * 3600;
    private static final SecureRandom RNG = new SecureRandom();

    private record Session(String userId, Instant expiresAt) {
    }

    private final Map<String, Session> sessions = new ConcurrentHashMap<>();

    /** 登录/注册成功后签发令牌 */
    public String issue(String userId) {
        byte[] raw = new byte[32];
        RNG.nextBytes(raw);
        String token = HexFormat.of().formatHex(raw);
        sessions.put(token, new Session(userId, Instant.now().plusSeconds(TTL_SECONDS)));
        return token;
    }

    /** 解析令牌 → userId；无效或过期返回 null */
    public String resolve(String token) {
        if (token == null || token.isBlank()) {
            return null;
        }
        Session s = sessions.get(token);
        if (s == null) {
            return null;
        }
        if (s.expiresAt().isBefore(Instant.now())) {
            sessions.remove(token);
            return null;
        }
        return s.userId();
    }

    /** 登出 */
    public void revoke(String token) {
        if (token != null) {
            sessions.remove(token);
        }
    }

    /** 清理过期会话（由心跳定期调用） */
    public int prune() {
        Instant now = Instant.now();
        int n = 0;
        for (Map.Entry<String, Session> e : sessions.entrySet()) {
            if (e.getValue().expiresAt().isBefore(now)) {
                sessions.remove(e.getKey());
                n++;
            }
        }
        return n;
    }

    public int size() {
        return sessions.size();
    }
}