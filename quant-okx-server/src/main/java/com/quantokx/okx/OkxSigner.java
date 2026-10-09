package com.quantokx.okx;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Base64;
import java.util.Locale;

/**
 * OKX V5 签名工具。
 * <pre>
 * sign = Base64( HMAC-SHA256( timestamp + METHOD + requestPath + body, secret ) )
 * </pre>
 * - timestamp 格式 yyyy-MM-dd'T'HH:mm:ss.SSS'Z'（UTC，毫秒 3 位）
 * - requestPath 必须包含 query string（与真正发出去的路径完全一致）
 * <p>
 * 对照 quant-okx-ios/QuantOKX/Sources/Networking/OKXClient.swift 的 timestamp()/sign()。
 */
public final class OkxSigner {

    private static final DateTimeFormatter TIMESTAMP_FORMAT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).withZone(ZoneOffset.UTC);

    private OkxSigner() {
    }

    /** 当前 UTC 时间戳（毫秒 3 位） */
    public static String timestamp() {
        return TIMESTAMP_FORMAT.format(Instant.now());
    }

    /**
     * 生成签名。
     *
     * @param timestamp   与 OK-ACCESS-TIMESTAMP 头一致的字符串
     * @param method      HTTP 方法（内部会转大写）
     * @param requestPath 形如 /api/v5/market/ticker?instId=BTC-USDT-SWAP
     * @param body        请求体（GET 传空字符串）
     * @param secret      API secret
     */
    public static String sign(String timestamp, String method, String requestPath, String body, String secret) {
        String message = timestamp
                + method.toUpperCase(Locale.US)
                + requestPath
                + (body == null ? "" : body);
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] digest = mac.doFinal(message.getBytes(StandardCharsets.UTF_8));
            return Base64.getEncoder().encodeToString(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("HMAC-SHA256 不可用", e);
        } catch (InvalidKeyException e) {
            throw new IllegalArgumentException("HMAC 密钥无效", e);
        }
    }
}
