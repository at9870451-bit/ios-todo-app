package com.quantokx.okx;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.quantokx.config.QuantOkxProperties;
import com.quantokx.model.Balance;
import com.quantokx.model.Candle;
import com.quantokx.model.OpenOrder;
import com.quantokx.model.OrderResult;
import com.quantokx.model.Position;
import com.quantokx.model.Ticker;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.math.BigDecimal;
import java.math.MathContext;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * OKX V5 REST 客户端（基于 JDK 自带 java.net.http.HttpClient，无第三方 HTTP 依赖）。
 * <p>
 * 签名：Base64(HMAC-SHA256(timestamp + method + requestPath(含 query) + body, secret))，见 {@link OkxSigner}。
 * 对照 quant-okx-ios/QuantOKX/Sources/Networking/OKXClient.swift，接口路径与参数完全一致：
 * - /api/v5/market/ticker、/api/v5/market/candles（公开）
 * - /api/v5/account/balance、/api/v5/account/positions、/api/v5/trade/orders-pending（签名）
 * - /api/v5/public/instruments（公开，结果缓存）
 * - /api/v5/account/set-leverage、/api/v5/trade/order、/api/v5/trade/close-position、/api/v5/trade/cancel-order（签名）
 */
@Component
public class OkxClient {

    private static final TypeReference<List<JsonNode>> JSON_LIST = new TypeReference<>() {
    };
    private static final int ERROR_SNIPPET_LIMIT = 200;

    private final HttpClient http;
    private final ObjectMapper mapper;
    private final String baseUrl;

    /** 合约面值缓存：instId -> (ctVal, lotSz, minSz)。与 iOS 端 actor 内的字典缓存一致 */
    private final Map<String, InstrumentInfo> instruments = new ConcurrentHashMap<>();

    public OkxClient(ObjectMapper mapper, QuantOkxProperties properties) {
        this.mapper = mapper;
        this.baseUrl = properties.getBaseUrl();
        this.http = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
    }

    /**
     * 一组 OKX 凭据 + 模拟盘开关。每次调用显式传入，避免可变全局状态带来的并发问题。
     */
    public record Credentials(String apiKey, String apiSecret, String passphrase, boolean demo) {

        public boolean isComplete() {
            return apiKey != null && !apiKey.isEmpty()
                    && apiSecret != null && !apiSecret.isEmpty()
                    && passphrase != null && !passphrase.isEmpty();
        }
    }

    /** 合约参数：面值 / 最小变动 / 最小下单量 */
    public record InstrumentInfo(double ctVal, double lotSz, double minSz) {
    }

    /** OKX instruments 原始条目 */
    @JsonIgnoreProperties(ignoreUnknown = true)
    record OkxInstrument(String instId, String ctVal, String lotSz, String minSz, String state) {
    }

    /** account/balance 的 data[] 元素（我们只关心 details） */
    @JsonIgnoreProperties(ignoreUnknown = true)
    record AccountDetails(List<Balance> details) {
    }

    // ------------------------------------------------------------------ 行情（公开，无需签名）

    /** 最新行情。对照 Swift: func ticker(_ instId: String) async throws -> Ticker */
    public Ticker ticker(String instId) throws OkxException {
        List<Ticker> list = request("GET", "/api/v5/market/ticker",
                q("instId", instId), null, new TypeReference<List<Ticker>>() {
                }, null);
        if (list == null || list.isEmpty()) {
            throw new OkxException("decode", "无行情");
        }
        return list.get(0);
    }

    /**
     * K 线。OKX 返回「新 → 旧」，这里反转为「旧 → 新」（契约要求）。
     * 对照 Swift: func candles(_ instId: String, bar: String, limit: Int = 100) async throws -> [Candle]
     */
    public List<Candle> candles(String instId, String bar, int limit) throws OkxException {
        List<List<String>> raw = request("GET", "/api/v5/market/candles",
                q("instId", instId, "bar", bar, "limit", String.valueOf(limit)), null,
                new TypeReference<List<List<String>>>() {
                }, null);
        List<Candle> out = new ArrayList<>();
        if (raw != null) {
            for (List<String> row : raw) {
                Candle c = Candle.fromOkx(row);
                if (c != null) {
                    out.add(c);
                }
            }
        }
        Collections.reverse(out);
        return out;
    }

    // ------------------------------------------------------------------ 账户（签名）

    /** 资金账户 USDT 等明细。对照 Swift: func balance() async throws -> [Balance] */
    public List<Balance> balance(Credentials creds) throws OkxException {
        List<AccountDetails> accs = request("GET", "/api/v5/account/balance", null, null,
                new TypeReference<List<AccountDetails>>() {
                }, creds);
        if (accs == null || accs.isEmpty() || accs.get(0).details() == null) {
            return new ArrayList<>();
        }
        return accs.get(0).details();
    }

    /** 持仓（不过滤 instId，但过滤掉 pos=0 的空仓，与 iOS 一致）。 */
    public List<Position> positions(Credentials creds, String instType) throws OkxException {
        List<Position> p = request("GET", "/api/v5/account/positions",
                q("instType", instType), null, new TypeReference<List<Position>>() {
                }, creds);
        List<Position> out = new ArrayList<>();
        if (p != null) {
            for (Position x : p) {
                if (!x.isEmpty()) {
                    out.add(x);
                }
            }
        }
        return out;
    }

    /** 未成交委托。对照 Swift: func pendingOrders(_ instId: String) */
    public List<OpenOrder> pendingOrders(Credentials creds, String instId) throws OkxException {
        return request("GET", "/api/v5/trade/orders-pending",
                q("instId", instId), null, new TypeReference<List<OpenOrder>>() {
                }, creds);
    }

    // ------------------------------------------------------------------ 合约参数 / 张数换算

    /**
     * 查询（并缓存）合约参数。对照 Swift: func instrument(_ instId: String)
     */
    public InstrumentInfo instrument(String instId) throws OkxException {
        InstrumentInfo cached = instruments.get(instId);
        if (cached != null) {
            return cached;
        }
        String instType = instId.endsWith("-SWAP") ? "SWAP" : "SPOT";
        List<OkxInstrument> list = request("GET", "/api/v5/public/instruments",
                q("instType", instType, "instId", instId), null,
                new TypeReference<List<OkxInstrument>>() {
                }, null);
        if (list == null || list.isEmpty()) {
            throw new OkxException("decode", "找不到合约 " + instId);
        }
        OkxInstrument i = list.get(0);
        InstrumentInfo info = new InstrumentInfo(
                parseDoubleOr(i.ctVal(), 1),
                parseDoubleOr(i.lotSz(), 1),
                parseDoubleOr(i.minSz(), 1));
        instruments.put(instId, info);
        return info;
    }

    /**
     * 把「多少 USDT」换算成 OKX 下单的 sz（张数/币数）。
     * <pre>
     * 合约：sz = floor( usdt * leverage / (ctVal * price) / lotSz ) * lotSz，不小于 minSz
     * 现货：sz = floor( usdt / price / lotSz ) * lotSz，不小于 minSz
     * </pre>
     * 与 iOS 端 sizeFor 数值一致（额外做了一次 1e-9 的浮点保护 + 12 位有效数字清洗）。
     */
    public double sizeFor(String instId, double usdt, double price, int leverage) throws OkxException {
        if (!(price > 0)) {
            throw new OkxException("param", "价格无效，无法换算下单数量");
        }
        if (!(usdt > 0)) {
            throw new OkxException("param", "下单金额必须大于 0");
        }
        InstrumentInfo inst = instrument(instId);
        if (instId.endsWith("-SWAP")) {
            double ctVal = inst.ctVal() > 0 ? inst.ctVal() : 1;
            double lotSz = inst.lotSz() > 0 ? inst.lotSz() : 1;
            double notional = usdt * leverage;
            double raw = notional / (ctVal * price);
            double sz = Math.floor(raw / lotSz + 1e-9) * lotSz;
            return roundSize(Math.max(inst.minSz(), sz));
        }
        double raw = usdt / price;
        double step = inst.lotSz() > 0 ? inst.lotSz() : 0.00000001;
        double sz = Math.floor(raw / step + 1e-9) * step;
        return roundSize(Math.max(inst.minSz(), sz));
    }

    // ------------------------------------------------------------------ 交易（签名）

    /**
     * 设置杠杆（仅 SWAP）。对照 Swift: func setLeverage(instId:lever:)
     */
    public void setLeverage(Credentials creds, String instId, int lever) throws OkxException {
        if (!instId.endsWith("-SWAP")) {
            return;
        }
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("instId", instId);
        body.put("lever", String.valueOf(lever));
        body.put("mgnMode", "cross");
        request("POST", "/api/v5/account/set-leverage", null, body, JSON_LIST, creds);
    }

    /**
     * 市价下单。
     * 对照 Swift: func marketOrder(instId:side:posSide:sz:tdMode:) async throws -> OrderResult
     * 注意：现货不带 posSide（与 iOS 一致）。
     */
    public OrderResult marketOrder(Credentials creds, String instId, String side, String posSide, double sz,
                                   String tdMode) throws OkxException {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("instId", instId);
        body.put("tdMode", tdMode == null || tdMode.isEmpty() ? "cross" : tdMode);
        body.put("side", side);
        body.put("ordType", "market");
        body.put("sz", formatSize(sz));
        if (instId.endsWith("-SWAP")) {
            body.put("posSide", posSide);
        }
        List<OrderResult> r = request("POST", "/api/v5/trade/order", null, body,
                new TypeReference<List<OrderResult>>() {
                }, creds);
        if (r == null || r.isEmpty()) {
            throw new OkxException("decode", "下单无返回");
        }
        OrderResult first = r.get(0);
        if (!first.ok()) {
            String code = first.sCode() == null ? "unknown" : first.sCode();
            String msg = first.sMsg() == null ? "" : first.sMsg();
            throw new OkxException(code, "OKX 返回错误 " + code + "：" + msg);
        }
        return first;
    }

    /**
     * 市价全平。对照 Swift: func closePosition(instId:posSide:mgnMode:)
     */
    public void closePosition(Credentials creds, String instId, String posSide) throws OkxException {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("instId", instId);
        body.put("mgnMode", "cross");
        if (instId.endsWith("-SWAP")) {
            body.put("posSide", posSide);
        }
        List<JsonNode> r = request("POST", "/api/v5/trade/close-position", null, body, JSON_LIST, creds);
        if (r == null || r.isEmpty()) {
            return;
        }
        JsonNode first = r.get(0);
        String code = first.hasNonNull("sCode") ? first.get("sCode").asText() : null;
        if (code != null && !"0".equals(code)) {
            String msg = first.path("sMsg").asText("");
            throw new OkxException(code, "OKX 返回错误 " + code + "：" + msg);
        }
    }

    /** 撤单。对照 Swift: func cancelOrder(instId:ordId:) */
    public void cancelOrder(Credentials creds, String instId, String ordId) throws OkxException {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("instId", instId);
        body.put("ordId", ordId);
        request("POST", "/api/v5/trade/cancel-order", null, body, JSON_LIST, creds);
    }

    // ------------------------------------------------------------------ 工具

    /**
     * 下单数量格式化：去除浮点尾巴和多余 0（12 位有效数字），输出普通十进制字符串，
     * 避免 "3.0000000000000004" / "1.0E-8" 这类 OKX 不能接受的格式。
     */
    public static String formatSize(double size) {
        if (!Double.isFinite(size) || size <= 0) {
            throw new IllegalArgumentException("下单数量必须为正数: " + size);
        }
        return new BigDecimal(Double.toString(size))
                .round(new MathContext(12))
                .stripTrailingZeros()
                .toPlainString();
    }

    private static double roundSize(double v) {
        return new BigDecimal(Double.toString(v)).round(new MathContext(12)).stripTrailingZeros().doubleValue();
    }

    private static double parseDoubleOr(String v, double fallback) {
        if (v == null || v.isEmpty()) {
            return fallback;
        }
        try {
            return Double.parseDouble(v);
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    /** 有序 query 参数表（LinkedHashMap 保证同一请求 URL 与签名串使用完全相同的顺序） */
    private static Map<String, String> q(String... kv) {
        if (kv.length % 2 != 0) {
            throw new IllegalArgumentException("query 参数必须成对出现");
        }
        Map<String, String> m = new LinkedHashMap<>();
        for (int i = 0; i < kv.length; i += 2) {
            m.put(kv[i], kv[i + 1]);
        }
        return m;
    }

    private static String buildQuery(Map<String, String> query) {
        if (query == null || query.isEmpty()) {
            return "";
        }
        StringBuilder sb = new StringBuilder("?");
        boolean first = true;
        for (Map.Entry<String, String> e : query.entrySet()) {
            if (!first) {
                sb.append('&');
            }
            sb.append(URLEncoder.encode(e.getKey(), StandardCharsets.UTF_8))
                    .append('=')
                    .append(URLEncoder.encode(e.getValue(), StandardCharsets.UTF_8));
            first = false;
        }
        return sb.toString();
    }

    /**
     * 统一请求：签名 + 发送 + 解析 {code,msg,data} 信封。
     * code != "0" 抛业务异常；HTTP 非 2xx 抛网络错误；解析失败抛「数据解析失败」。
     *
     * @param creds 为 null 表示公开接口（不签名）
     */
    private <T> T request(String method, String path, Map<String, String> query, Object body,
                          TypeReference<T> type, Credentials creds) throws OkxException {
        String fullPath = path + buildQuery(query);
        URI uri = URI.create(baseUrl + fullPath);

        String bodyStr = "";
        if (body != null) {
            try {
                bodyStr = mapper.writeValueAsString(body);
            } catch (IOException e) {
                throw new OkxException("encode", "请求体序列化失败");
            }
        }

        HttpRequest.Builder builder = HttpRequest.newBuilder(uri)
                .timeout(Duration.ofSeconds(20))
                .header("Content-Type", "application/json");

        if (creds != null) {
            if (!creds.isComplete()) {
                throw new OkxException("no-credentials", "未配置 OKX API 密钥");
            }
            String ts = OkxSigner.timestamp();
            builder.header("OK-ACCESS-KEY", creds.apiKey());
            builder.header("OK-ACCESS-TIMESTAMP", ts);
            builder.header("OK-ACCESS-PASSPHRASE", creds.passphrase());
            builder.header("OK-ACCESS-SIGN", OkxSigner.sign(ts, method, fullPath, bodyStr, creds.apiSecret()));
            if (creds.demo()) {
                builder.header("x-simulated-trading", "1");
            }
        }

        if (body != null) {
            builder.method(method, HttpRequest.BodyPublishers.ofString(bodyStr, StandardCharsets.UTF_8));
        } else {
            builder.method(method, HttpRequest.BodyPublishers.noBody());
        }

        HttpResponse<String> resp;
        try {
            resp = http.send(builder.build(), HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (IOException e) {
            throw new OkxException("network", "网络错误：" + e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new OkxException("network", "请求被中断");
        }

        int status = resp.statusCode();
        if (status < 200 || status >= 300) {
            throw new OkxException(String.valueOf(status), "网络错误 " + status + "：" + snippet(resp.body()));
        }

        JsonNode root;
        try {
            root = mapper.readTree(resp.body());
        } catch (IOException e) {
            throw new OkxException("decode", "数据解析失败：" + e.getMessage());
        }
        if (root == null || !root.isObject()) {
            throw new OkxException("decode", "数据解析失败：响应不是 JSON 对象");
        }
        String code = root.path("code").asText("");
        if (!"0".equals(code)) {
            String msg = root.path("msg").asText("未知错误");
            throw new OkxException(code, "OKX 返回错误 " + code + "：" + msg);
        }
        JsonNode data = root.get("data");
        if (data == null || data.isNull()) {
            throw new OkxException("decode", "数据解析失败：data 为空");
        }
        try {
            return mapper.convertValue(data, type);
        } catch (IllegalArgumentException e) {
            throw new OkxException("decode", "数据解析失败：" + e.getMessage());
        }
    }

    /** 截取错误响应片段（与 iOS 的 prefix(200) 一致），仅用于错误提示，不含密钥 */
    private static String snippet(String body) {
        if (body == null) {
            return "";
        }
        String oneLine = body.replace('\n', ' ').replace('\r', ' ').trim();
        if (oneLine.length() <= ERROR_SNIPPET_LIMIT) {
            return oneLine;
        }
        return oneLine.substring(0, ERROR_SNIPPET_LIMIT);
    }
}
