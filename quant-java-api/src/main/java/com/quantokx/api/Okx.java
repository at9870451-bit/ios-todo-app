package com.quantokx.api;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.math.BigDecimal;
import java.math.MathContext;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;

public final class Okx {
    public record Creds(String key, String secret, String passphrase, boolean demo) {
        public boolean complete() { return key != null && !key.isEmpty() && secret != null && !secret.isEmpty() && passphrase != null && !passphrase.isEmpty(); }
    }
    public record Inst(double ctVal, double lotSz, double minSz, double tickSz) {}
    public record OrderAck(String ordId, String sCode, String sMsg) {}

    private static final String BASE = "https://www.okx.com";
    private final HttpClient http;
    private final Map<String, Inst> instCache = new ConcurrentHashMap<>();

    public Okx() { http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build(); }

    public List<Map<String, Object>> ticker(String instId) { return toMaps(envelope(send(null, "GET", "/api/v5/market/ticker?instId=" + u(instId), null))); }
    public List<Map<String, Object>> tickers(String instType) { return toMaps(envelope(send(null, "GET", "/api/v5/market/tickers?instType=" + u(instType), null))); }
    public List<Map<String, Object>> instruments(String instType) { return toMaps(envelope(send(null, "GET", "/api/v5/public/instruments?instType=" + u(instType), null))); }
    public List<List<Object>> candles(String instId, String bar, int limit) {
        var data = envelope(send(null, "GET", "/api/v5/market/candles?instId=" + u(instId) + "&bar=" + u(bar) + "&limit=" + limit, null));
        List<List<Object>> out = new ArrayList<>();
        for (var row : data) {
            List<Object> c = new ArrayList<>();
            c.add(Long.parseLong(row.get(0).asText()));
            for (int i = 1; i <= 5; i++) c.add(row.get(i).asText());
            out.add(c);
        }
        Collections.reverse(out); return out;
    }
    public Map<String, Object> instrument(String instId) {
        Inst c = instCache.get(instId);
        if (c != null) return Map.of("ctVal", c.ctVal(), "lotSz", c.lotSz(), "minSz", c.minSz(), "tickSz", c.tickSz());
        String it = instId.endsWith("-SWAP") ? "SWAP" : "SPOT";
        var list = toMaps(envelope(send(null, "GET", "/api/v5/public/instruments?instType=" + u(it) + "&instId=" + u(instId), null)));
        if (list.isEmpty()) throw new OkxErr("decode", "找不到合约 " + instId);
        var i = list.get(0);
        Inst info = new Inst(num(i.get("ctVal"), 1), num(i.get("lotSz"), 1), num(i.get("minSz"), 1), num(i.get("tickSz"), 0.1));
        instCache.put(instId, info); return i;
    }
    public List<Map<String, Object>> instrumentsAll(String instType) { return toMaps(envelope(send(null, "GET", "/api/v5/public/instruments?instType=" + u(instType), null))); }
    public List<Map<String, Object>> balance(Creds c) { return toMaps(envelope(send(c, "GET", "/api/v5/account/balance", null))); }
    public List<Map<String, Object>> positions(Creds c, String instType) {
        List<Map<String, Object>> all = toMaps(envelope(send(c, "GET", "/api/v5/account/positions?instType=" + u(instType), null)));
        List<Map<String, Object>> out = new ArrayList<>();
        for (var p : all) if (Math.abs(num(p.get("pos"))) > 0) out.add(p);
        return out;
    }
    public List<Map<String, Object>> pendingOrders(Creds c, String instId) {
        String q = instId == null || instId.isEmpty() ? "?instType=SWAP" : "?instId=" + u(instId);
        return toMaps(envelope(send(c, "GET", "/api/v5/trade/orders-pending" + q, null)));
    }
    public List<Map<String, Object>> orderHistory(Creds c, String instType, int limit) {
        return toMaps(envelope(send(c, "GET", "/api/v5/trade/orders-history-archive?instType=" + u(instType) + "&limit=" + Math.min(100, Math.max(1, limit)), null)));
    }
    public Map<String, Object> accountConfig(Creds c) {
        List<Map<String, Object>> list = toMaps(envelope(send(c, "GET", "/api/v5/account/config", null)));
        return list.isEmpty() ? Map.of() : list.get(0);
    }
    public OrderAck placeOrder(Creds c, Map<String, Object> op, Double slPx, Double tpPx) {
        if (slPx != null || tpPx != null) {
            List<Map<String, Object>> attach = new ArrayList<>();
            Map<String, Object> algo = new LinkedHashMap<>();
            if (tpPx != null) { algo.put("tpTriggerPx", fmtPx(tpPx)); algo.put("tpOrdPx", "-1"); }
            if (slPx != null) { algo.put("slTriggerPx", fmtPx(slPx)); algo.put("slOrdPx", "-1"); }
            attach.add(algo); op.put("attachAlgoOrds", attach);
        }
        var list = toMaps(envelope(send(c, "POST", "/api/v5/trade/order", json(op))));
        if (list.isEmpty()) throw new OkxErr("decode", "下单无返回");
        var first = list.get(0);
        String sCode = str(first.get("sCode"));
        if (!"0".equals(sCode)) throw new OkxErr(sCode, "OKX 下单失败 " + sCode + "：" + str(first.get("sMsg")));
        return new OrderAck(str(first.get("ordId")), sCode, str(first.get("sMsg")));
    }
    public void cancelOrder(Creds c, String instId, String ordId) {
        Map<String, Object> p = new LinkedHashMap<>(); p.put("instId", instId); p.put("ordId", ordId);
        envelope(send(c, "POST", "/api/v5/trade/cancel-order", json(p)));
    }
    public void closePosition(Creds c, String instId, String posSide) {
        Map<String, Object> p = new LinkedHashMap<>(); p.put("instId", instId); p.put("mgnMode", "cross");
        if (instId.endsWith("-SWAP")) p.put("posSide", posSide);
        envelope(send(c, "POST", "/api/v5/trade/close-position", json(p)));
    }
    public void setLeverage(Creds c, String instId, int lever, String mgnMode) {
        Map<String, Object> p = new LinkedHashMap<>(); p.put("instId", instId); p.put("lever", String.valueOf(lever)); p.put("mgnMode", mgnMode);
        envelope(send(c, "POST", "/api/v5/account/set-leverage", json(p)));
    }
    public String positionMode(Creds c) {
        List<Map<String, Object>> list = toMaps(envelope(send(c, "GET", "/api/v5/account/config", null)));
        return list.isEmpty() ? "net_mode" : str(list.get(0).get("posMode"));
    }

    private record Raw(int status, String body) {}
    private Raw send(Creds c, String method, String pathWithQuery, String jsonBody) {
        try {
            String ts = okxTs();
            HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(BASE + pathWithQuery)).timeout(Duration.ofSeconds(25)).header("Content-Type", "application/json");
            if (c != null) {
                if (!c.complete()) throw new OkxErr("no-credentials", "未配置 OKX API 密钥");
                String body = jsonBody == null ? "" : jsonBody;
                b.header("OK-ACCESS-KEY", c.key()).header("OK-ACCESS-TIMESTAMP", ts)
                 .header("OK-ACCESS-PASSPHRASE", c.passphrase())
                 .header("OK-ACCESS-SIGN", sign(c.secret(), ts, method, pathWithQuery, body));
                if (c.demo()) b.header("x-simulated-trading", "1");
            }
            if (jsonBody != null) b.method(method, HttpRequest.BodyPublishers.ofString(jsonBody, StandardCharsets.UTF_8));
            else b.method(method, HttpRequest.BodyPublishers.noBody());
            HttpResponse<String> r = http.send(b.build(), HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            return new Raw(r.statusCode(), r.body());
        } catch (java.io.IOException e) { throw new OkxErr("network", "网络错误：" + e.getMessage()); }
        catch (InterruptedException e) { Thread.currentThread().interrupt(); throw new OkxErr("network", "请求被中断"); }
    }
    private com.fasterxml.jackson.databind.JsonNode envelope(Raw r) {
        try {
            var m = new com.fasterxml.jackson.databind.ObjectMapper();
            var root = m.readTree(r.body());
            String code = root.path("code").asText("");
            if (!"0".equals(code)) throw new OkxErr(code, "OKX 返回错误 " + code + "：" + root.path("msg").asText("未知错误"));
            var data = root.path("data");
            if (data.isMissingNode()) throw new OkxErr("decode", "响应缺少 data");
            return data;
        } catch (OkxErr e) { throw e; }
        catch (Exception e) { throw new OkxErr("decode", "响应解析失败：" + e.getMessage()); }
    }
    private static String okxTs() {
        return java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(java.time.ZoneOffset.UTC).format(java.time.Instant.now());
    }
    private static String sign(String secret, String ts, String method, String path, String body) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return Base64.getEncoder().encodeToString(mac.doFinal((ts + method.toUpperCase() + path + body).getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) { throw new RuntimeException(e); }
    }
    public static String fmtPx(double v) { return new BigDecimal(Double.toString(v)).round(new MathContext(12)).stripTrailingZeros().toPlainString(); }
    public static double num(Object o, double dft) { if (o == null) return dft; if (o instanceof Number n) return n.doubleValue(); try { return Double.parseDouble(o.toString()); } catch (Exception e) { return dft; } }
    public static String enc(String s) { return URLEncoder.encode(s, StandardCharsets.UTF_8); }
    public static String json(Object o) { try { return new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(o); } catch (Exception e) { throw new RuntimeException(e); } }
    public static String str(Object o) { return o == null ? "" : o.toString(); }
    @SuppressWarnings("unchecked")
    public static List<Map<String, Object>> toMaps(com.fasterxml.jackson.databind.JsonNode arr) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (var item : arr) {
            Map<String, Object> m = new LinkedHashMap<>();
            var it = item.fields();
            while (it.hasNext()) { var e = it.next(); if (!e.getValue().isNull()) m.put(e.getKey(), e.getValue()); }
            out.add(m);
        }
        return out;
    }

    public static final class OkxErr extends RuntimeException {
        public final String code;
        public OkxErr(String code, String message) { super(message); this.code = code; }
    }
}
