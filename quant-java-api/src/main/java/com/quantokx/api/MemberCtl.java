package com.quantokx.api;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;

/**
 * 会员接口（iOS App）：套餐、状态、订单、购买。
 * 支付：配置了易支付（sys_config.pay_enabled=1 且 pay_api_url 非空）时生成待支付订单；
 *       未配置时走演示模式（demo_direct）直接开通，与 v1.x 行为一致，便于联调。
 */
@RestController
@RequestMapping("/api/member")
public class MemberCtl {
    Long uid(HttpServletRequest q) { return (Long) q.getAttribute("uid"); }

    @GetMapping("/plans")
    public Object plans(HttpServletRequest q) {
        Long uid = q.getAttribute("uid") instanceof Long u ? u : null;
        Map<String, Object> badge = uid == null ? null : MemberSvc.badgeOf(uid);
        Map<String, Object> limits = uid == null ? null : Member.limits(badge == null ? "free" : Svc.str(badge.get("level")));
        return Resp.ok(Resp.map(
            "plans", Member.plans(),
            "periods", java.util.Arrays.asList(
                Resp.map("months", 1, "label", "1 个月", "discount", ""),
                Resp.map("months", 3, "label", "3 个月", "discount", "约 9 折"),
                Resp.map("months", 12, "label", "12 个月", "discount", "约 8 折")
            ),
            "level_names", MemberSvc.NAMES,
            "badge", badge,
            "limits", limits,
            "usage", Resp.map("backtest_today", 0, "ai_today", 0),
            "payment", Resp.map(
                "configured", payConfigured(),
                "channels", java.util.Arrays.asList("alipay", "wxpay"),
                "channel_names", Resp.map("alipay", "支付宝", "wxpay", "微信支付")),
            "site", Resp.map("site_name", IosCtl.cfg("site_name", "Amore"), "register_enabled", 1)
        ));
    }

    @GetMapping("/status")
    public Object status(HttpServletRequest q) {
        long uid = uid(q);
        Map<String, Object> badge = MemberSvc.badgeOf(uid);
        String level = Svc.str(badge.get("level"));
        return Resp.ok(Resp.map(
            "badge", badge,
            "limits", Member.limits(level),
            "usage", Resp.map("backtest_today", 0, "ai_today", 0),
            "payment", Resp.map("configured", payConfigured(), "channels", java.util.Arrays.asList("alipay", "wxpay"),
                    "channel_names", Resp.map("alipay", "支付宝", "wxpay", "微信支付"))));
    }

    @GetMapping("/orders")
    public Object orders(HttpServletRequest q) {
        long uid = uid(q);
        var rows = Db.rows("SELECT * FROM member_orders WHERE user_id=? ORDER BY id DESC LIMIT 50", uid);
        var items = new ArrayList<Map<String, Object>>();
        for (var r : rows) items.add(Resp.map(
            "id", ((Number) r.get("id")).intValue(),
            "trade_no", Svc.str(r.get("trade_no")),
            "level", Svc.str(r.get("level")),
            "level_name", MemberSvc.name(Svc.str(r.get("level"))),
            "months", ((Number) r.get("months")).intValue(),
            "amount", Svc.str(r.get("amount")),
            "channel", "alipay", "channel_name", "支付宝",
            "status", Svc.str(r.get("status")),
            "pay_url", "",
            "paid_at", r.get("paid_at"),
            "created_at", Svc.str(r.get("created_at"))));
        return Resp.ok(Resp.map("items", items));
    }

    /**
     * 购买会员。body: { level, months, channel }
     * 已配置支付 → status=pending 并返回 pay_url（由后续支付回调置 paid 并开通）；
     * 未配置 → 演示模式直接开通（status=paid 立即生效）。
     */
    @PostMapping("/pay")
    public Object pay(@RequestBody Map<String, Object> body, HttpServletRequest q) {
        long uid = uid(q);
        String level = Svc.str(body.get("level"));
        int months = body.get("months") instanceof Number n ? n.intValue() : 1;
        String channel = Svc.str(body.getOrDefault("channel", "alipay"));
        if (!MemberSvc.LEVELS.contains(level) || "free".equals(level))
            return Resp.map("code", "INVALID_LEVEL", "message", "请选择要购买的会员等级", "data", null);
        if (months < 1 || months > 36)
            return Resp.map("code", "INVALID_MONTHS", "message", "购买时长需在 1~36 个月之间", "data", null);

        String tradeNo = "AM" + new java.text.SimpleDateFormat("yyyyMMddHHmmss").format(new Date()) + (int) (Math.random() * 9000 + 1000);
        double amount = MemberSvc.priceFor(level, months);
        boolean configured = payConfigured();
        if (!configured) {
            // 演示模式：直接开通
            Db.ins("INSERT INTO member_orders(user_id,trade_no,level,months,amount,status,created_at) VALUES(?,?,?,?,?, 'paid', NOW())",
                    uid, tradeNo, level, months, String.format("%.2f", amount));
            String expire = MemberSvc.upgrade(uid, level, months);
            ConsoleCtl.logChange(uid, "level", "-", level, "user", "ios");
            return Resp.ok("已直接开通（演示模式）", Resp.map(
                    "trade_no", tradeNo, "amount", String.format("%.2f", amount),
                    "pay_url", "", "expire_at", expire, "demo", true));
        }

        // 真实支付：建待支付订单，返回收银台地址（易支付对接见 PaymentSvc）
        Db.ins("INSERT INTO member_orders(user_id,trade_no,level,months,amount,status,channel,created_at) VALUES(?,?,?,?,?, 'pending',?, NOW())",
                uid, tradeNo, level, months, String.format("%.2f", amount), channel);
        String xff = q.getHeader("X-Forwarded-For");
        String clientIp = (xff == null || xff.isBlank()) ? q.getRemoteAddr() : xff.split(",")[0].trim();
        String payUrl = PaymentSvc.buildPayUrl(tradeNo, amount, channel, clientIp);
        if (payUrl == null) {
            // 配置不完整 → 回退演示开通，避免用户卡死
            Db.upd("UPDATE member_orders SET status='paid' WHERE trade_no=?", tradeNo);
            String expire = MemberSvc.upgrade(uid, level, months);
            return Resp.ok("支付通道未配置完整，已直接开通（演示模式）", Resp.map(
                    "trade_no", tradeNo, "amount", String.format("%.2f", amount),
                    "pay_url", "", "expire_at", expire, "demo", true));
        }
        return Resp.ok("订单已创建，请完成支付", Resp.map(
                "trade_no", tradeNo, "amount", String.format("%.2f", amount),
                "pay_url", payUrl, "status", "pending", "demo", false));
    }

    /** 支付回调（易支付异步通知）：验签 → 标记订单已支付 → 开通会员 */
    @PostMapping("/notify")
    public String notify(@RequestParam Map<String, String> params) {
        String tradeNo = params.get("out_trade_no");
        if (tradeNo == null || tradeNo.isBlank()) return "fail";
        if (!PaymentSvc.verifyNotify(params)) return "fail";
        Map<String, Object> o = Db.one("SELECT * FROM member_orders WHERE trade_no=?", tradeNo);
        if (o == null) return "fail";
        if (!"paid".equals(Svc.str(o.get("status")))) {
            Db.upd("UPDATE member_orders SET status='paid', paid_at=NOW() WHERE trade_no=?", tradeNo);
            long userId = ((Number) o.get("user_id")).longValue();
            int months = ((Number) o.get("months")).intValue();
            MemberSvc.upgrade(userId, Svc.str(o.get("level")), months);
        }
        return "success";
    }

    static boolean payConfigured() {
        return "1".equals(IosCtl.cfg("pay_enabled", "0")) && !IosCtl.cfg("pay_api_url", "").isBlank();
    }
}
