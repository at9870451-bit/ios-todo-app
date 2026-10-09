package com.quantokx.model;

/**
 * 运行时配置（内存快照 + ./data/config.json 持久化）。
 * <p>
 * 注意：ConfigStore 里持有的是 AtomicReference 快照，实例一旦发布就不应再被外部修改；
 * ConfigStore.update() 采用「copy → 修改 → 发布」的方式写入，保证引擎每轮读到的配置是一致的。
 * <p>
 * 默认值遵循「默认安全」：demoTrading = true（模拟盘）。
 */
public class AppConfig {

    // ---- OKX 凭据（读取优先级：环境变量 > config.json，见 ConfigStore） ----
    private String okxApiKey = "";
    private String okxApiSecret = "";
    private String okxPassphrase = "";

    /** 模拟盘开关，默认 true —— 第一次跑千万不要用真钱 */
    private boolean demoTrading = true;

    // ---- 交易参数 ----
    private String instId = "BTC-USDT-SWAP";
    private String bar = "1m";
    private StrategyKind activeStrategy = StrategyKind.MA_CROSS;
    private double tradeSizeUSDT = 10;
    private int leverage = 3;
    private int pollSeconds = 15;

    // ---- 风控 ----
    private double stopLossPct = 2.0;
    private double takeProfitPct = 4.0;
    private double maxPositionUSDT = 100;
    private int maxTradesPerHour = 10;

    // ---- AI ----
    private boolean aiEnabled = false;
    private String aiBaseURL = "https://api.openai.com/v1/chat/completions";
    private String aiModel = "gpt-4o-mini";
    private String aiKey = "";

    public String getOkxApiKey() {
        return okxApiKey;
    }

    public void setOkxApiKey(String okxApiKey) {
        this.okxApiKey = okxApiKey;
    }

    public String getOkxApiSecret() {
        return okxApiSecret;
    }

    public void setOkxApiSecret(String okxApiSecret) {
        this.okxApiSecret = okxApiSecret;
    }

    public String getOkxPassphrase() {
        return okxPassphrase;
    }

    public void setOkxPassphrase(String okxPassphrase) {
        this.okxPassphrase = okxPassphrase;
    }

    public boolean isDemoTrading() {
        return demoTrading;
    }

    public void setDemoTrading(boolean demoTrading) {
        this.demoTrading = demoTrading;
    }

    public String getInstId() {
        return instId;
    }

    public void setInstId(String instId) {
        this.instId = instId;
    }

    public String getBar() {
        return bar;
    }

    public void setBar(String bar) {
        this.bar = bar;
    }

    public StrategyKind getActiveStrategy() {
        return activeStrategy;
    }

    public void setActiveStrategy(StrategyKind activeStrategy) {
        this.activeStrategy = activeStrategy;
    }

    public double getTradeSizeUSDT() {
        return tradeSizeUSDT;
    }

    public void setTradeSizeUSDT(double tradeSizeUSDT) {
        this.tradeSizeUSDT = tradeSizeUSDT;
    }

    public int getLeverage() {
        return leverage;
    }

    public void setLeverage(int leverage) {
        this.leverage = leverage;
    }

    public int getPollSeconds() {
        return pollSeconds;
    }

    public void setPollSeconds(int pollSeconds) {
        this.pollSeconds = pollSeconds;
    }

    public double getStopLossPct() {
        return stopLossPct;
    }

    public void setStopLossPct(double stopLossPct) {
        this.stopLossPct = stopLossPct;
    }

    public double getTakeProfitPct() {
        return takeProfitPct;
    }

    public void setTakeProfitPct(double takeProfitPct) {
        this.takeProfitPct = takeProfitPct;
    }

    public double getMaxPositionUSDT() {
        return maxPositionUSDT;
    }

    public void setMaxPositionUSDT(double maxPositionUSDT) {
        this.maxPositionUSDT = maxPositionUSDT;
    }

    public int getMaxTradesPerHour() {
        return maxTradesPerHour;
    }

    public void setMaxTradesPerHour(int maxTradesPerHour) {
        this.maxTradesPerHour = maxTradesPerHour;
    }

    public boolean isAiEnabled() {
        return aiEnabled;
    }

    public void setAiEnabled(boolean aiEnabled) {
        this.aiEnabled = aiEnabled;
    }

    public String getAiBaseURL() {
        return aiBaseURL;
    }

    public void setAiBaseURL(String aiBaseURL) {
        this.aiBaseURL = aiBaseURL;
    }

    public String getAiModel() {
        return aiModel;
    }

    public void setAiModel(String aiModel) {
        this.aiModel = aiModel;
    }

    public String getAiKey() {
        return aiKey;
    }

    public void setAiKey(String aiKey) {
        this.aiKey = aiKey;
    }

    /** 深拷贝（字段全部为不可变类型，浅拷贝即深拷贝） */
    public AppConfig copy() {
        AppConfig c = new AppConfig();
        c.okxApiKey = this.okxApiKey;
        c.okxApiSecret = this.okxApiSecret;
        c.okxPassphrase = this.okxPassphrase;
        c.demoTrading = this.demoTrading;
        c.instId = this.instId;
        c.bar = this.bar;
        c.activeStrategy = this.activeStrategy;
        c.tradeSizeUSDT = this.tradeSizeUSDT;
        c.leverage = this.leverage;
        c.pollSeconds = this.pollSeconds;
        c.stopLossPct = this.stopLossPct;
        c.takeProfitPct = this.takeProfitPct;
        c.maxPositionUSDT = this.maxPositionUSDT;
        c.maxTradesPerHour = this.maxTradesPerHour;
        c.aiEnabled = this.aiEnabled;
        c.aiBaseURL = this.aiBaseURL;
        c.aiModel = this.aiModel;
        c.aiKey = this.aiKey;
        return c;
    }

    /**
     * 修复从 config.json 读到的脏数据（null / 越界），保证引擎拿到可用配置。
     */
    public void sanitize() {
        okxApiKey = blankToEmpty(okxApiKey);
        okxApiSecret = blankToEmpty(okxApiSecret);
        okxPassphrase = blankToEmpty(okxPassphrase);
        aiKey = blankToEmpty(aiKey);
        if (instId == null || instId.isBlank()) {
            instId = "BTC-USDT-SWAP";
        }
        if (bar == null || bar.isBlank()) {
            bar = "1m";
        }
        if (activeStrategy == null) {
            activeStrategy = StrategyKind.MA_CROSS;
        }
        if (!(tradeSizeUSDT > 0)) {
            tradeSizeUSDT = 10;
        }
        if (leverage < 1 || leverage > 125) {
            leverage = 3;
        }
        if (pollSeconds < 5) {
            pollSeconds = 5;
        }
        if (pollSeconds > 3600) {
            pollSeconds = 3600;
        }
        if (!(stopLossPct > 0)) {
            stopLossPct = 2.0;
        }
        if (!(takeProfitPct > 0)) {
            takeProfitPct = 4.0;
        }
        if (!(maxPositionUSDT > 0)) {
            maxPositionUSDT = 100;
        }
        if (maxTradesPerHour < 0) {
            maxTradesPerHour = 10;
        }
        if (aiBaseURL == null) {
            aiBaseURL = "";
        }
        if (aiModel == null) {
            aiModel = "";
        }
    }

    private static String blankToEmpty(String v) {
        return v == null ? "" : v;
    }
}
