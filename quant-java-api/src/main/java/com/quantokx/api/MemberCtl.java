package com.quantokx.api;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;

@RestController
@RequestMapping("/api/member")
public class MemberCtl {
    Long uid(HttpServletRequest q) { return (Long) q.getAttribute("uid"); }

    @GetMapping("/plans")
    public Object plans() {
        return Resp.ok(Resp.map("plans", Member.plans(), "periods", java.util.Arrays.asList(
            Resp.map("months", 1, "label", "1 个月", "discount", ""),
            Resp.map("months", 3, "label", "3 个月", "discount", "约 9 折"),
            Resp.map("months", 12, "label", "12 个月", "discount", "约 8.3 折")
        ), "level_names", MemberSvc.NAMES, "site", Resp.map("site_name", "QuantOKX", "register_enabled", 1), "usage", Resp.map("backtest_today", 0, "ai_today", 0)));
    }

    @GetMapping("/status")
    public Object status(HttpServletRequest q) {
        long uid = uid(q);
        var u = Db.one("SELECT level FROM users WHERE id=?", uid);
        String level = u == null ? "free" : Svc.str(u.get("level"));
        return Resp.ok(Resp.map("badge", Resp.map("level", level, "name", MemberSvc.name(level), "is_admin", "ultimate".equals(level), "expire_at", null, "days_left", null, "auto_renew", false), "limits", Resp.map("level", level, "name", MemberSvc.name(level)), "usage", Resp.map("backtest_today", 0, "ai_today", 0)));
    }

    @GetMapping("/orders")
    public Object orders(HttpServletRequest q) {
        long uid = uid(q);
        var rows = Db.rows("SELECT * FROM member_orders WHERE user_id=? ORDER BY id DESC LIMIT 50", uid);
        var items = new ArrayList<Map<String, Object>>();
        for (var r : rows) items.add(Resp.map("id", ((Number) r.get("id")).intValue(), "trade_no", Svc.str(r.get("trade_no")), "level", Svc.str(r.get("level")), "level_name", MemberSvc.name(Svc.str(r.get("level"))), "months", ((Number) r.get("months")).intValue(), "amount", Svc.str(r.get("amount")), "channel", "alipay", "channel_name", "支付宝", "status", Svc.str(r.get("status")), "pay_url", "", "paid_at", null, "created_at", Svc.str(r.get("created_at"))));
        return Resp.ok(Resp.map("items", items));
    }

    @PostMapping("/pay")
    public Object pay(@RequestBody Map<String, Object> body, HttpServletRequest q) {
        long uid = uid(q);
        String level = Svc.str(body.get("level"));
        int months = body.get("months") instanceof Number n ? n.intValue() : 1;
        if (!MemberSvc.LEVELS.contains(level) || "free".equals(level)) return Resp.map("code", "INVALID_LEVEL", "message", "请选择要购买的会员等级", "data", null);
        String tradeNo = "QB" + new java.text.SimpleDateFormat("yyyyMMddHHmmss").format(new Date()) + (int)(Math.random() * 9000 + 1000);
        double amount = MemberSvc.priceFor(level, months);
        Db.ins("INSERT INTO member_orders(user_id,trade_no,level,months,amount,status) VALUES(?,?,?,?,?, 'paid')", uid, tradeNo, level, months, String.format("%.2f", amount));
        MemberSvc.upgrade(uid, level, months);
        return Resp.ok("已直接开通（演示模式）", Resp.map("trade_no", tradeNo, "amount", String.format("%.2f", amount), "pay_url", ""));
    }
}
