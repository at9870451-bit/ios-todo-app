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

    /** 构造收银台跳转地址；配置不完整返回 null */
    public static String buildPayUrl(String tradeNo, double amount, String channel) {
        String api = IosCtl.cfg("pay_api_url", "");
        String pid = IosCtl.cfg("pay_pid", "");
        String key = IosCtl.cfg("pay_key", "");
        if (api.isBlank() || pid.isBlank() || key.isBlank()) return null;
        String notifyUrl = IosCtl.cfg("site_base_url", "http://154.12.16.204:8080") + "/api/member/notify";
        String returnUrl = IosCtl.cfg("pay_return_url", "http://154.12.16.204:8080/panel");
        Map<String, String> p = new LinkedHashMap<>();
        p.put("pid", pid);
        p.put("type", channel.isBlank() ? "alipay" : channel);
        p.put("out_trade_no", tradeNo);
        p.put("notify_url", notifyUrl);
        p.put("return_url", returnUrl);
        p.put("name", "Amore 会员 " + tradeNo);
        p.put("money", String.format("%.2f", amount));
        p.put("sign", sign(p, key));
        p.put("sign_type", "MD5");
        StringBuilder sb = new StringBuilder(api);
        sb.append(api.contains("?") ? "&" : "?");
        boolean first = true;
        for (Map.Entry<String, String> e : p.entrySet()) {
            if (!first) sb.append('&');
            sb.append(e.getKey()).append('=').append(urlEncode(e.getValue()));
            first = false;
        }
        return sb.toString();
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
