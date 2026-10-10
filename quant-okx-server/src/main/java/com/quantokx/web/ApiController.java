package com.quantokx.web;

import com.quantokx.auth.SessionStore;
import com.quantokx.auth.UserStore;
import com.quantokx.config.QuantOkxProperties;
import com.quantokx.config.SecretScrubber;
import com.quantokx.engine.EngineRegistry;
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
import com.quantokx.model.MembershipPlan;
import com.quantokx.model.OpenOrder;
import com.quantokx.model.Position;
import com.quantokx.model.StrategyKind;
import com.quantokx.model.Ticker;
import com.quantokx.model.TimeFormat;
import com.quantokx.model.TradeLogEntry;
import com.quantokx.okx.OkxClient;
import com.quantokx.okx.OkxException;
import com.quantokx.pay.EpayService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * REST 接口层（多租户）：所有业务数据按当前登录用户隔离。
 * <p>
 * 鉴权：X-Auth-Token = 登录/注册签发的会话令牌（见 AuthInterceptor），
 * userId 从 request attribute 取。/api/health 与 /api/pay/* 免鉴权。
 */
@RestController
@RequestMapping("/api")
public class ApiController {

    private final EngineRegistry registry;
    private final UserStore users;
    private final SessionStore sessions;
    private final OkxClient okx;
    private final EpayService epay;
    private final SecretScrubber scrubber;
    private final QuantOkxProperties properties;

    public ApiController(EngineRegistry registry,
                         UserStore users,
                         SessionStore sessions,
                         OkxClient okx,
                         EpayService epay,
                         SecretScrubber scrubber,
                         QuantOkxProperties properties) {
        this.registry = registry;
        this.users = users;
        this.sessions = sessions;
        this.okx = okx;
        this.epay = epay;
        this.scrubber = scrubber;
        this.properties = properties;
    }

    // ------------------------------------------------------------------ 视图

    /** GET /api/membership/plans 的元素 */
    public record PlanView(String id, String name, double pricePerMonth, String badge,
                           int minPollSeconds, boolean aiEnabled, List<String> features,
                           boolean highlight) {
    }

    /** POST /api/membership/subscribe 的返回（payUrl 空 = 演示直通已开通） */
    public record SubscribeView(String orderId, String level, String planName, String expiresAt,
                                Double total, String payUrl, boolean demo) {
    }

    /** 登录/注册返回 */
    public record AuthData(String token, String userId, String username, String level,
                           String planName, boolean active, int daysLeft) {
    }

    /** GET /api/me */
    public record MeData(String userId, String username, String createdAt, String level,
                         String planName, boolean active, String expiresAt, int daysLeft,
                         MembershipPlan.Benefits benefits) {
    }

    /** 订阅请求体 */
    public record SubscribeRequest(String planId, Integer months) {
    }

    /** 登录/注册请求体 */
    public record AuthRequest(String username, String password) {
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

    // ------------------------------------------------------------------ 认证

    /** POST /api/auth/register */
    @PostMapping("/auth/register")
    public ApiResponse<AuthData> register(@RequestBody(required = false) AuthRequest body) {
        require(body);
        UserStore.User u = users.register(body.username(), body.password());
        String token = sessions.issue(u.userId);
        UserStore.MemberStatus st = users.statusOf(u.userId);
        return ApiResponse.ok(new AuthData(token, u.userId, u.username,
                st.level(), st.planName(), st.active(), st.daysLeft()));
    }

    /** POST /api/auth/login */
    @PostMapping("/auth/login")
    public ApiResponse<AuthData> login(@RequestBody(required = false) AuthRequest body) {
        require(body);
        UserStore.User u = users.verifyLogin(body.username(), body.password())
                .orElseThrow(() -> new IllegalArgumentException("用户名或密码错误"));
        String token = sessions.issue(u.userId);
        UserStore.MemberStatus st = users.statusOf(u.userId);
        return ApiResponse.ok(new AuthData(token, u.userId, u.username,
                st.level(), st.planName(), st.active(), st.daysLeft()));
    }

    /** GET /api/me */
    @GetMapping("/me")
    public ApiResponse<MeData> me(HttpServletRequest request) {
        String uid = uid(request);
        UserStore.User u = users.findById(uid)
                .orElseThrow(() -> new IllegalArgumentException("用户不存在"));
        UserStore.MemberStatus st = users.statusOf(uid);
        return ApiResponse.ok(new MeData(u.userId, u.username, u.createdAt,
                st.level(), st.planName(), st.active(), st.expiresAt(), st.daysLeft(),
                st.benefits()));
    }

    /** POST /api/auth/logout */
    @PostMapping("/auth/logout")
    public ApiResponse<EngineState> logout(HttpServletRequest request) {
        sessions.revoke(request.getHeader("X-Auth-Token"));
        return ApiResponse.ok(new EngineState(false));
    }

    // ------------------------------------------------------------------ 状态与引擎

    /** GET /api/status */
    @GetMapping("/status")
    public ApiResponse<StatusData> status(HttpServletRequest request) {
        return ApiResponse.ok(engine(request).status());
    }

    /** POST /api/engine/start */
    @PostMapping("/engine/start")
    public ApiResponse<EngineState> startEngine(HttpServletRequest request) {
        TradingEngine engine = engine(request);
        engine.start();
        return ApiResponse.ok(new EngineState(engine.isRunning()));
    }

    /** POST /api/engine/stop */
    @PostMapping("/engine/stop")
    public ApiResponse<EngineState> stopEngine(HttpServletRequest request) {
        engine(request).stop();
        return ApiResponse.ok(new EngineState(false));
    }

    // ------------------------------------------------------------------ 配置

    /** GET /api/config（密钥只返回掩码） */
    @GetMapping("/config")
    public ApiResponse<ConfigView> getConfig(HttpServletRequest request) {
        return ApiResponse.ok(configStore(request).maskedView());
    }

    /** PUT /api/config（部分更新；会员权益校验在这里做——只有这里知道用户是谁） */
    @PutMapping("/config")
    public ApiResponse<ConfigView> updateConfig(HttpServletRequest request,
                                                @RequestBody ConfigUpdate body) {
        String uid = uid(request);
        MembershipPlan.Benefits benefits = users.benefitsOf(uid);
        if (body != null && body.pollSeconds() != null
                && body.pollSeconds() < benefits.minPollSeconds()) {
            throw new IllegalArgumentException("当前会员最低轮询间隔 "
                    + benefits.minPollSeconds() + "s，请到会员中心升级");
        }
        if (body != null && Boolean.TRUE.equals(body.aiEnabled()) && !benefits.aiEnabled()) {
            throw new IllegalArgumentException("AI 决策为会员功能，请先升级会员");
        }
        configStore(request).update(body);
        return ApiResponse.ok(configStore(request).maskedView());
    }

    /** POST /api/config/test（测试 OKX 连通性；业务失败 code 仍为 0） */
    @PostMapping("/config/test")
    public ApiResponse<TestResult> testConfig(HttpServletRequest request) {
        ConfigStore cs = configStore(request);
        TradeLogStore logStore = logStore(request);
        AppConfig cfg = cs.get();
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
    public ApiResponse<TickerView> ticker(HttpServletRequest request,
                                          @RequestParam(required = false) String instId) {
        return ApiResponse.ok(TickerView.of(okx.ticker(resolveInstId(request, instId))));
    }

    /** GET /api/market/candles?instId=&bar=1m&limit=120（旧 → 新排序） */
    @GetMapping("/market/candles")
    public ApiResponse<List<Candle>> candles(HttpServletRequest request,
                                             @RequestParam(required = false) String instId,
                                             @RequestParam(required = false) String bar,
                                             @RequestParam(defaultValue = "120") int limit) {
        String id = resolveInstId(request, instId);
        String b = (bar == null || bar.isBlank()) ? configStore(request).get().getBar() : bar.trim();
        int n = Math.max(1, Math.min(300, limit));
        return ApiResponse.ok(okx.candles(id, b, n));
    }

    // ------------------------------------------------------------------ 交易

    /** GET /api/positions（只返回非零持仓；数值保持 OKX 原始字符串） */
    @GetMapping("/positions")
    public ApiResponse<List<Position>> positions(HttpServletRequest request) {
        return ApiResponse.ok(okx.positions(creds(configStore(request).get()), "SWAP"));
    }

    /** GET /api/orders?instId= */
    @GetMapping("/orders")
    public ApiResponse<List<OpenOrder>> orders(HttpServletRequest request,
                                               @RequestParam(required = false) String instId) {
        return ApiResponse.ok(okx.pendingOrders(creds(configStore(request).get()),
                resolveInstId(request, instId)));
    }

    /** GET /api/logs?limit=200（最新在前） */
    @GetMapping("/logs")
    public ApiResponse<List<TradeLogEntry>> logs(HttpServletRequest request,
                                                 @RequestParam(defaultValue = "200") int limit) {
        return ApiResponse.ok(logStore(request).list(limit));
    }

    /** DELETE /api/logs */
    @DeleteMapping("/logs")
    public ApiResponse<ClearLogsResult> clearLogs(HttpServletRequest request) {
        return ApiResponse.ok(new ClearLogsResult(logStore(request).clear()));
    }

    /** POST /api/trade/close-all */
    @PostMapping("/trade/close-all")
    public ApiResponse<CloseAllResult> closeAll(HttpServletRequest request) {
        return ApiResponse.ok(engine(request).closeAll());
    }

    /** POST /api/trade/order（手动下单；同样要过 RiskManager） */
    @PostMapping("/trade/order")
    public ApiResponse<OrderAck> order(HttpServletRequest request,
                                       @RequestBody(required = false) ManualOrderRequest body) {
        if (body == null) {
            return ApiResponse.ok(new OrderAck("", false, "请求体不能为空"));
        }
        return ApiResponse.ok(engine(request).manualOrder(body));
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

    // ------------------------------------------------------------------ 会员

    /** GET /api/membership/plans */
    @GetMapping("/membership/plans")
    public ApiResponse<List<PlanView>> membershipPlans() {
        List<PlanView> list = new ArrayList<>();
        for (MembershipPlan p : MembershipPlan.PLANS) {
            list.add(new PlanView(p.id(), p.name(), p.pricePerMonth(), p.badge(),
                    p.minPollSeconds(), p.aiEnabled(), p.features(), p.highlight()));
        }
        return ApiResponse.ok(list);
    }

    /** GET /api/membership/status（当前用户） */
    @GetMapping("/membership/status")
    public ApiResponse<UserStore.MemberStatus> membershipStatus(HttpServletRequest request) {
        return ApiResponse.ok(users.statusOf(uid(request)));
    }

    /** GET /api/membership/orders（当前用户） */
    @GetMapping("/membership/orders")
    public ApiResponse<List<UserStore.OrderRec>> membershipOrders(HttpServletRequest request) {
        return ApiResponse.ok(users.ordersOf(uid(request)));
    }

    /**
     * POST /api/membership/subscribe：
     * 易支付未配置 → 演示直通（立即开通，payUrl=null, demo=true）；
     * 已配置 → 创建 PENDING 订单并返回收银台地址，等 /api/pay/notify 回调开通。
     */
    @PostMapping("/membership/subscribe")
    public ApiResponse<SubscribeView> subscribe(HttpServletRequest request,
                                                @RequestBody(required = false) SubscribeRequest body) {
        String uid = uid(request);
        if (body == null || body.planId() == null || body.planId().isBlank()) {
            throw new IllegalArgumentException("planId 不能为空");
        }
        if (body.months() == null) {
            throw new IllegalArgumentException("months 不能为空");
        }
        MembershipPlan plan = MembershipPlan.findByIdOrNull(body.planId().trim());
        if (plan == null) {
            throw new IllegalArgumentException("套餐不存在：" + body.planId());
        }
        if (plan == MembershipPlan.FREE) {
            throw new IllegalArgumentException("免费版无需订阅");
        }
        if (body.months() != 1 && body.months() != 3 && body.months() != 12) {
            throw new IllegalArgumentException("订阅时长仅支持 1 / 3 / 12 个月");
        }
        MembershipPlan current = users.activePlanOf(uid);
        if (plan.rank() < current.rank()) {
            throw new IllegalArgumentException("当前会员等级更高（" + current.name() + "），无法降级订阅");
        }
        double total = plan.pricePerMonth() * body.months() * (body.months() == 12 ? 0.8 : 1.0);
        total = Math.round(total * 100.0) / 100.0;

        if (!epay.configured()) {
            UserStore.ActivateResult r = users.activateMembership(uid, plan, body.months(), "PAID_DEMO");
            return ApiResponse.ok(new SubscribeView(r.order().orderId(), plan.id(), plan.name(),
                    r.expiresAt(), total, null, true));
        }
        EpayService.PayOrder po = epay.createPending(uid, plan, body.months(), total);
        String payUrl = epay.buildPayUrl(po.outTradeNo(), "QuantOKX-" + plan.name(), po.total());
        return ApiResponse.ok(new SubscribeView(po.outTradeNo(), plan.id(), plan.name(),
                null, total, payUrl, false));
    }

    // ------------------------------------------------------------------ 易支付回调（免鉴权）

    /** GET /api/pay/notify —— 异步通知，验签后开通会员。必须应答纯文本 success。 */
    @GetMapping("/pay/notify")
    public ResponseEntity<String> payNotify(HttpServletRequest request) {
        Map<String, String> p = flat(request);
        if (!epay.verifyNotify(p)) {
            return ResponseEntity.ok().body("fail");
        }
        String outTradeNo = p.get("out_trade_no");
        if (!"TRADE_SUCCESS".equalsIgnoreCase(p.get("trade_status"))) {
            return ResponseEntity.ok().body("fail");
        }
        boolean done = epay.markPaid(outTradeNo, users);
        return ResponseEntity.ok().body(done ? "success" : "fail");
    }

    /** GET /api/pay/return —— 同步跳转落地页 */
    @GetMapping("/pay/return")
    public ResponseEntity<String> payReturn() {
        String html = "<!doctype html><html lang=\"zh\"><meta charset=\"utf-8\">"
                + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
                + "<body style=\"font-family:-apple-system,sans-serif;text-align:center;padding-top:80px\">"
                + "<h2>✅ 支付完成</h2><p>请返回 App 刷新会员状态</p></body></html>";
        return ResponseEntity.ok().contentType(org.springframework.http.MediaType.TEXT_HTML)
                .body(html);
    }

    // ------------------------------------------------------------------ 内部工具

    private static String uid(HttpServletRequest request) {
        Object v = request.getAttribute(AuthInterceptor.ATTR_USER_ID);
        if (v == null) {
            throw new IllegalArgumentException("未登录");
        }
        return String.valueOf(v);
    }

    private static void require(AuthRequest body) {
        if (body == null) {
            throw new IllegalArgumentException("请求体不能为空");
        }
    }

    private TradingEngine engine(HttpServletRequest request) {
        return registry.engine(uid(request));
    }

    private ConfigStore configStore(HttpServletRequest request) {
        return registry.configStore(uid(request));
    }

    private TradeLogStore logStore(HttpServletRequest request) {
        return registry.logStore(uid(request));
    }

    private String resolveInstId(HttpServletRequest request, String instId) {
        if (instId == null || instId.isBlank()) {
            return configStore(request).get().getInstId();
        }
        return instId.trim();
    }

    private static Map<String, String> flat(HttpServletRequest request) {
        Map<String, String> out = new HashMap<>();
        request.getParameterMap().forEach((k, v) -> out.put(k, v == null || v.length == 0 ? "" : v[0]));
        return out;
    }

    private static OkxClient.Credentials creds(AppConfig cfg) {
        return new OkxClient.Credentials(cfg.getOkxApiKey(), cfg.getOkxApiSecret(),
                cfg.getOkxPassphrase(), cfg.isDemoTrading());
    }
}