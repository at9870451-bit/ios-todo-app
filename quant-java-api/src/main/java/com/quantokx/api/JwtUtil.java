package com.quantokx.api;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.JwtException;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Date;

/**
 * Console 管理后台 JWT（HS256）。
 * 密钥来源：环境变量 ADMIN_JWT_SECRET 优先；否则使用 sys_config 里的 admin_jwt_secret（首次启动自动生成并持久化）。
 * Token 会话存 Redis（qb:admintoken:{jti} -> adminId），登出即删除；Redis 降级时退化为纯无状态校验。
 */
public final class JwtUtil {
    public static final long TTL_SECONDS = 12 * 3600;
    private static volatile String cachedSecret;
    private static final SecureRandom RND = new SecureRandom();

    static String secret() {
        String s = cachedSecret;
        if (s != null) return s;
        synchronized (JwtUtil.class) {
            if (cachedSecret != null) return cachedSecret;
            String env = System.getenv("ADMIN_JWT_SECRET");
            if (env != null && env.length() >= 16) { cachedSecret = env; return env; }
            String v = null;
            try { Object o = Db.scalar("SELECT v FROM sys_config WHERE k='admin_jwt_secret'"); v = o == null ? null : o.toString(); }
            catch (Exception ignore) {}
            if (v == null || v.length() < 16) {
                byte[] b = new byte[32]; RND.nextBytes(b);
                StringBuilder sb = new StringBuilder();
                for (byte x : b) sb.append(String.format("%02x", x));
                v = sb.toString();
                try { Db.upd("INSERT INTO sys_config(k,v,remark) VALUES('admin_jwt_secret',?,'后台JWT密钥(自动生成)') ON DUPLICATE KEY UPDATE v=VALUES(v)", v); }
                catch (Exception ignore) {}
            }
            cachedSecret = v;
            return v;
        }
    }

    public static String issue(long adminId, String username, String jti) {
        Date now = new Date();
        return Jwts.builder()
                .subject(username)
                .claim("aid", adminId)
                .id(jti)
                .issuedAt(now)
                .expiration(new Date(now.getTime() + TTL_SECONDS * 1000))
                .signWith(io.jsonwebtoken.security.Keys.hmacShaKeyFor(secret().getBytes(StandardCharsets.UTF_8)))
                .compact();
    }

    /** 解析并校验签名/过期；失败返回 null */
    public static Claims parse(String token) {
        try {
            return Jwts.parser().verifyWith(io.jsonwebtoken.security.Keys.hmacShaKeyFor(secret().getBytes(StandardCharsets.UTF_8)))
                    .build().parseSignedClaims(token).getPayload();
        } catch (JwtException | IllegalArgumentException e) {
            return null;
        }
    }

    private JwtUtil() {}
}
