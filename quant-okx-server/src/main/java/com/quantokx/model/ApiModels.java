package com.quantokx.model;

import java.util.List;

/**
 * REST 接口的 DTO 集合（严格对照 quant-okx-API.md 契约，字段名不可改）。
 * 全部使用 record，Jackson 直接按组件名序列化；请求体用包装类型以便区分「省略 / null / 空串」。
 */
public final class ApiModels {

    private ApiModels() {
    }

    // ------------------------------------------------------------------ 系统

    /** GET /api/health */
    public record HealthData(String status, String version, String serverTime, String javaVersion) {
    }

    /** ticker 响应视图（比 OKX 原始多了 changePct） */
    public record TickerView(String instId,
                             String last,
                             String open24h,
                             String high24h,
                             String low24h,
                             String vol24h,
                             double changePct) {

        public static TickerView of(Ticker t) {
            return new TickerView(t.instId(), t.last(), t.open24h(), t.high24h(),
                    t.low24h(), t.vol24h(), t.changePct());
        }
    }

    /** status.lastSignal */
    public record LastSignalData(String action,
                                 String reason,
                                 double confidence,
                                 String strategy,
                                 double price,
                                 String at) {
    }

    /** GET /api/status */
    public record StatusData(boolean running,
                             boolean demoTrading,
                             String instId,
                             String bar,
                             String activeStrategy,
                             long tickCount,
                             String lastTickAt,
                             String errorMessage,
                             double balanceUSDT,
                             long uptimeSeconds,
                             TickerView ticker,
                             List<Position> positions,
                             LastSignalData lastSignal,
                             String lastAIReply) {
    }

    /** POST /api/engine/start | stop */
    public record EngineState(boolean running) {
    }

    // ------------------------------------------------------------------ 配置

    /** GET /api/config（绝不包含密钥明文） */
    public record ConfigView(boolean okxConfigured,
                             String okxApiKeyMasked,
                             boolean demoTrading,
                             String instId,
                             String bar,
                             String activeStrategy,
                             double tradeSizeUSDT,
                             int leverage,
                             int pollSeconds,
                             double stopLossPct,
                             double takeProfitPct,
                             double maxPositionUSDT,
                             int maxTradesPerHour,
                             boolean aiEnabled,
                             String aiBaseURL,
                             String aiModel,
                             boolean aiKeyConfigured) {
    }

    /**
     * PUT /api/config 请求体。字段同 ConfigView，但：
     * - 密钥字段（okxApiKey / okxApiSecret / okxPassphrase / aiKey）只为非 null 时生效：
     *   null/省略 = 不改，"" = 清空，其他 = 覆盖；
     * - 其余字段为 null 时表示不改（部分更新）。
     */
    public record ConfigUpdate(String okxApiKey,
                               String okxApiSecret,
                               String okxPassphrase,
                               Boolean demoTrading,
                               String instId,
                               String bar,
                               String activeStrategy,
                               Double tradeSizeUSDT,
                               Integer leverage,
                               Integer pollSeconds,
                               Double stopLossPct,
                               Double takeProfitPct,
                               Double maxPositionUSDT,
                               Integer maxTradesPerHour,
                               Boolean aiEnabled,
                               String aiBaseURL,
                               String aiModel,
                               String aiKey) {
    }

    /** POST /api/config/test（业务失败也是 code=0，用 ok/message 表达） */
    public record TestResult(boolean ok, String message, String instId, String lastPrice, String balanceUSDT) {
    }

    // ------------------------------------------------------------------ 交易

    /** POST /api/trade/order 请求体 */
    public record ManualOrderRequest(String instId, String side, String posSide, Double sz, String ordType) {
    }

    /** POST /api/trade/order 响应 */
    public record OrderAck(String ordId, boolean success, String message) {
    }

    /** POST /api/trade/close-all 响应 */
    public record CloseAllResult(int closed, String message) {
    }

    /** DELETE /api/logs 响应 */
    public record ClearLogsResult(int cleared) {
    }

    // ------------------------------------------------------------------ 策略

    /** GET /api/strategies 元素 */
    public record StrategyInfo(String id, String title, String detail) {
    }
}
