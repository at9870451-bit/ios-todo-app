package com.quantokx;

import com.quantokx.config.QuantOkxProperties;
import com.quantokx.model.AppConfig;
import com.quantokx.store.ConfigStore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.core.env.Environment;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * QuantOKX 后端入口：OKX 自动交易引擎 + iOS App 控制台接口。
 * <p>
 * 启动后请留意日志里的「模拟盘 / 实盘」提示 —— 默认 demoTrading=true（模拟盘）。
 */
@SpringBootApplication
@EnableScheduling
public class QuantOkxApplication {

    private static final Logger log = LoggerFactory.getLogger(QuantOkxApplication.class);

    public static void main(String[] args) {
        ConfigurableApplicationContext ctx = SpringApplication.run(QuantOkxApplication.class, args);
        printStartupBanner(ctx);
    }

    /** 启动横幅：明确当前是模拟盘还是实盘，并提示默认鉴权令牌风险 */
    private static void printStartupBanner(ConfigurableApplicationContext ctx) {
        QuantOkxProperties props = ctx.getBean(QuantOkxProperties.class);
        ConfigStore store = ctx.getBean(ConfigStore.class);
        Environment env = ctx.getEnvironment();
        AppConfig cfg = store.get();

        String port = env.getProperty("local.server.port", env.getProperty("server.port", "8080"));

        log.info("========================================================");
        log.info("QuantOKX 后端已启动  v{}  端口 {}", props.getVersion(), port);
        if (cfg.isDemoTrading()) {
            log.info("交易模式：模拟盘（demoTrading=true，签名请求带 x-simulated-trading:1）—— 安全");
        } else {
            log.warn("交易模式：！！！实盘！！！ demoTrading=false，指令会以真实资金成交，请再次确认！");
        }
        boolean okxReady = notEmpty(cfg.getOkxApiKey()) && notEmpty(cfg.getOkxApiSecret())
                && notEmpty(cfg.getOkxPassphrase());
        log.info("OKX 凭据：{}（key {}；来源：环境变量 OKX_API_KEY/OKX_API_SECRET/OKX_PASSPHRASE 优先，其次 ./data/config.json）",
                okxReady ? "已配置" : "未配置", maskForLog(cfg.getOkxApiKey()));
        log.info("默认策略：{}  交易对：{}  周期：{}  轮询：{}s",
                cfg.getActiveStrategy().wire(), cfg.getInstId(), cfg.getBar(), cfg.getPollSeconds());
        if ("changeme".equals(props.getAuthToken())) {
            log.warn("鉴权令牌仍是默认值 changeme，请修改 application.yml 的 quantokx.auth-token "
                    + "（或设置环境变量 QUANT_OKX_AUTH_TOKEN）");
        }
        log.info("========================================================");
    }

    private static boolean notEmpty(String v) {
        return v != null && !v.isEmpty();
    }

    /** 日志里只出现掩码，绝不打印明文密钥 */
    private static String maskForLog(String v) {
        if (v == null || v.isEmpty()) {
            return "未配置";
        }
        if (v.length() <= 8) {
            return "****";
        }
        return v.substring(0, 4) + "****" + v.substring(v.length() - 4);
    }
}
