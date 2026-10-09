package com.quantokx.store;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quantokx.config.QuantOkxProperties;
import com.quantokx.model.ApiModels.ConfigUpdate;
import com.quantokx.model.ApiModels.ConfigView;
import com.quantokx.model.AppConfig;
import com.quantokx.model.StrategyKind;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicReference;

/**
 * 配置存储：
 * - 内存快照（AtomicReference&lt;AppConfig&gt;，写新对象、不原地改，保证引擎每轮读到一致快照）；
 * - 持久化到 ./data/config.json（权限 600）；
 * - 密钥读取优先级：环境变量 OKX_API_KEY / OKX_API_SECRET / OKX_PASSPHRASE &gt; config.json；
 * - 对外只暴露掩码视图（GET /api/config 绝不返回明文）。
 */
@Component
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
    private final long pollPulseMillis;
    private final AtomicReference<AppConfig> ref = new AtomicReference<>(new AppConfig());

    /** 环境变量来源的密钥（null 表示未设置） */
    private volatile String envApiKey;
    private volatile String envApiSecret;
    private volatile String envPassphrase;

    public ConfigStore(ObjectMapper mapper, QuantOkxProperties properties) {
        this.mapper = mapper;
        this.dataDir = Paths.get(properties.getDataDir());
        this.configFile = this.dataDir.resolve("config.json");
        long pulse = properties.getPollPulseMillis();
        this.pollPulseMillis = pulse > 0 ? pulse : 1000L;
    }

    @PostConstruct
    void init() {
        envApiKey = envOrNull("OKX_API_KEY");
        envApiSecret = envOrNull("OKX_API_SECRET");
        envPassphrase = envOrNull("OKX_PASSPHRASE");

        try {
            Files.createDirectories(dataDir);
        } catch (IOException e) {
            log.warn("创建数据目录 {} 失败：{}", dataDir, e.getMessage());
        }

        AppConfig loaded = null;
        if (Files.exists(configFile)) {
            try {
                loaded = mapper.readValue(configFile.toFile(), AppConfig.class);
            } catch (IOException e) {
                log.warn("读取 {} 失败，回退默认配置：{}", configFile, e.getMessage());
            }
        }
        if (loaded == null) {
            loaded = new AppConfig();
        }
        loaded.sanitize();
        ref.set(loaded);

        log.info("配置目录：{}（文件：{}）", dataDir.toAbsolutePath().normalize(), configFile.getFileName());
        if (envApiKey != null || envApiSecret != null || envPassphrase != null) {
            log.info("检测到 OKX 凭据环境变量（OKX_API_KEY / OKX_API_SECRET / OKX_PASSPHRASE），将优先于 config.json 使用");
        }
    }

    /**
     * @Scheduled(fixedDelayString = "#{@configStore.pollMillis}") 取用的心跳间隔。
     * 说明：SpEL 在注册定时任务时只会解析一次，所以这里固定返回一个较短的心跳，
     * 真正的轮询间隔由 TradingEngine 每轮读取 pollSeconds 判断 —— 这样 PUT /api/config
     * 修改 pollSeconds 后，下一轮立即生效（热更新）。
     */
    public long getPollMillis() {
        return pollPulseMillis;
    }

    /**
     * 当前生效配置（含环境变量覆盖）。返回的是快照副本，调用方不应修改。
     */
    public AppConfig get() {
        AppConfig cur = ref.get();
        if (envApiKey == null && envApiSecret == null && envPassphrase == null) {
            return cur;
        }
        AppConfig overlay = cur.copy();
        if (envApiKey != null) {
            overlay.setOkxApiKey(envApiKey);
        }
        if (envApiSecret != null) {
            overlay.setOkxApiSecret(envApiSecret);
        }
        if (envPassphrase != null) {
            overlay.setOkxPassphrase(envPassphrase);
        }
        return overlay;
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
     * 校验失败抛 IllegalArgumentException（由 GlobalExceptionHandler 转成 code=400）。
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
            // 与 iOS 引擎 max(5, pollSeconds) 的行为对齐：这里直接收敛到 [5, 3600]
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
        log.info("配置已更新：instId={} bar={} strategy={} demo={} poll={}s",
                next.getInstId(), next.getBar(), next.getActiveStrategy().wire(), next.isDemoTrading(), next.getPollSeconds());
    }

    /** 供脱敏器使用的候选密钥列表（内存 + 环境变量，去重、长度 &gt;= 4） */
    public List<String> secretCandidates() {
        AppConfig c = ref.get();
        List<String> out = new ArrayList<>();
        addSecret(out, c.getOkxApiKey());
        addSecret(out, c.getOkxApiSecret());
        addSecret(out, c.getOkxPassphrase());
        addSecret(out, c.getAiKey());
        addSecret(out, envApiKey);
        addSecret(out, envApiSecret);
        addSecret(out, envPassphrase);
        return out;
    }

    // ------------------------------------------------------------------ 内部工具

    private static void addSecret(List<String> out, String v) {
        if (v != null && v.length() >= 4 && !out.contains(v)) {
            out.add(v);
        }
    }

    /** 密钥字段应用规则 */
    private static String applySecret(String incoming, String current) {
        if (incoming == null) {
            return current;                 // 省略 / null：不改
        }
        if (incoming.contains("****")) {
            return current;                 // 前端把掩码回传了：忽略，避免把 "abcd****wxyz" 存成密钥
        }
        return incoming;                    // ""：清空；其他：覆盖
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

    private static String envOrNull(String name) {
        String v = System.getenv(name);
        return (v == null || v.isEmpty()) ? null : v;
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
                log.warn("无法把 {} 权限设置为 600：{}", configFile, e.getMessage());
            }
        } catch (IOException e) {
            // 配置已在本进程生效；只有落盘失败时提示（重启后会丢失）
            log.error("配置持久化失败（内存中已生效，重启会丢失）：{}", e.getMessage());
        }
    }
}
