package com.quantokx.api;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseBody;
import jakarta.servlet.http.HttpServletResponse;
import java.util.*;

/**
 * 可视化数据面板：注册人数 / 会话 / 消息 / 会员 / 趋势图。
 * 独立于 /api/admin（App 管理端），用面板密钥登录（环境变量 PANEL_KEY，默认 amapanel2026）。
 * 页面与数据接口路径均不含 /api 前缀，App 拦截器不影响。
 */
@Controller
public class PanelCtl {

    static String panelKey() {
        String k = System.getenv("PANEL_KEY");
        return (k == null || k.isBlank()) ? "amapanel2026" : k;
    }

    static boolean authed(jakarta.servlet.http.HttpServletRequest q) {
        Object ok = q.getSession().getAttribute("panel_authed");
        return Boolean.TRUE.equals(ok);
    }

    /** 面板单页（内嵌 HTML/JS/CSS，无外部依赖） */
    @GetMapping({"/panel", "/panel.html"})
    public void pageHtml(HttpServletResponse r) throws Exception {
        r.setContentType("text/html; charset=utf-8");
        r.setHeader("Cache-Control", "no-store");
        try (var in = PanelCtl.class.getResourceAsStream("/panel.html")) {
            r.getOutputStream().write(in == null ? "<h1>panel missing</h1>".getBytes() : in.readAllBytes());
        }
    }

    @PostMapping("/panel/login")
    @ResponseBody
    public Object login(@RequestBody Map<String, Object> b, jakarta.servlet.http.HttpServletRequest q) {
        if (panelKey().equals(Svc.str(b.get("key")))) {
            q.getSession(true).setAttribute("panel_authed", true);
            return Resp.ok("登录成功", Resp.eo());
        }
        return Resp.map("code", "BAD_KEY", "message", "密钥错误", "data", null);
    }

    @PostMapping("/panel/logout")
    @ResponseBody
    public Object logout(jakarta.servlet.http.HttpServletRequest q) {
        var s = q.getSession(false);
        if (s != null) s.invalidate();
        return Resp.ok("已退出", Resp.eo());
    }

    @GetMapping("/panel/stats")
    @ResponseBody
    public Object stats(jakarta.servlet.http.HttpServletRequest q) {
        if (!authed(q)) return Resp.map("code", "UNAUTHORIZED", "message", "请先登录面板", "data", null);

        long users = num("SELECT COUNT(*) FROM users");
        long usersToday = 0; // users 表无 created_at 列，暂不提供当日新增
        long sessions = num("SELECT COUNT(*) FROM chat_sessions");
        long messages = num("SELECT COUNT(*) FROM chat_messages");
        long msgsToday = num("SELECT COUNT(*) FROM chat_messages WHERE date(created_at)=date('now','localtime')");
        long aiConfigs = num("SELECT COUNT(*) FROM ai_configs");
        long aiRunning = num("SELECT COUNT(*) FROM ai_configs WHERE running=1 AND enabled=1");
        long orders = num("SELECT COUNT(*) FROM member_orders");
        long ordersPaid = num("SELECT COUNT(*) FROM member_orders WHERE status='paid'");
        double income = money("SELECT COALESCE(SUM(CAST(amount AS REAL)),0) FROM member_orders WHERE status='paid'");
        long logs = num("SELECT COUNT(*) FROM system_logs");
        long strategies = num("SELECT COUNT(*) FROM strategies");

        // 近 7 天消息趋势（按天）
        var trend = new ArrayList<Map<String, Object>>();
        var rows = Db.rows("SELECT date(created_at) d, COUNT(*) c FROM chat_messages " +
                "WHERE created_at >= datetime('now','localtime','-6 days') GROUP BY date(created_at) ORDER BY d");
        Map<String, Object> byDay = new LinkedHashMap<>();
        for (var r : rows) byDay.put(Svc.str(r.get("d")), ((Number) r.get("c")).longValue());
        for (int i = 6; i >= 0; i--) {
            String d = new java.text.SimpleDateFormat("yyyy-MM-dd").format(new Date(System.currentTimeMillis() - i * 86400000L));
            trend.add(Resp.map("date", d.substring(5), "count", byDay.getOrDefault(d, 0L)));
        }

        // 用户列表（最近 50 个）
        var users = Db.rows("SELECT id, username, role, level, live_trading FROM users ORDER BY id DESC LIMIT 50");

        // 最近会话
        var sessionsList = Db.rows("SELECT s.id, s.title, s.updated_at, u.username, " +
                "(SELECT COUNT(*) FROM chat_messages m WHERE m.session_id=s.id) AS msgs " +
                "FROM chat_sessions s LEFT JOIN users u ON u.id=s.user_id ORDER BY s.updated_at DESC LIMIT 20");

        return Resp.ok(Resp.map(
                "user_total", users, "user_today", usersToday,
                "sessions", sessions, "messages", messages, "msgs_today", msgsToday,
                "ai_configs", aiConfigs, "ai_running", aiRunning,
                "orders", orders, "orders_paid", ordersPaid,
                "income_total", String.format("%.2f", income),
                "logs", logs, "strategies", strategies,
                "trend", trend, "users", users, "sessions_list", sessionsList
        ));
    }

    static long num(String sql) {
        Object v = Db.sc(sql);
        return v instanceof Number n ? n.longValue() : 0;
    }

    static double money(String sql) {
        Object v = Db.sc(sql);
        if (v instanceof Number n) return n.doubleValue();
        try { return Double.parseDouble(String.valueOf(v)); } catch (Exception e) { return 0; }
    }

    static long count(String sql) { return num(sql); }
}
