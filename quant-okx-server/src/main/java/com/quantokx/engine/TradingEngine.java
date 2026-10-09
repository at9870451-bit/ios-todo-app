package com.quantokx.engine;

import com.quantokx.ai.AiClient;
import com.quantokx.config.SecretScrubber;
import com.quantokx.model.ApiModels.CloseAllResult;
import com.quantokx.model.ApiModels.LastSignalData;
import com.quantokx.model.ApiModels.ManualOrderRequest;
import com.quantokx.model.ApiModels.OrderAck;
import com.quantokx.model.ApiModels.StatusData;
import com.quantokx.model.ApiModels.TickerView;
import com.quantokx.model.AppConfig;
import com.quantokx.model.Balance;
import com.quantokx.model.Candle;
import com.quantokx.model.OrderResult;
import com.quantokx.model.Position;
import com.quantokx.model.Signal;
import com.quantokx.model.StrategyKind;
import com.quantokx.model.Ticker;
import com.quantokx.model.TimeFormat;
import com.quantokx.okx.OkxClient;
import com.quantokx.okx.OkxException;
import com.quantokx.store.ConfigStore;
import com.quantokx.strategy.StrategyContext;
import com.quantokx.strategy.StrategyEngine;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 交易引擎：拉数据 → 风控检查 → 策略决策 → 下单。所有下单动作都过 RiskManager，不能绕过。
 * <p>
 * 对照 quant-okx-ios/QuantOKX/Sources/Engine/TradingEngine.swift：
 * 每轮顺序严格为 行情(ticker+candles) → 持仓/余额 → 风控（止盈止损优先，命中直接平仓且本轮不再看策略）
 * → 策略（ai 策略异步调 AiClient）→ 风险检查（最大持仓 / 每小时次数 / 单笔金额）→ 下单。
 * <p>
 * 配置热更新：每轮从 ConfigStore 读最新快照，PUT /api/config 后下一轮立即生效。
 */
@Component
public class TradingEngine {

    private static final Logger log = LoggerFactory.getLogger(TradingEngine.class);

    /** 契约要求拉 120 根 K 线 */
    private static final int CANDLE_LIMIT = 120;
    /** AI 决策等待上限（AiClient 内部 HTTP 超时 45s） */
    private static final long AI_TIMEOUT_SECONDS = 60;

    private final OkxClient okx;
    private final ConfigStore configStore;
    private final TradeLogStore logStore;
    private final AiClient aiClient;
    private final RiskManager riskManager;
    private final SecretScrubber scrubber;
    private final ExecutorService aiExecutor;

    // ---- 对外状态 ----
    private final AtomicBoolean running = new AtomicBoolean(false);
    private final AtomicLong tickCount = new AtomicLong(0);
    private volatile Instant lastTickAt;
    private volatile String errorMessage;
    private volatile Ticker ticker;
    private volatile List<Position> positions = List.of();
    private volatile double balanceUSDT;
    private volatile LastSignalData lastSignal;
    private volatile String lastAIReply = "";
    private volatile long startedAtMs;
    /** 上一轮 tick 的开始时间（频率闸门用） */
    private volatile long lastTickStartedAtMs;

    public TradingEngine(OkxClient okx,
                         ConfigStore configStore,
                         TradeLogStore logStore,
                         AiClient aiClient,
                         RiskManager riskManager,
                         SecretScrubber scrubber) {
        this.okx = okx;
        this.configStore = configStore;
        this.logStore = logStore;
        this.aiClient = aiClient;
        this.riskManager = riskManager;
        this.scrubber = scrubber;
        this.aiExecutor = Executors.newSingleThreadExecutor(r -> {
            Thread t = new Thread(r, "ai-decider");
            t.setDaemon(true);
            return t;
        });
    }

    // ------------------------------------------------------------------ 启停

    /** 启动引擎。缺少 OKX 密钥时不启动，并在 errorMessage 里说明原因。 */
    public synchronized boolean start() {
        if (running.get()) {
            return true;
        }
        AppConfig cfg = configStore.get();
        if (!creds(cfg).isComplete()) {
            errorMessage = "请先配置 OKX API 密钥（okxApiKey / okxApiSecret / okxPassphrase）";
            return false;
        }
        running.set(true);
        errorMessage = null;
        if (startedAtMs == 0) {
            startedAtMs = System.currentTimeMillis();
        }
        lastTickStartedAtMs = 0; // 启动后立即跑第一轮
        tradeLog(cfg.getInstId(), "引擎启动", "START", 0, 0,
                "策略：" + cfg.getActiveStrategy().title() + (cfg.isDemoTrading() ? "（模拟盘）" : "（实盘！）"), true);
        return true;
    }

    /** 停止引擎 */
    public synchronized void stop() {
        if (!running.getAndSet(false)) {
            return;
        }
        AppConfig cfg = configStore.get();
        tradeLog(cfg.getInstId(), "引擎停止", "STOP", 0, 0, "累计 " + tickCount.get() + " 次轮询", true);
    }

    public boolean isRunning() {
        return running.get();
    }

    // ------------------------------------------------------------------ 主循环

    /**
     * 调度心跳：@Scheduled 的 SpEL 在注册时只解析一次（见 ConfigStore#getPollMillis），
     * 所以这里用短心跳 + 每轮读取「当前」pollSeconds 的方式实现轮询间隔热更新。
     */
    @Scheduled(fixedDelayString = "#{@configStore.pollMillis}")
    public void scheduledTick() {
        if (!running.get()) {
            return;
        }
        AppConfig cfg = configStore.get();
        int pollSeconds = Math.max(5, cfg.getPollSeconds());
        long now = System.currentTimeMillis();
        if (lastTickStartedAtMs != 0 && now - lastTickStartedAtMs < pollSeconds * 1000L) {
            return; // 还没到下一轮
        }
        lastTickStartedAtMs = now;
        tick();
    }

    /** 单次轮询（严格按契约顺序：行情 → 账户 → 风控 → 策略 → 下单） */
    synchronized void tick() {
        tickCount.incrementAndGet();
        lastTickAt = Instant.now();

        AppConfig cfg = configStore.get();
        String instId = cfg.getInstId();

        try {
            // 1. 行情：ticker + candles(120 根)
            Ticker tk = okx.ticker(instId);
            List<Candle> candles = okx.candles(instId, cfg.getBar(), CANDLE_LIMIT);
            ticker = tk;

            // 2. 账户：持仓 + 余额（与 iOS 的 try? 一致：失败不中断本轮）
            List<Position> mine = List.of();
            try {
                List<Position> all = okx.positions(creds(cfg), instTypeOf(instId));
                List<Position> filtered = new ArrayList<>();
                for (Position p : all) {
                    if (instId.equals(p.instId())) {
                        filtered.add(p);
                    }
                }
                mine = filtered;
                positions = mine;
            } catch (OkxException e) {
                positions = List.of();
                log.warn("拉取持仓失败：{}", scrubber.scrub(e.getMessage()));
            }
            try {
                for (Balance b : okx.balance(creds(cfg))) {
                    if ("USDT".equalsIgnoreCase(b.ccy())) {
                        balanceUSDT = b.availDouble();
                        break;
                    }
                }
            } catch (OkxException e) {
                log.warn("拉取余额失败：{}", scrubber.scrub(e.getMessage()));
            }

            // 3. 持仓判定
            Position longPos = mine.stream().filter(Position::isLong).findFirst().orElse(null);
            Position shortPos = mine.stream().filter(Position::isShort).findFirst().orElse(null);

            StrategyContext ctx = new StrategyContext(instId, candles, tk,
                    longPos != null, shortPos != null,
                    StrategyContext.Params.withRisk(cfg.getStopLossPct(), cfg.getTakeProfitPct()));

            // 4. 风控优先：有持仓先检查止盈止损（命中直接平仓，本轮结束）
            Signal signal = null;
            if (longPos != null || shortPos != null) {
                Position p = longPos != null ? longPos : shortPos;
                boolean isLong = longPos != null;
                signal = StrategyEngine.riskCheck(ctx, p.avgDouble(), isLong, p.uplRatioDouble());
                if (signal != null && signal.action().isAction()) {
                    tradeLog(instId, signal.reason(), "风控", tk.lastDouble(), 0, "自动触发", true);
                }
            }

            // 5. 策略（风控未命中时才跑）
            if (signal == null) {
                if (cfg.getActiveStrategy() == StrategyKind.AI) {
                    signal = evaluateAi(ctx, cfg);
                } else {
                    signal = StrategyEngine.evaluate(cfg.getActiveStrategy(), ctx);
                }
            }
            if (signal == null) {
                return;
            }
            lastSignal = new LastSignalData(signal.action().wire(), signal.reason(), signal.confidence(),
                    signal.strategy().wire(), signal.price(), TimeFormat.isoNow());

            // 6. 执行（执行前过 RiskManager）
            if (signal.action().isAction()) {
                execute(signal, ctx, cfg, mine, longPos, shortPos);
            }

            errorMessage = null;
        } catch (OkxException e) {
            errorMessage = scrubber.scrub(e.getMessage());
            tradeLog(instId, "轮询失败", "ERROR", 0, 0, errorMessage, false);
        } catch (Exception e) {
            errorMessage = scrubber.scrub(String.valueOf(e.getMessage()));
            tradeLog(instId, "轮询失败", "ERROR", 0, 0, errorMessage, false);
            log.error("轮询异常：{}", scrubber.scrub(e.toString()));
        }
    }

    // ------------------------------------------------------------------ AI 决策（异步）

    /**
     * AI 策略：把行情摘要交给 AiClient，异步执行后等待结果（带超时）。
     * 对照 iOS: TradingEngine.evaluateAI —— 未启用/未配置时返回 hold；
     * 调用失败返回 hold（"AI 调用失败，本轮观望"），并把失败原因写进 lastAIReply。
     */
    private Signal evaluateAi(StrategyContext ctx, AppConfig cfg) {
        if (!cfg.isAiEnabled() || cfg.getAiBaseURL() == null || cfg.getAiBaseURL().isEmpty()) {
            return Signal.hold("未启用 AI 或未配置接口地址", StrategyKind.AI, ctx.price());
        }
        String prompt = StrategyEngine.describe(ctx);

        CompletableFuture<AiClient.Decision> future = CompletableFuture.supplyAsync(() -> aiCall(cfg, prompt), aiExecutor);
        try {
            AiClient.Decision d = future.get(AI_TIMEOUT_SECONDS, TimeUnit.SECONDS);
            lastAIReply = d.action().label()
                    + " (置信度 " + String.format(Locale.US, "%.2f", d.confidence()) + ")："
                    + d.reason();
            return new Signal(d.action(), "AI：" + d.reason(), d.confidence(), StrategyKind.AI, ctx.price());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            lastAIReply = "调用失败：请求被中断";
            return Signal.hold("AI 调用失败，本轮观望", StrategyKind.AI, ctx.price());
        } catch (ExecutionException | TimeoutException e) {
            String msg = e.getCause() == null ? e.getMessage() : e.getCause().getMessage();
            lastAIReply = "调用失败：" + scrubber.scrub(msg == null ? "未知错误" : msg);
            return Signal.hold("AI 调用失败，本轮观望", StrategyKind.AI, ctx.price());
        } finally {
            future.cancel(false); // 成功时已是 no-op；超时后放弃等待，避免拖住本轮
        }
    }

    /** 交给线程池执行的实际调用；异常统一收敛成带脱敏消息的运行时异常 */
    private AiClient.Decision aiCall(AppConfig cfg, String prompt) {
        try {
            return aiClient.decide(cfg.getAiBaseURL(), cfg.getAiModel(), cfg.getAiKey(), prompt);
        } catch (OkxException e) {
            throw new IllegalStateException(scrubber.scrub(e.getMessage()), e);
        }
    }

    // ------------------------------------------------------------------ 下单执行

    /**
     * 执行信号。频率限制对开/平仓都生效；平仓直接 close-position，开仓走 openPosition。
     * 对照 iOS: TradingEngine.execute
     */
    private void execute(Signal sig, StrategyContext ctx, AppConfig cfg, List<Position> mine,
                         Position longPos, Position shortPos) throws OkxException {
        String instId = ctx.instId();
        double price = ctx.price();

        // 频率限制（滑动窗口，与 iOS 一致：开/平仓都算）
        String limited = riskManager.checkFrequency(cfg.getMaxTradesPerHour());
        if (limited != null) {
            tradeLog(instId, limited, "跳过", price, 0, sig.reason(), false);
            return;
        }

        OkxClient.Credentials creds = creds(cfg);
        switch (sig.action()) {
            case HOLD -> {
                // 不操作
            }
            case CLOSE_LONG -> {
                okx.closePosition(creds, instId, longPos != null ? longPos.posSide() : "long");
                riskManager.recordTrade();
                tradeLog(instId, "平多成功", "平多", price, 0, sig.reason(), true);
            }
            case CLOSE_SHORT -> {
                okx.closePosition(creds, instId, shortPos != null ? shortPos.posSide() : "short");
                riskManager.recordTrade();
                tradeLog(instId, "平空成功", "平空", price, 0, sig.reason(), true);
            }
            case BUY -> {
                if (longPos != null) {
                    return; // 已有多头，静默返回（与 iOS 一致）
                }
                if (shortPos != null) {
                    // 单向持仓语义：反向持仓先平掉
                    okx.closePosition(creds, instId, shortPos.posSide());
                    tradeLog(instId, "先平空再开多", "平空", price, 0, "方向反转", true);
                }
                openPosition("buy", "long", sig, ctx, cfg, mine);
            }
            case SELL -> {
                if (shortPos != null) {
                    return;
                }
                if (longPos != null) {
                    okx.closePosition(creds, instId, longPos.posSide());
                    tradeLog(instId, "先平多再开空", "平多", price, 0, "方向反转", true);
                }
                openPosition("sell", "short", sig, ctx, cfg, mine);
            }
        }
    }

    /**
     * 开仓：先过 RiskManager（单笔金额 + 最大持仓上限），再设杠杆、换算张数、市价下单。
     * 对照 iOS: TradingEngine.openPosition
     * <p>
     * 注意一处有意的差异：iOS 计算当前持仓名义价值用的是 |pos| * price（忽略合约面值 ctVal），
     * Java 端改为「|pos| * ctVal * price」（现货为 |pos| * price），即真实名义价值（USDT），
     * 否则 BTC-USDT-SWAP（ctVal=0.01）这类合约会把持仓高估 100 倍，导致几乎无法开仓。
     */
    private void openPosition(String side, String posSide, Signal sig, StrategyContext ctx, AppConfig cfg,
                              List<Position> mine) throws OkxException {
        String instId = ctx.instId();
        double price = ctx.price();
        OkxClient.Credentials creds = creds(cfg);
        boolean swap = instId.endsWith("-SWAP");

        double unitNotional = swap ? okx.instrument(instId).ctVal() * price : price;
        double currentNotional = currentNotionalUsdt(mine, unitNotional);
        String openCheck = riskManager.checkOpenOrder(cfg.getTradeSizeUSDT(), currentNotional, cfg.getMaxPositionUSDT());
        if (openCheck != null) {
            tradeLog(instId, openCheck, "跳过", price, 0, sig.reason(), false);
            return;
        }

        // 杠杆（失败不阻塞下单，与 iOS 的 try? 一致）
        if (swap) {
            try {
                okx.setLeverage(creds, instId, cfg.getLeverage());
            } catch (OkxException e) {
                log.warn("设置杠杆失败（忽略）：{}", scrubber.scrub(e.getMessage()));
            }
        }

        // 张数换算：usdt * leverage / (ctVal * price)，向下取整到 lotSz，不小于 minSz
        double sz = okx.sizeFor(instId, cfg.getTradeSizeUSDT(), price, cfg.getLeverage());
        if (!(sz > 0)) {
            tradeLog(instId, "下单数量为 0，跳过", "跳过", price, 0, sig.reason(), false);
            return;
        }

        okx.marketOrder(creds, instId, side, posSide, sz, "cross");
        riskManager.recordTrade();
        boolean isLong = "long".equals(posSide);
        tradeLog(instId, "开" + (isLong ? "多" : "空") + "成功", isLong ? "开多" : "开空",
                price, sz, sig.reason(), true);
    }

    // ------------------------------------------------------------------ 手动操作

    /**
     * 一键全平（POST /api/trade/close-all）：拉取全部非零 SWAP 持仓逐个市价平仓。
     * 平仓属于降风险操作，不受频率限制，但会占用频率配额（成功平仓后 recordTrade）。
     */
    public CloseAllResult closeAll() {
        AppConfig cfg = configStore.get();
        OkxClient.Credentials creds = creds(cfg);

        List<Position> all;
        try {
            all = okx.positions(creds, "SWAP");
        } catch (OkxException e) {
            String msg = scrubber.scrub(e.getMessage());
            return new CloseAllResult(0, "获取持仓失败：" + msg);
        }

        int closed = 0;
        for (Position p : all) {
            try {
                okx.closePosition(creds, p.instId(), p.posSide());
                closed++;
                riskManager.recordTrade();
                String action = p.isLong() ? "平多" : "平空";
                tradeLog(p.instId(), "手动平仓", action, tickerPrice(), Math.abs(p.posDouble()), "用户操作", true);
            } catch (OkxException e) {
                String msg = scrubber.scrub(e.getMessage());
                tradeLog(p.instId(), "手动平仓失败", "ERROR", tickerPrice(), Math.abs(p.posDouble()), msg, false);
            }
        }

        // 立刻刷新引擎本地持仓缓存（引擎停止时 /api/status 也能反映最新状态）
        try {
            List<Position> filtered = new ArrayList<>();
            for (Position p : okx.positions(creds, "SWAP")) {
                if (p.instId().equals(cfg.getInstId())) {
                    filtered.add(p);
                }
            }
            positions = filtered;
        } catch (OkxException e) {
            log.warn("刷新持仓失败：{}", scrubber.scrub(e.getMessage()));
        }

        return new CloseAllResult(closed, "已平仓 " + closed + " 个");
    }

    /**
     * 手动下单（POST /api/trade/order）。业务失败用 success=false + message 表达（协议仍是 code=0）。
     * 同样要过 RiskManager：频率 + 单笔金额 + 最大持仓上限。
     */
    public OrderAck manualOrder(ManualOrderRequest req) {
        AppConfig cfg = configStore.get();
        String instId = (req.instId() == null || req.instId().isBlank()) ? cfg.getInstId() : req.instId().trim();
        String side = req.side() == null ? "" : req.side().trim().toLowerCase(Locale.US);
        if (!"buy".equals(side) && !"sell".equals(side)) {
            return new OrderAck("", false, "side 必须是 buy 或 sell");
        }
        double sz = req.sz() == null ? 0 : req.sz();
        if (!(sz > 0)) {
            return new OrderAck("", false, "sz 必须大于 0");
        }
        String ordType = (req.ordType() == null || req.ordType().isBlank()) ? "market" : req.ordType().trim();
        if (!"market".equalsIgnoreCase(ordType)) {
            return new OrderAck("", false, "当前仅支持 ordType=market");
        }
        String posSide = (req.posSide() == null || req.posSide().isBlank())
                ? ("buy".equals(side) ? "long" : "short")
                : req.posSide().trim();
        if (!"long".equals(posSide) && !"short".equals(posSide) && !"net".equals(posSide)) {
            return new OrderAck("", false, "posSide 必须是 long / short / net");
        }

        OkxClient.Credentials creds = creds(cfg);
        double reportedPrice = tickerPrice();
        try {
            Ticker tk = okx.ticker(instId);
            double price = tk.lastDouble();
            reportedPrice = price;
            if (!(price > 0)) {
                throw new OkxException("param", "无法获取 " + instId + " 的有效价格");
            }

            boolean swap = instId.endsWith("-SWAP");
            double unitNotional = swap ? okx.instrument(instId).ctVal() * price : price;
            double notional = sz * unitNotional;

            String freq = riskManager.checkFrequency(cfg.getMaxTradesPerHour());
            if (freq != null) {
                tradeLog(instId, freq, "跳过", price, 0, "手动下单", false);
                return new OrderAck("", false, freq);
            }

            List<Position> mineOnInst = new ArrayList<>();
            for (Position p : okx.positions(creds, swap ? "SWAP" : "SPOT")) {
                if (instId.equals(p.instId())) {
                    mineOnInst.add(p);
                }
            }
            String openCheck = riskManager.checkOpenOrder(notional,
                    currentNotionalUsdt(mineOnInst, unitNotional), cfg.getMaxPositionUSDT());
            if (openCheck != null) {
                tradeLog(instId, openCheck, "跳过", price, 0, "手动下单", false);
                return new OrderAck("", false, openCheck);
            }

            if (swap) {
                try {
                    okx.setLeverage(creds, instId, cfg.getLeverage());
                } catch (OkxException e) {
                    log.warn("设置杠杆失败（忽略）：{}", scrubber.scrub(e.getMessage()));
                }
            }

            OrderResult r = okx.marketOrder(creds, instId, side, posSide, sz, "cross");
            riskManager.recordTrade();
            String action = "buy".equals(side) ? "开多" : "开空";
            tradeLog(instId, action + "成功（手动）", action, price, sz, "", true);
            return new OrderAck(r.ordId() == null ? "" : r.ordId(), true, "");
        } catch (OkxException e) {
            String msg = scrubber.scrub(e.getMessage());
            tradeLog(instId, "手动下单失败", "ERROR", reportedPrice, sz, msg, false);
            return new OrderAck("", false, msg);
        }
    }

    // ------------------------------------------------------------------ 状态快照

    /** GET /api/status 的数据。positions 为空时返回空数组（不会是 null，方便前端直接遍历）。 */
    public StatusData status() {
        AppConfig c = configStore.get();
        Ticker tk = ticker;
        return new StatusData(
                running.get(),
                c.isDemoTrading(),
                c.getInstId(),
                c.getBar(),
                c.getActiveStrategy().wire(),
                tickCount.get(),
                TimeFormat.iso(lastTickAt),
                errorMessage,
                balanceUSDT,
                uptimeSeconds(),
                tk == null ? null : TickerView.of(tk),
                positions,
                lastSignal,
                lastAIReply);
    }

    public long uptimeSeconds() {
        long started = startedAtMs;
        if (started == 0) {
            return 0;
        }
        return Math.max(0, (System.currentTimeMillis() - started) / 1000);
    }

    // ------------------------------------------------------------------ 内部工具

    private void tradeLog(String instId, String title, String action,
                          double price, double size, String note, boolean ok) {
        logStore.log(scrubber.scrub(instId), scrubber.scrub(title), action, price, size, scrubber.scrub(note), ok);
    }

    private static OkxClient.Credentials creds(AppConfig cfg) {
        return new OkxClient.Credentials(cfg.getOkxApiKey(), cfg.getOkxApiSecret(),
                cfg.getOkxPassphrase(), cfg.isDemoTrading());
    }

    private static String instTypeOf(String instId) {
        return instId.endsWith("-SWAP") ? "SWAP" : "SPOT";
    }

    /** 当前持仓的名义价值（USDT）：swap 用 ctVal 折算，现货直接 pos*price */
    private static double currentNotionalUsdt(List<Position> positions, double unitNotional) {
        double sum = 0;
        for (Position p : positions) {
            sum += Math.abs(p.posDouble()) * unitNotional;
        }
        return sum;
    }

    private double tickerPrice() {
        Ticker t = ticker;
        return t == null ? 0 : t.lastDouble();
    }
}
