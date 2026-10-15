package com.quantokx.api;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

/**
 * 易支付（彩虹易支付兼容协议）对接。
 * 配置来自 sys_config：pay_api_url（接口地址）、pay_pid（商户号）、pay_key（密钥）。
 * 签名：参与参数按字典序升序拼接 k=v&...&key=密钥，MD5 小写。
 */
public final class PaymentSvc {

    /**
     * 通过易支付 mapi.php（POST）创建支付单，返回网关收银台 payurl；失败返回 null。
     * 注意：①新版彩虹网关必须带 clientip ②name 需纯 ASCII（含中文/空格时部分网关签名校验失败）
     */
    public static String buildPayUrl(String tradeNo, double amount, String channel, String clientIp) {
        String api = IosCtl.cfg("pay_api_url", "");
        String pid = IosCtl.cfg("pay_pid", "");
        String key = IosCtl.cfg("pay_key", "");
        if (api.isBlank() || pid.isBlank() || key.isBlank()) return null;
        String endpoint = api.endsWith("/") ? api + "mapi.php" : api + "/mapi.php";
        String notifyUrl = IosCtl.cfg("site_base_url", "http://154.12.16.204:8080") + "/api/member/notify";
        String returnUrl = IosCtl.cfg("pay_return_url", "http://154.12.16.204:8080/panel");
        // TreeMap：参数名字典序，与签名顺序一致
        Map<String, String> p = new TreeMap<>();
        p.put("pid", pid);
        p.put("type", channel.isBlank() ? "alipay" : channel);
        p.put("out_trade_no", tradeNo);
        p.put("notify_url", notifyUrl);
        p.put("return_url", returnUrl);
        p.put("name", "Amore VIP");
        p.put("money", String.format("%.2f", amount));
        p.put("clientip", clientIp == null || clientIp.isBlank() ? "154.12.16.204" : clientIp);
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> e : p.entrySet()) {
            if (sb.length() > 0) sb.append('&');
            sb.append(e.getKey()).append('=').append(e.getValue());
        }
        sb.append(key);
        p.put("sign", md5(sb.toString()));
        p.put("sign_type", "MD5");
        StringBuilder body = new StringBuilder();
        boolean first = true;
        for (Map.Entry<String, String> e : p.entrySet()) {
            if (!first) body.append('&');
            body.append(e.getKey()).append('=').append(urlEncode(e.getValue()));
            first = false;
        }
        try {
            java.net.http.HttpClient http = java.net.http.HttpClient.newHttpClient();
            java.net.http.HttpRequest req = java.net.http.HttpRequest.newBuilder()
                    .uri(java.net.URI.create(endpoint))
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .timeout(java.time.Duration.ofSeconds(15))
                    .POST(java.net.http.HttpRequest.BodyPublishers.ofString(body.toString()))
                    .build();
            java.net.http.HttpResponse<String> resp =
                    http.send(req, java.net.http.HttpResponse.BodyHandlers.ofString());
            String out = resp.body() == null ? "" : resp.body();
            java.util.regex.Matcher m = java.util.regex.Pattern
                    .compile("\"payurl\"\\s*:\\s*\"([^\"]+)\"").matcher(out);
            if (m.find()) return m.group(1).replace("\\/", "/");
            System.out.println("[Pay] mapi no payurl: " + out);
            return null;
        } catch (Exception e) {
            System.out.println("[Pay] mapi error: " + e);
            return null;
        }
    }

    /** 异步通知验签 */
    public static boolean verifyNotify(Map<String, String> params) {
        String key = IosCtl.cfg("pay_key", "");
        if (key.isBlank()) return false;
        String given = params.get("sign");
        if (given == null || given.isBlank()) return false;
        Map<String, String> p = new TreeMap<>();
        for (Map.Entry<String, String> e : params.entrySet()) {
            String k = e.getKey();
            String v = e.getValue();
            if ("sign".equals(k) || "sign_type".equals(k) || v == null || v.isBlank()) continue;
            p.put(k, v);
        }
        return sign(p, key).equalsIgnoreCase(given);
    }

    static String sign(Map<String, String> params, String key) {
        List<String> keys = new ArrayList<>(params.keySet());
        Collections.sort(keys);
        StringBuilder sb = new StringBuilder();
        for (String k : keys) {
            if ("sign".equals(k) || "sign_type".equals(k)) continue;
            String v = params.get(k);
            if (v == null || v.isBlank()) continue;
            if (sb.length() > 0) sb.append('&');
            sb.append(k).append('=').append(v);
        }
        sb.append(key);
        return md5(sb.toString());
    }

    static String md5(String s) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] b = md.digest(s.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte x : b) sb.append(String.format("%02x", x));
            return sb.toString();
        } catch (Exception e) { throw new RuntimeException(e); }
    }

    static String urlEncode(String s) {
        try { return java.net.URLEncoder.encode(s, StandardCharsets.UTF_8); } catch (Exception e) { return s; }
    }

    private PaymentSvc() {}
}
