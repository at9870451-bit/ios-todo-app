package com.quantokx.pay;

import com.quantokx.config.QuantOkxProperties;
import com.quantokx.auth.UserStore;
import com.quantokx.model.MembershipPlan;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.security.MessageDigest;
import java.util.Map;
import java.util.Optional;
import java.util.TreeMap;

/**
 * 易支付（epay）对接：
 * - 配置来自环境变量 EPAY_API_URL / EPAY_PID / EPAY_KEY（三者齐全才算已配置）；
 * - 签名：参数按 key ASCII 升序、剔除 sign/sign_type/空值，拼 a=b&c=d 后直接拼 key，MD5 小写；
 * - 下单构造 GET 提交地址（浏览器打开即进入收银台）。
 */
@Component
public class EpayService {

    private static final Logger log = LoggerFactory.getLogger(EpayService.class);

    private final com.fasterxml.jackson.databind.ObjectMapper mapper;
    private final QuantOkxProperties props;
    private java.nio.file.Path payFile;
    private List<PayOrder> pays = List.of();

    public EpayService(com.fasterxml.jackson.databind.ObjectMapper mapper, QuantOkxProperties props) {
        this.mapper = mapper;
        this.props = props;
    }

    /** 一笔支付订单（PENDING → PAID） */
    public record PayOrder(String outTradeNo, String userId, String planId, String planName,
                           int months, double total, String status, String createdAt) {
    }

    private static class PayOrdersFile {
        public List<PayOrder> orders;
    }

    @jakarta.annotation.PostConstruct
    void init() {
        payFile = java.nio.file.Paths.get(props.getDataDir()).resolve("payorders.json");
        if (java.nio.file.Files.exists(payFile)) {
            try {
                PayOrdersFile f = mapper.readValue(payFile.toFile(), PayOrdersFile.class);
                pays = f.orders == null ? List.of() : f.orders;
            } catch (IOException e) {
                log.warn("读取支付订单失败：{}", e.getMessage());
            }
        }
    }

    /** 创建待支付订单 */
    public synchronized PayOrder createPending(String userId, MembershipPlan plan,
                                               int months, double total) {
        String no = "QK" + java.time.LocalDateTime.now()
                .format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss"))
                + String.format("%03d", new java.security.SecureRandom().nextInt(1000));
        PayOrder o = new PayOrder(no, userId, plan.id(), plan.name(), months, total,
                "PENDING", com.quantokx.model.TimeFormat.isoNow());
        List<PayOrder> next = new ArrayList<>(pays);
        next.add(0, o);
        if (next.size() > 500) {
            next = new ArrayList<>(next.subList(0, 500));
        }
        pays = List.copyOf(next);
        persistPays();
        log.info("创建支付订单：{} 用户 {} {} ¥{}", no, userId, plan.name(), total);
        return o;
    }

    public synchronized Optional<PayOrder> findByOutTradeNo(String no) {
        return pays.stream().filter(o -> o.outTradeNo().equals(no)).findFirst();
    }

    /**
     * 回调标记支付并开通会员。幂等：已 PAID 直接返回 true。
     *
     * @return true = 本次或之前已成功开通；false = 订单不存在/开通失败
     */
    public synchronized boolean markPaid(String outTradeNo, UserStore users) {
        Optional<PayOrder> opt = findByOutTradeNo(outTradeNo);
        if (opt.isEmpty()) {
            log.warn("回调订单不存在：{}", outTradeNo);
            return false;
        }
        PayOrder o = opt.get();
        if ("PAID".equals(o.status())) {
            return true; // 幂等
        }
        try {
            MembershipPlan plan = MembershipPlan.findByIdOrNull(o.planId());
            if (plan == null) {
                log.error("回调订单套餐不存在：{}", o.planId());
                return false;
            }
            users.activateMembership(o.userId(), plan, o.months(), "PAID");
        } catch (Exception e) {
            log.error("回调开通会员失败：{}", e.getMessage());
            return false;
        }
        List<PayOrder> next = new ArrayList<>();
        for (PayOrder x : pays) {
            next.add(x.outTradeNo().equals(outTradeNo)
                    ? new PayOrder(x.outTradeNo(), x.userId(), x.planId(), x.planName(),
                    x.months(), x.total(), "PAID", x.createdAt())
                    : x);
        }
        pays = List.copyOf(next);
        persistPays();
        return true;
    }

    private void persistPays() {
        try {
            java.nio.file.Files.createDirectories(payFile.getParent());
            PayOrdersFile f = new PayOrdersFile();
            f.orders = pays;
            mapper.writerWithDefaultPrettyPrinter().writeValue(payFile.toFile(), f);
        } catch (IOException e) {
            log.error("支付订单持久化失败：{}", e.getMessage());
        }
    }

    public boolean configured() {
        return notBlank(props.getEpayApiUrl())
                && notBlank(props.getEpayPid())
                && notBlank(props.getEpayKey());
    }

    /**
     * 构建易支付收银台地址。
     *
     * @param outTradeNo  商户订单号
     * @param name        商品名
     * @param money       金额（元，两位小数）
     * @return 可直接在浏览器打开的提交地址；未配置时返回 null
     */
    public String buildPayUrl(String outTradeNo, String name, double money) {
        if (!configured()) {
            return null;
        }
        String api = props.getEpayApiUrl().trim();
        while (api.endsWith("/")) {
            api = api.substring(0, api.length() - 1);
        }
        String notify = props.getServerBaseUrl() + "/api/pay/notify";
        String returnUrl = props.getServerBaseUrl() + "/api/pay/return";

        TreeMap<String, String> params = new TreeMap<>();
        params.put("pid", props.getEpayPid().trim());
        params.put("type", "alipay");
        params.put("out_trade_no", outTradeNo);
        params.put("notify_url", notify);
        params.put("return_url", returnUrl);
        params.put("name", name);
        params.put("money", String.format(java.util.Locale.US, "%.2f", money));

        String sign = sign(params, props.getEpayKey().trim());
        StringBuilder sb = new StringBuilder(api).append("/submit.php?");
        for (Map.Entry<String, String> e : params.entrySet()) {
            sb.append(urlEncode(e.getKey())).append('=')
              .append(urlEncode(e.getValue())).append('&');
        }
        sb.append("sign=").append(sign).append("&sign_type=MD5");
        return sb.toString();
    }

    /**
     * 校验回调签名（易支付异步通知）。
     * 注意：易支付回调参数里通常还带 trade_no / trade_status 等，验证时只剔除 sign/sign_type/空值。
     */
    public boolean verifyNotify(Map<String, String> params) {
        if (!configured()) {
            return false;
        }
        String sign = params.get("sign");
        if (sign == null || sign.isEmpty()) {
            return false;
        }
        TreeMap<String, String> sorted = new TreeMap<>();
        for (Map.Entry<String, String> e : params.entrySet()) {
            String k = e.getKey();
            String v = e.getValue();
            if ("sign".equalsIgnoreCase(k) || "sign_type".equalsIgnoreCase(k)) {
                continue;
            }
            if (v == null || v.isEmpty()) {
                continue;
            }
            sorted.put(k, v);
        }
        String expected = sign(sorted, props.getEpayKey().trim());
        return expected.equalsIgnoreCase(sign);
    }

    // ------------------------------------------------------------------ 工具

    /** 易支付标准签名：a=b&c=d… + key 直接拼，MD5 小写（key 不做参与编码） */
    private static String sign(TreeMap<String, String> params, String key) {
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> e : params.entrySet()) {
            sb.append(e.getKey()).append('=').append(e.getValue()).append('&');
        }
        sb.setLength(Math.max(0, sb.length() - 1));
        String raw = sb + key;
        try {
            byte[] d = MessageDigest.getInstance("MD5")
                    .digest(raw.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte b : d) {
                hex.append(String.format("%02x", b));
            }
            return hex.toString();
        } catch (Exception e) {
            throw new IllegalStateException("MD5 签名失败", e);
        }
    }

    private static String urlEncode(String v) {
        try {
            return URLEncoder.encode(v, StandardCharsets.UTF_8);
        } catch (Exception e) {
            return v;
        }
    }

    private static boolean notBlank(String v) {
        return v != null && !v.isEmpty();
    }
}