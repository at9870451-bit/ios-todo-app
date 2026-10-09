package com.quantokx.web;

import com.quantokx.config.QuantOkxProperties;
import com.quantokx.config.SecretScrubber;
import com.quantokx.engine.TradeLogStore;
import com.quantokx.engine.TradingEngine;
import com.quantokx.model.ApiModels.ClearLogsResult;
import com.quantokx.model.ApiModels.CloseAllResult;
import com.quantokx.model.ApiModels.ConfigUpdate;
import com.quantokx.model.ApiModels.ConfigView;
import com.quantokx.model.ApiModels.EngineState;
import com.quantokx.model.ApiModels.HealthData;
import com.quantokx.model.ApiModels.ManualOrderRequest;
import com.quantokx.model.ApiModels.OrderAck;
import com.quantokx.model.ApiModels.StatusData;
import com.quantokx.model.ApiModels.StrategyInfo;
import com.quantokx.model.ApiModels.TestResult;
import com.quantokx.model.ApiModels.TickerView;
import com.quantokx.model.AppConfig;
import com.quantokx.model.Balance;
import com.quantokx.model.Candle;
import com.quantokx.model.OpenOrder;
import com.quantokx.model.Position;
import com.quantokx.model.StrategyKind;
import com.quantokx.model.Ticker;
import com.quantokx.model.TimeFormat;
import com.quantokx.model.TradeLogEntry;
import com.quantokx.okx.OkxClient;
import com.quantokx.okx.OkxException;
import com.quantokx.store.ConfigStore;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.List;

/**
 * REST 接口层。所有返回都包在 {@link ApiResponse} 信封里，字段严格对照 quant-okx-API.md 契约。
 * <p>
 * 异常约定：
 * - 鉴权失败 → HTTP 401 + 统一信封（见 AuthInterceptor）；
 * - 业务/参数错误 → 统一信封 code=400（见 GlobalExceptionHandler）；
 * - /api/config/test 与 /api/trade/order 的业务失败仍返回 code=0，用 ok/success + message 表达。
 */
@RestController
@RequestMapping("/api")
public class ApiController {

    private final TradingEngine engine;
    private final ConfigStore configStore;
    private final OkxClient okx;
    private final TradeLogStore logStore;
    private final SecretScrubber scrubber;
    private final QuantOkxProperties properties;

    public ApiController(TradingEngine engine,
                         ConfigStore configStore,
                         OkxClient okx,
                         TradeLogStore logStore,
                         SecretScrubber scrubber,
                         QuantOkxProperties properties) {
        this.engine = engine;
        this.configStore = configStore;
        this.okx = okx;
        this.logStore = logStore;
        this.scrubber = scrubber;
        this.properties = properties;
    }

    // ------------------------------------------------------------------ 系统

    /** GET /api/health（无需鉴权） */
    @GetMapping("/health")
    public ApiResponse<HealthData> health() {
        return ApiResponse.ok(new HealthData(
                "up",
                properties.getVersion(),
                TimeFormat.isoNow(),
                String.valueOf(Runtime.version().feature())));
    }

    /** GET /api/status */
    @GetMapping("/status")
    public ApiResponse<StatusData> status() {
        return ApiResponse.ok(engine.status());
    }

    /** POST /api/engine/start */
    @PostMapping("/engine/start")
    public ApiResponse<EngineState> startEngine() {
        engine.start();
        return ApiResponse.ok(new EngineState(engine.isRunning()));
    }

    /** POST /api/engine/stop */
    @PostMapping("/engine/stop")
    public ApiResponse<EngineState> stopEngine() {
        engine.stop();
        return ApiResponse.ok(new EngineState(engine.isRunning()));
    }

    // ------------------------------------------------------------------ 配置

    /** GET /api/config（密钥只返回掩码） */
    @GetMapping("/config")
    public ApiResponse<ConfigView> getConfig() {
        return ApiResponse.ok(configStore.maskedView());
    }

    /** PUT /api/config（部分更新；立即对运行中的引擎生效） */
    @PutMapping("/config")
    public ApiResponse<ConfigView> updateConfig(@RequestBody ConfigUpdate body) {
        configStore.update(body);
        return ApiResponse.ok(configStore.maskedView());
    }

    /** POST /api/config/test（测试 OKX 连通性；业务失败 code 仍为 0） */
    @PostMapping("/config/test")
    public ApiResponse<TestResult> testConfig() {
        AppConfig cfg = configStore.get();
        String instId = cfg.getInstId();
        OkxClient.Credentials creds = creds(cfg);
        if (!creds.isComplete()) {
            String msg = "未配置 OKX API 密钥";
            logStore.log(instId, "连接测试失败", "测试", 0, 0, msg, false);
            return ApiResponse.ok(new TestResult(false, msg, instId, null, null));
        }
        try {
            Ticker t = okx.ticker(instId);
            String avail = "0";
            for (Balance b : okx.balance(creds)) {
                if ("USDT".equalsIgnoreCase(b.ccy())) {
                    avail = b.availBal() == null ? "0" : b.availBal();
                    break;
                }
            }
            logStore.log(instId, "连接测试成功", "测试", t.lastDouble(), 0, "", true);
            return ApiResponse.ok(new TestResult(true, "连接正常", instId, t.last(), avail));
        } catch (OkxException e) {
            String msg = scrubber.scrub(e.getMessage());
            logStore.log(instId, "连接测试失败", "测试", 0, 0, msg, false);
            return ApiResponse.ok(new TestResult(false, msg, instId, null, null));
        }
    }

    // ------------------------------------------------------------------ 行情

    /** GET /api/market/ticker?instId= */
    @GetMapping("/market/ticker")
    public ApiResponse<TickerView> ticker(@RequestParam(required = false) String instId) {
        return ApiResponse.ok(TickerView.of(okx.ticker(resolveInstId(instId))));
    }

    /** GET /api/market/candles?instId=&bar=1m&limit=120（旧 → 新排序） */
    @GetMapping("/market/candles")
    public ApiResponse<List<Candle>> candles(@RequestParam(required = false) String instId,
                                             @RequestParam(required = false) String bar,
                                             @RequestParam(defaultValue = "120") int limit) {
        String id = resolveInstId(instId);
        String b = (bar == null || bar.isBlank()) ? configStore.get().getBar() : bar.trim();
        int n = Math.max(1, Math.min(300, limit));
        return ApiResponse.ok(okx.candles(id, b, n));
    }

    // ------------------------------------------------------------------ 交易

    /** GET /api/positions（只返回非零持仓；数值保持 OKX 原始字符串） */
    @GetMapping("/positions")
    public ApiResponse<List<Position>> positions() {
        return ApiResponse.ok(okx.positions(creds(configStore.get()), "SWAP"));
    }

    /** GET /api/orders?instId= */
    @GetMapping("/orders")
    public ApiResponse<List<OpenOrder>> orders(@RequestParam(required = false) String instId) {
        return ApiResponse.ok(okx.pendingOrders(creds(configStore.get()), resolveInstId(instId)));
    }

    /** GET /api/logs?limit=200（最新在前） */
    @GetMapping("/logs")
    public ApiResponse<List<TradeLogEntry>> logs(@RequestParam(defaultValue = "200") int limit) {
        return ApiResponse.ok(logStore.list(limit));
    }

    /** DELETE /api/logs */
    @DeleteMapping("/logs")
    public ApiResponse<ClearLogsResult> clearLogs() {
        return ApiResponse.ok(new ClearLogsResult(logStore.clear()));
    }

    /** POST /api/trade/close-all */
    @PostMapping("/trade/close-all")
    public ApiResponse<CloseAllResult> closeAll() {
        return ApiResponse.ok(engine.closeAll());
    }

    /** POST /api/trade/order（手动下单；同样要过 RiskManager） */
    @PostMapping("/trade/order")
    public ApiResponse<OrderAck> order(@RequestBody(required = false) ManualOrderRequest body) {
        if (body == null) {
            return ApiResponse.ok(new OrderAck("", false, "请求体不能为空"));
        }
        return ApiResponse.ok(engine.manualOrder(body));
    }

    // ------------------------------------------------------------------ 策略

    /** GET /api/strategies */
    @GetMapping("/strategies")
    public ApiResponse<List<StrategyInfo>> strategies() {
        List<StrategyInfo> list = new ArrayList<>();
        for (StrategyKind k : StrategyKind.values()) {
            list.add(new StrategyInfo(k.wire(), k.title(), k.detail()));
        }
        return ApiResponse.ok(list);
    }

    // ------------------------------------------------------------------ 内部工具

    private String resolveInstId(String instId) {
        if (instId == null || instId.isBlank()) {
            return configStore.get().getInstId();
        }
        return instId.trim();
    }

    private static OkxClient.Credentials creds(AppConfig cfg) {
        return new OkxClient.Credentials(cfg.getOkxApiKey(), cfg.getOkxApiSecret(),
                cfg.getOkxPassphrase(), cfg.isDemoTrading());
    }
}
