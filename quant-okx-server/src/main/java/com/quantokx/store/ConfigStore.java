package com.quantokx.store;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quantokx.config.SecretRegistry;
import com.quantokx.model.ApiModels.ConfigUpdate;
import com.quantokx.model.ApiModels.ConfigView;
import com.quantokx.model.AppConfig;
import com.quantokx.model.StrategyKind;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicReference;

/**
 * 每用户配置存储（多租户）：
 * - 每个用户一个实例，目录由 EngineRegistry 传入（data/users/{userId}/）；
 * - 内存快照 AtomicReference&lt;AppConfig&gt;，写新对象不原地改，保证引擎每轮读到一致快照；
 * - 持久化到 {userDir}/config.json（权限 600）；
 * - 密钥只存在本用户目录，且会注册到 SecretRegistry 供日志脱敏；
 * - 对外只暴露掩码视图（绝不返回明文）。
 */
public class ConfigStore {

    private static final Logger log = LoggerFactory.getLogger(ConfigStore.class);

    /** OKX k 线周期白名单 */
    private static final Set<String> ALLOWED_BARS = Set.of(
            "1m", "3m", "5m", "15m", "30m",
            "1H", "2H", "4H", "6H", "12H",
            "1D", "2D", "3D", "1W", "1M", "3M");

    private final ObjectMapper mapper;
    private final Path dataDir;
    private final Path configFile;
    private final SecretRegistry secrets;
    private final AtomicReference<AppConfig> ref = new AtomicReference<>(new AppConfig());

    public ConfigStore(ObjectMapper mapper, Path userDir, SecretRegistry secrets) {
        this.mapper = mapper;
        this.dataDir = userDir;
        this.configFile = userDir.resolve("config.json");
        this.secrets = secrets;
    }

    @PostConstruct
    void init() {
        try {
            Files.createDirectories(dataDir);
        } catch (IOException e) {
            log.warn("创建数据目录失败：{}", e.getMessage());
        }

        AppConfig loaded = null;
        if (Files.exists(configFile)) {
            try {
                loaded = mapper.readValue(configFile.toFile(), AppConfig.class);
            } catch (IOException e) {
                log.warn("读取配置失败，回退默认：{}", e.getMessage());
            }
        }
        if (loaded == null) {
            loaded = new AppConfig();
        }
        loaded.sanitize();
        ref.set(loaded);

        // 让日志脱敏器知道这个用户的密钥
        secrets.register(loaded.getOkxApiKey());
        secrets.register(loaded.getOkxApiSecret());
        secrets.register(loaded.getOkxPassphrase());
        secrets.register(loaded.getAiKey());

        log.info("用户配置目录：{}", dataDir.toAbsolutePath().normalize());
    }

    /** 当前生效配置（快照副本，调用方不应修改） */
    public AppConfig get() {
        return ref.get();
    }

    /** 掩码视图（GET /api/config、PUT /api/config 的返回） */
    public ConfigView maskedView() {
        AppConfig c = get();
        boolean okxConfigured = notBlank(c.getOkxApiKey()) && notBlank(c.getOkxApiSecret()) && notBlank(c.getOkxPassphrase());
        return new ConfigView(
                okxConfigured,
                mask(c.getOkxApiKey()),
                c.isDemoTrading(),
                c.getInstId(),
                c.getBar(),
                c.getActiveStrategy().wire(),
                c.getTradeSizeUSDT(),
                c.getLeverage(),
                c.getPollSeconds(),
                c.getStopLossPct(),
                c.getTakeProfitPct(),
                c.getMaxPositionUSDT(),
                c.getMaxTradesPerHour(),
                c.isAiEnabled(),
                c.getAiBaseURL(),
                c.getAiModel(),
                notBlank(c.getAiKey()));
    }

    /**
     * 更新配置（部分更新）：null/省略 = 不改；密钥字段 ""=清空、含 "****" 视为掩码回显忽略。
     * 会员权益校验在 ApiController 层完成（那里才有用户上下文）。
     */
    public synchronized void update(ConfigUpdate req) {
        if (req == null) {
            throw new IllegalArgumentException("请求体不能为空");
        }
        AppConfig next = ref.get().copy();

        next.setOkxApiKey(applySecret(req.okxApiKey(), next.getOkxApiKey()));
        next.setOkxApiSecret(applySecret(req.okxApiSecret(), next.getOkxApiSecret()));
        next.setOkxPassphrase(applySecret(req.okxPassphrase(), next.getOkxPassphrase()));
        next.setAiKey(applySecret(req.aiKey(), next.getAiKey()));

        if (req.demoTrading() != null) {
            next.setDemoTrading(req.demoTrading());
        }
        if (req.instId() != null) {
            String v = req.instId().trim();
            if (v.isEmpty()) {
                throw new IllegalArgumentException("instId 不能为空");
            }
            if (!v.matches("[A-Za-z0-9_-]+")) {
                throw new IllegalArgumentException("instId 格式不正确：" + v);
            }
            next.setInstId(v);
        }
        if (req.bar() != null) {
            String v = req.bar().trim();
            if (!ALLOWED_BARS.contains(v)) {
                throw new IllegalArgumentException("bar 不支持：" + v + "（可选：1m/5m/15m/30m/1H/4H/1D …）");
            }
            next.setBar(v);
        }
        if (req.activeStrategy() != null) {
            StrategyKind kind = StrategyKind.fromWireOrNull(req.activeStrategy().trim());
            if (kind == null) {
                throw new IllegalArgumentException("未知策略：" + req.activeStrategy()
                        + "（可选：grid/maCross/rsi/breakout/ai）");
            }
            next.setActiveStrategy(kind);
        }
        if (req.tradeSizeUSDT() != null) {
            next.setTradeSizeUSDT(requireRange("tradeSizeUSDT", req.tradeSizeUSDT(), 0.000001, 1000000));
        }
        if (req.leverage() != null) {
            int lev = req.leverage();
            if (lev < 1 || lev > 125) {
                throw new IllegalArgumentException("leverage 超出范围（1 ~ 125）");
            }
            next.setLeverage(lev);
        }
        if (req.pollSeconds() != null) {
            int p = Math.max(5, Math.min(3600, req.pollSeconds()));
            next.setPollSeconds(p);
        }
        if (req.stopLossPct() != null) {
            next.setStopLossPct(requireRange("stopLossPct", req.stopLossPct(), 0.000001, 100));
        }
        if (req.takeProfitPct() != null) {
            next.setTakeProfitPct(requireRange("takeProfitPct", req.takeProfitPct(), 0.000001, 1000));
        }
        if (req.maxPositionUSDT() != null) {
            next.setMaxPositionUSDT(requireRange("maxPositionUSDT", req.maxPositionUSDT(), 0.000001, 1000000000));
        }
        if (req.maxTradesPerHour() != null) {
            int m = req.maxTradesPerHour();
            if (m < 0 || m > 1000) {
                throw new IllegalArgumentException("maxTradesPerHour 超出范围（0 ~ 1000）");
            }
            next.setMaxTradesPerHour(m);
        }
        if (req.aiEnabled() != null) {
            next.setAiEnabled(req.aiEnabled());
        }
        if (req.aiBaseURL() != null) {
            String v = req.aiBaseURL().trim();
            if (!v.isEmpty() && !v.startsWith("http")) {
                throw new IllegalArgumentException("aiBaseURL 必须是 http(s) 地址");
            }
            next.setAiBaseURL(v);
        }
        if (req.aiModel() != null) {
            next.setAiModel(req.aiModel().trim());
        }

        next.sanitize();
        ref.set(next);
        persist(next);

        secrets.register(next.getOkxApiKey());
        secrets.register(next.getOkxApiSecret());
        secrets.register(next.getOkxPassphrase());
        secrets.register(next.getAiKey());

        log.info("配置已更新：instId={} bar={} strategy={} demo={} poll={}s",
                next.getInstId(), next.getBar(), next.getActiveStrategy().wire(),
                next.isDemoTrading(), next.getPollSeconds());
    }

    // ------------------------------------------------------------------ 内部工具

    private static void addSecret(java.util.List<String> out, String v) {
        if (v != null && v.length() >= 4 && !out.contains(v)) {
            out.add(v);
        }
    }

    private static String applySecret(String incoming, String current) {
        if (incoming == null) {
            return current;
        }
        if (incoming.contains("****")) {
            return current;
        }
        return incoming;
    }

    private static double requireRange(String name, double value, double min, double max) {
        if (Double.isNaN(value) || value < min || value > max) {
            throw new IllegalArgumentException(name + " 超出范围（" + min + " ~ " + max + "）");
        }
        return value;
    }

    private static String mask(String v) {
        if (v == null || v.isEmpty()) {
            return "未配置";
        }
        if (v.length() <= 8) {
            return "****";
        }
        return v.substring(0, 4) + "****" + v.substring(v.length() - 4);
    }

    private static boolean notBlank(String v) {
        return v != null && !v.isEmpty();
    }

    private void persist(AppConfig config) {
        Path tmp = dataDir.resolve("config.json.tmp");
        try {
            Files.createDirectories(dataDir);
            mapper.writerWithDefaultPrettyPrinter().writeValue(tmp.toFile(), config);
            try {
                Files.move(tmp, configFile, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException e) {
                Files.move(tmp, configFile, StandardCopyOption.REPLACE_EXISTING);
            }
            try {
                Files.setPosixFilePermissions(configFile, PosixFilePermissions.fromString("rw-------"));
            } catch (UnsupportedOperationException | IOException e) {
                log.warn("无法设置权限 600：{}", e.getMessage());
            }
        } catch (IOException e) {
            log.error("配置持久化失败（内存中已生效）：{}", e.getMessage());
        }
    }
}