package com.quantokx.dollstudio.auth;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

/** HMAC 签名 token：base64(uid:expiry:hmac) —— 30 天有效 */
public final class TokenUtil {
    private TokenUtil() {}

    public static String issue(long userId, long expiryEpochSec, String secret) {
        String payload = userId + ":" + expiryEpochSec;
        return Base64.getEncoder().encodeToString(payload + ":" + hmac(payload, secret));
    }

    public static String issue(long userId, String secret) {
        return issue(userId, System.currentTimeMillis() / 1000 + 30L * 86400, secret);
    }

    /** 校验并返回 userId；失败抛 IllegalArgumentException */
    public static long verify(String token, String secret) {
        try {
            String decoded = new String(Base64.getDecoder().decode(token), StandardCharsets.UTF_8);
            String[] parts = decoded.split(":");
            if (parts.length != 3) throw new IllegalArgumentException("格式无效");
            long uid = Long.parseLong(parts[0]);
            long exp = Long.parseLong(parts[1]);
            if (exp < System.currentTimeMillis() / 1000) throw new IllegalArgumentException("已过期");
            if (!hmac(parts[0] + ":" + parts[1], secret).equals(parts[2]))
                throw new IllegalArgumentException("签名不符");
            return uid;
        } catch (IllegalArgumentException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalArgumentException("token 解析失败");
        }
    }

    private static String hmac(String data, String secret) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] out = mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : out) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
