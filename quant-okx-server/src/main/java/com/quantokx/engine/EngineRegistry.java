package com.quantokx.engine;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quantokx.ai.AiClient;
import com.quantokx.config.SecretRegistry;
import com.quantokx.auth.SessionStore;
import com.quantokx.auth.UserStore;
import com.quantokx.config.QuantOkxProperties;
import com.quantokx.config.SecretScrubber;
import com.quantokx.okx.OkxClient;
import com.quantokx.store.ConfigStore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 引擎注册表：每个用户一份独立的运行环境（ConfigStore / TradeLogStore / RiskManager / TradingEngine）。
 * 心跳每 1 秒唤醒一次，遍历所有运行中的引擎，按各自 pollSeconds（含会员权益钳制）判断是否该跑下一轮。
 * 懒创建：用户第一次请求时才建对应引擎，避免无用户时浪费内存。
 */
@Component
public class EngineRegistry {

    private static final Logger log = LoggerFactory.getLogger(EngineRegistry.class);

    private final ObjectMapper mapper;
    private final QuantOkxProperties props;
    private final UserStore userStore;
    private final SessionStore sessionStore;
    private final AiClient aiClient;
    private final SecretScrubber scrubber;
    private final OkxClient okx;
    private final SecretRegistry secrets;

    private final Map<String, UserEnv> envs = new ConcurrentHashMap<>();

    /** 每个引擎最近一次启动轮询的时间戳（毫秒），用于按 pollSeconds 节流 */
    private static final class UserEnv {
        final ConfigStore config;
        final TradeLogStore logs;
        final RiskManager risk;
        final TradingEngine engine;
        volatile long lastTickMs;

        UserEnv(ConfigStore config, TradeLogStore logs, RiskManager risk, TradingEngine engine) {
            this.config = config;
            this.logs = logs;
            this.risk = risk;
            this.engine = engine;
        }
    }

    public EngineRegistry(ObjectMapper mapper,
                          QuantOkxProperties props,
                          UserStore userStore,
                          SessionStore sessionStore,
                          AiClient aiClient,
                          SecretScrubber scrubber,
                          OkxClient okx,
                          SecretRegistry secrets) {
        this.mapper = mapper;
        this.props = props;
        this.userStore = userStore;
        this.sessionStore = sessionStore;
        this.aiClient = aiClient;
        this.scrubber = scrubber;
        this.okx = okx;
        this.secrets = secrets;
    }

    /** 取（必要时创建）某用户的运行环境 */
    public UserEnv env(String userId) {
        return envs.computeIfAbsent(userId, uid -> {
            try {
                Files.createDirectories(userStore.userDir(uid));
            } catch (Exception e) {
                log.warn("创建用户目录失败：{}", e.getMessage());
            }
            ConfigStore cfg = new ConfigStore(mapper, userStore.userDir(uid), secrets);
            TradeLogStore tl = new TradeLogStore();
            RiskManager rm = new RiskManager();
            TradingEngine eng = new TradingEngine(okx, cfg, tl, aiClient, rm, scrubber, userStore, uid);
            log.info("为用户 {} 创建交易引擎", uid);
            return new UserEnv(cfg, tl, rm, eng);
        });
    }

    public TradingEngine engine(String userId) {
        return env(userId).engine;
    }

    public ConfigStore configStore(String userId) {
        return env(userId).config;
    }

    public TradeLogStore logStore(String userId) {
        return env(userId).logs;
    }

    /**
     * 心跳：1 秒一次，遍历所有引擎。
     * 说明：@Scheduled 的 SpEL 只在注册时解析一次，所以固定 1 秒心跳 + 逐引擎按 pollSeconds 节流，
     * 这样 PUT /api/config 修改 pollSeconds（或会员等级变化）后，下一轮立即生效。
     */
    @Scheduled(fixedDelayString = "1000")
    public void heartbeat() {
        long now = System.currentTimeMillis();
        for (Map.Entry<String, UserEnv> e : envs.entrySet()) {
            UserEnv ue = e.getValue();
            if (!ue.engine.isRunning()) {
                continue;
            }
            int pollSeconds = Math.max(
                    userStore.benefitsOf(e.getKey()).minPollSeconds(),
                    Math.max(5, ue.config.get().getPollSeconds()));

            if (ue.lastTickMs != 0 && now - ue.lastTickMs < pollSeconds * 1000L) {
                continue;
            }
            ue.lastTickMs = now;
            try {
                ue.engine.tick();
            } catch (Exception ex) {
                log.error("引擎轮询异常（用户 {}）：{}", e.getKey(), scrubber.scrub(ex.toString()));
            }
        }
        sessionStore.prune();
    }

    /** 统计信息（调试用） */
    public List<String> snapshot() {
        List<String> out = new ArrayList<>();
        for (Map.Entry<String, UserEnv> e : envs.entrySet()) {
            out.add(e.getKey() + " running=" + e.getValue().engine.isRunning()
                    + " ticks=" + e.getValue().engine.status().tickCount());
        }
        return out;
    }

    public int engineCount() {
        return envs.size();
    }
}