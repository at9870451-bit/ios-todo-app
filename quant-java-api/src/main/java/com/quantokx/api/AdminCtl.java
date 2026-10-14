package com.quantokx.api;

import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.util.*;

/**
 * iOS App 内「管理端」接口（/api/admin/**），认证沿用 App 的 QBSESSID 会话。
 * v2.0：全部改为真实数据读写（原为占位实现），响应形状保持不变，兼容 App 既有解码模型。
 */
@RestController
@RequestMapping("/api/admin")
public class AdminCtl {

    /** 仅管理员可访问 */
    private boolean guard(HttpServletRequest q, HttpServletResponse resp) {
        Long uid = (Long) q.getAttribute("uid");
        if (uid == null) return false;
        Map<String, Object> u = Db.one("SELECT role FROM users WHERE id=?", uid);
        if (u == null || !"admin".equals(Svc.str(u.get("role")))) {
            resp.setStatus(403);
            return false;
        }
        return true;
    }

    @GetMapping("/stats")
    public Object stats(HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        long orderTotal = num(Db.scalar("SELECT COUNT(*) FROM member_orders"));
        long paid = num(Db.scalar("SELECT COUNT(*) FROM member_orders WHERE status='paid'"));
        long pending = num(Db.scalar("SELECT COUNT(*) FROM member_orders WHERE status<>'paid'"));
        double income = money("SELECT COALESCE(SUM(CAST(amount AS DECIMAL(12,2))),0) FROM member_orders WHERE status='paid'");
        double incomeToday = money("SELECT COALESCE(SUM(CAST(amount AS DECIMAL(12,2))),0) FROM member_orders WHERE status='paid' AND created_at>=CURDATE()");
        return Resp.ok(Resp.map(
                "user_total", num(Db.scalar("SELECT COUNT(*) FROM users")),
                "user_today", num(Db.scalar("SELECT COUNT(*) FROM users WHERE created_at>=CURDATE()")),
                "order_total", orderTotal, "order_paid", paid, "order_pending", pending,
                "income_total", String.format("%.2f", income),
                "income_today", String.format("%.2f", incomeToday)));
    }

    @GetMapping("/users")
    public Object users(HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        List<Map<String, Object>> items = Db.rows("SELECT id,username,nickname,email,role,level AS membership_level,status,created_at,last_login_at " +
                "FROM users ORDER BY id DESC LIMIT 200");
        for (Map<String, Object> r : items) ConsoleCtl.normalizeUser(r);
        return Resp.ok(Resp.map("items", items, "total", num(Db.scalar("SELECT COUNT(*) FROM users")), "page", 1));
    }

    @GetMapping("/orders")
    public Object orders(HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        List<Map<String, Object>> items = Db.rows("SELECT o.id,o.user_id,o.trade_no,o.level,o.months,o.amount,o.status,o.created_at,u.username " +
                "FROM member_orders o LEFT JOIN users u ON u.id=o.user_id ORDER BY o.id DESC LIMIT 200");
        return Resp.ok(Resp.map("items", items, "total", num(Db.scalar("SELECT COUNT(*) FROM member_orders")), "page", 1));
    }

    @GetMapping("/plans")
    public Object plans(HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        return Resp.ok(Resp.map("plans", Member.plans()));
    }

    @PostMapping("/plans/save")
    public Object plansSave(@RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        for (String level : Member.LEVELS) {
            Object price = b.get(level + "_price_month");
            if (price != null) Db.upd("INSERT INTO sys_config(k,v,remark) VALUES(?,?,'套餐月价') ON DUPLICATE KEY UPDATE v=VALUES(v)",
                    "plan_" + level + "_month", Svc.str(price));
        }
        return Resp.ok("套餐已保存", null);
    }

    @GetMapping("/free-ai")
    public Object freeAi(HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        Map<String, Object> cfg = new LinkedHashMap<>();
        for (String k : new String[]{"free_ai_url", "free_ai_model", "free_ai_key"})
            cfg.put(k, IosCtl.cfg(k, ""));
        return Resp.ok(Resp.map("config", cfg, "configured", !Svc.str(cfg.get("free_ai_key")).isBlank()));
    }

    @PostMapping("/free-ai/save")
    public Object freeAiSave(@RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        for (String k : new String[]{"free_ai_url", "free_ai_model", "free_ai_key"}) {
            if (b.containsKey(k)) Db.upd("INSERT INTO sys_config(k,v,remark) VALUES(?,?,'免费AI') ON DUPLICATE KEY UPDATE v=VALUES(v)", k, Svc.str(b.get(k)));
        }
        return Resp.ok("免费 AI 配置已保存", null);
    }

    @GetMapping("/payment")
    public Object payment(HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        Map<String, Object> cfg = Resp.map(
                "api_url", IosCtl.cfg("pay_api_url", ""),
                "pid", IosCtl.cfg("pay_pid", ""),
                "key", IosCtl.cfg("pay_key", ""),
                "enabled", "1".equals(IosCtl.cfg("pay_enabled", "0")) ? 1 : 0,
                "demo_direct", "1".equals(IosCtl.cfg("pay_demo_direct", "1")) ? 1 : 0);
        return Resp.ok(Resp.map("config", cfg, "channels", new ArrayList<>(), "configured", !Svc.str(cfg.get("api_url")).isBlank()));
    }

    @PostMapping("/payment/save")
    public Object paymentSave(@RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        Map<String, String> map = Map.of("api_url", "pay_api_url", "pid", "pay_pid", "key", "pay_key", "enabled", "pay_enabled", "demo_direct", "pay_demo_direct");
        for (Map.Entry<String, String> e : map.entrySet()) {
            if (b.containsKey(e.getKey())) Db.upd("INSERT INTO sys_config(k,v,remark) VALUES(?,?,'支付') ON DUPLICATE KEY UPDATE v=VALUES(v)",
                    e.getValue(), Svc.str(b.get(e.getKey())));
        }
        return Resp.ok("支付配置已保存", null);
    }

    @GetMapping("/settings")
    public Object settings(HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        return Resp.ok(Resp.map("site", Resp.map(
                "register_enabled", "1".equals(IosCtl.cfg("register_enabled", "1")) ? 1 : 0,
                "register_need_email", "1".equals(IosCtl.cfg("register_need_email", "0")) ? 1 : 0,
                "site_name", IosCtl.cfg("site_name", "Amore"),
                "announcement", IosCtl.cfg("announcement", ""))));
    }

    @PostMapping("/settings/save")
    public Object settingsSave(@RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        Map<String, String> map = Map.of("register_enabled", "register_enabled", "register_need_email", "register_need_email",
                "site_name", "site_name", "announcement", "announcement");
        for (Map.Entry<String, String> e : map.entrySet()) {
            if (b.containsKey(e.getKey())) Db.upd("INSERT INTO sys_config(k,v,remark) VALUES(?,?,'站点设置') ON DUPLICATE KEY UPDATE v=VALUES(v)",
                    e.getValue(), Svc.str(b.get(e.getKey())));
        }
        return Resp.ok("设置已保存", null);
    }

    @PostMapping("/user/update")
    public Object userUpdate(@RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        long id = (long) Svc.num(b.get("id"), 0);
        Map<String, Object> u = Db.one("SELECT * FROM users WHERE id=?", id);
        if (u == null) {
            resp.setStatus(404);
            return Resp.map("code", "NOT_FOUND", "message", "用户不存在", "data", null);
        }
        String level = b.get("level") == null ? Svc.str(u.get("level")) : Svc.str(b.get("level"));
        String role = b.get("role") == null ? Svc.str(u.get("role")) : Svc.str(b.get("role"));
        int status = b.get("status") == null ? (int) num(u.get("status")) : (int) Svc.num(b.get("status"), 1);
        String nickname = b.get("nickname") == null ? Svc.str(u.get("nickname")) : Svc.str(b.get("nickname"));
        String email = b.get("email") == null ? Svc.str(u.get("email")) : Svc.str(b.get("email"));
        Db.upd("UPDATE users SET level=?, role=?, status=?, nickname=?, email=? WHERE id=?", level, role, status, nickname, email, id);
        if (!level.equals(Svc.str(u.get("level")))) ConsoleCtl.logChange(id, "level", Svc.str(u.get("level")), level, "admin", "ios-admin");
        if (status != (int) num(u.get("status"))) ConsoleCtl.logChange(id, "status", String.valueOf(num(u.get("status"))), String.valueOf(status), "admin", "ios-admin");
        return Resp.ok("用户已更新", null);
    }

    @PostMapping("/order/mark-paid")
    public Object markPaid(@RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) {
        if (!guard(q, resp)) return Resp.map("code", 403, "message", "无权限", "data", null);
        long id = (long) Svc.num(b.get("id"), 0);
        Map<String, Object> o = Db.one("SELECT * FROM member_orders WHERE id=?", id);
        if (o == null) {
            resp.setStatus(404);
            return Resp.map("code", "NOT_FOUND", "message", "订单不存在", "data", null);
        }
        Db.upd("UPDATE member_orders SET status='paid' WHERE id=?", id);
        return Resp.ok("订单已标记支付", null);
    }

    static long num(Object o) { return o instanceof Number n ? n.longValue() : 0; }

    static double money(String sql) {
        Object v = Db.scalar(sql);
        if (v instanceof Number n) return Math.round(n.doubleValue() * 100d) / 100d;
        try { return Math.round(Double.parseDouble(String.valueOf(v)) * 100d) / 100d; } catch (Exception e) { return 0; }
    }
}
