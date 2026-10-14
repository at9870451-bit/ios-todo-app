package com.quantokx.api;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * Web 管理后台 API（/api/console/**）。JWT 认证，权限码校验，操作日志由拦截器统一记录。
 * 全部数据来自 MySQL 真实业务表，无静态假数据。
 */
@RestController
@RequestMapping("/api/console")
public class ConsoleCtl {

    private static final DateTimeFormatter DF = DateTimeFormatter.ofPattern("yyyy-MM-dd");
    private static final Set<String> CONFIG_KEYS = Set.of(
            "register_enabled", "register_need_email", "site_name", "announcement",
            "app_version", "min_version", "maintain_mode",
            "pay_api_url", "pay_pid", "pay_key", "pay_enabled");

    // ============================ 认证 ============================

    @PostMapping("/auth/login")
    public Object login(@RequestBody Map<String, Object> b, HttpServletRequest req, HttpServletResponse resp) {
        String username = Svc.str(b.get("username")).trim();
        String password = Svc.str(b.get("password"));
        String ip = QkApiApplication.ip(req);
        if (username.isEmpty() || password.isEmpty()) return err(resp, 422, "请输入用户名和密码");

        String rlKey = "qb:loginfail:" + ip;
        String cnt = Rds.get(rlKey);
        if (cnt != null && Long.parseLong(cnt) >= 10) return err(resp, 429, "失败次数过多，请 10 分钟后再试");

        Map<String, Object> a = Db.one("SELECT a.*, r.code AS role_code, r.name AS role_name, r.perms FROM sys_admin a " +
                "LEFT JOIN sys_role r ON r.id=a.role_id WHERE a.username=?", username);
        if (a == null || !org.mindrot.jbcrypt.BCrypt.checkpw(password, Svc.str(a.get("password_hash")))) {
            Rds.incr(rlKey, 600);
            return err(resp, 401, "用户名或密码错误");
        }
        if (num(a.get("status")) != 1) return err(resp, 403, "账号已被禁用");

        long id = num(a.get("id"));
        String jti = Sess.newToken();
        String token = JwtUtil.issue(id, username, jti);
        Rds.set("qb:admintoken:" + jti, String.valueOf(id), JwtUtil.TTL_SECONDS);
        Db.upd("UPDATE sys_admin SET last_login_at=NOW(), last_login_ip=? WHERE id=?", ip, id);
        try {
            Db.upd("INSERT INTO sys_operation_log(admin_id,admin_name,action,method,path,params,ip,status) VALUES(?,?,?,?,?,?,?,?)",
                    id, username, "管理员登录", "POST", "/api/console/auth/login", null, ip, 200);
        } catch (Exception ignore) {}

        Map<String, Object> admin = adminView(a);
        admin.put("token", token);
        admin.put("expires_in", JwtUtil.TTL_SECONDS);
        return Resp.ok("登录成功", admin);
    }

    @GetMapping("/auth/me")
    public Object me(HttpServletRequest q) {
        var ctx = (QkApiApplication.ConsoleAuth) q.getAttribute("console");
        Map<String, Object> a = Db.one("SELECT a.*, r.code AS role_code, r.name AS role_name, r.perms FROM sys_admin a " +
                "LEFT JOIN sys_role r ON r.id=a.role_id WHERE a.id=?", ctx.id());
        return Resp.ok(adminView(a));
    }

    @PostMapping("/auth/logout")
    public Object logout(HttpServletRequest q) {
        String auth = q.getHeader("Authorization");
        if (auth != null && auth.startsWith("Bearer ")) {
            var cl = JwtUtil.parse(auth.substring(7).trim());
            if (cl != null && cl.getId() != null) Rds.del("qb:admintoken:" + cl.getId());
        }
        return Resp.ok("已退出登录", null);
    }

    @PostMapping("/auth/password")
    public Object changePassword(@RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) {
        var ctx = (QkApiApplication.ConsoleAuth) q.getAttribute("console");
        String oldPw = Svc.str(b.get("old_password"));
        String newPw = Svc.str(b.get("new_password"));
        if (newPw.length() < 8) return err(resp, 422, "新密码至少 8 位");
        Map<String, Object> a = Db.one("SELECT password_hash FROM sys_admin WHERE id=?", ctx.id());
        if (a == null || !org.mindrot.jbcrypt.BCrypt.checkpw(oldPw, Svc.str(a.get("password_hash"))))
            return err(resp, 422, "原密码不正确");
        Db.upd("UPDATE sys_admin SET password_hash=? WHERE id=?",
                org.mindrot.jbcrypt.BCrypt.hashpw(newPw, org.mindrot.jbcrypt.BCrypt.gensalt(10)), ctx.id());
        return Resp.ok("密码已修改", null);
    }

    static Map<String, Object> adminView(Map<String, Object> a) {
        List<String> perms = parsePerms(Svc.str(a.get("perms")));
        Map<String, Object> m = Resp.map(
                "id", num(a.get("id")),
                "username", Svc.str(a.get("username")),
                "nickname", Svc.str(a.get("nickname")),
                "role_id", num(a.get("role_id")),
                "role_code", Svc.str(a.get("role_code")),
                "role_name", Svc.str(a.get("role_name")),
                "status", num(a.get("status")),
                "perms", perms,
                "last_login_at", a.get("last_login_at"),
                "last_login_ip", a.get("last_login_ip"),
                "created_at", a.get("created_at"));
        return m;
    }

    // ============================ 用户管理 ============================

    @GetMapping("/users")
    public Object users(@RequestParam(defaultValue = "1") int page,
                        @RequestParam(defaultValue = "20") int size,
                        @RequestParam(required = false) String keyword,
                        @RequestParam(required = false) String status,
                        @RequestParam(required = false) String level,
                        @RequestParam(required = false) String date_from,
                        @RequestParam(required = false) String date_to,
                        @RequestParam(required = false, defaultValue = "created_at") String order,
                        @RequestParam(required = false, defaultValue = "desc") String dir) {
        StringBuilder w = new StringBuilder(" WHERE 1=1");
        List<Object> args = new ArrayList<>();
        if (keyword != null && !keyword.isBlank()) {
            w.append(" AND (username LIKE ? OR email LIKE ? OR nickname LIKE ? OR id=?)");
            String k = "%" + keyword.trim() + "%";
            args.add(k); args.add(k); args.add(k);
            args.add(parseLong(keyword.trim()));
        }
        if ("1".equals(status)) w.append(" AND status=1");
        if ("0".equals(status)) w.append(" AND status=0");
        if (level != null && !level.isBlank()) { w.append(" AND level=?"); args.add(level); }
        if (date_from != null && !date_from.isBlank()) { w.append(" AND created_at>=?"); args.add(date_from + " 00:00:00"); }
        if (date_to != null && !date_to.isBlank()) { w.append(" AND created_at<=?"); args.add(date_to + " 23:59:59"); }

        long total = num(Db.scalar("SELECT COUNT(*) FROM users" + w, args.toArray()));
        List<Object> pageArgs = new ArrayList<>(args);
        pageArgs.add(size);
        pageArgs.add((page - 1) * size);
        String col = switch (order == null ? "" : order) {
            case "id" -> "id"; case "last_login_at" -> "last_login_at"; default -> "created_at";
        };
        String d = "asc".equalsIgnoreCase(dir) ? "ASC" : "DESC";
        List<Map<String, Object>> rows = Db.rows("SELECT id,username,nickname,email,role,level,status,created_at,last_login_at,last_login_ip,register_ip,live_trading " +
                "FROM users" + w + " ORDER BY " + col + " " + d + ", id " + d + " LIMIT ? OFFSET ?", pageArgs.toArray());
        for (Map<String, Object> r : rows) normalizeUser(r);
        return Resp.ok(Resp.map("total", total, "page", page, "size", size, "items", rows));
    }

    @GetMapping("/users/{id}")
    public Object userDetail(@PathVariable long id, HttpServletResponse resp) {
        Map<String, Object> u = Db.one("SELECT * FROM users WHERE id=?", id);
        if (u == null) return err(resp, 404, "用户不存在");
        u.remove("pass_hash");
        normalizeUser(u);
        Map<String, Object> stats = Resp.map(
                "sessions", num(Db.scalar("SELECT COUNT(*) FROM chat_sessions WHERE user_id=?", id)),
                "messages", num(Db.scalar("SELECT COUNT(*) FROM chat_messages WHERE session_id IN (SELECT id FROM chat_sessions WHERE user_id=?)", id)),
                "ai_configs", num(Db.scalar("SELECT COUNT(*) FROM ai_configs WHERE user_id=?", id)),
                "strategies", num(Db.scalar("SELECT COUNT(*) FROM strategies WHERE user_id=?", id)),
                "orders", num(Db.scalar("SELECT COUNT(*) FROM orders WHERE user_id=?", id)));
        return Resp.ok(Resp.map("user", u, "stats", stats));
    }

    @GetMapping("/users/{id}/logins")
    public Object userLogins(@PathVariable long id,
                             @RequestParam(defaultValue = "1") int page,
                             @RequestParam(defaultValue = "20") int size) {
        long total = num(Db.scalar("SELECT COUNT(*) FROM app_user_login_log WHERE user_id=?", id));
        List<Map<String, Object>> rows = Db.rows("SELECT * FROM app_user_login_log WHERE user_id=? ORDER BY id DESC LIMIT ? OFFSET ?",
                id, size, (page - 1) * size);
        return Resp.ok(Resp.map("total", total, "page", page, "size", size, "items", rows));
    }

    @GetMapping("/users/{id}/devices")
    public Object userDevices(@PathVariable long id) {
        return Resp.ok(Resp.map("items", Db.rows("SELECT * FROM app_user_device WHERE user_id=? ORDER BY last_seen_at DESC", id)));
    }

    @GetMapping("/users/{id}/changes")
    public Object userChanges(@PathVariable long id,
                              @RequestParam(defaultValue = "1") int page,
                              @RequestParam(defaultValue = "20") int size) {
        long total = num(Db.scalar("SELECT COUNT(*) FROM app_user_change_log WHERE user_id=?", id));
        List<Map<String, Object>> rows = Db.rows("SELECT * FROM app_user_change_log WHERE user_id=? ORDER BY id DESC LIMIT ? OFFSET ?",
                id, size, (page - 1) * size);
        return Resp.ok(Resp.map("total", total, "page", page, "size", size, "items", rows));
    }

    @PostMapping("/users/{id}/ban")
    public Object ban(@PathVariable long id, @RequestBody(required = false) Map<String, Object> b,
                      HttpServletRequest q, HttpServletResponse resp) {
        Map<String, Object> u = Db.one("SELECT id,username FROM users WHERE id=?", id);
        if (u == null) return err(resp, 404, "用户不存在");
        String reason = b == null ? "" : Svc.str(b.get("reason"));
        int days = b == null ? 0 : (int) Svc.num(b.get("days"), 0);
        String until = null;
        if (days > 0) {
            until = java.time.LocalDateTime.now().plusDays(days).format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        }
        Db.upd("UPDATE users SET status=0, ban_reason=?, ban_until=? WHERE id=?", reason, until, id);
        logChange(id, "status", "1", "0", operator(q), "console");
        return Resp.ok("已封禁用户 " + Svc.str(u.get("username")), null);
    }

    @PostMapping("/users/{id}/unban")
    public Object unban(@PathVariable long id, HttpServletRequest q, HttpServletResponse resp) {
        Map<String, Object> u = Db.one("SELECT id,username FROM users WHERE id=?", id);
        if (u == null) return err(resp, 404, "用户不存在");
        Db.upd("UPDATE users SET status=1, ban_reason=NULL, ban_until=NULL WHERE id=?", id);
        logChange(id, "status", "0", "1", operator(q), "console");
        return Resp.ok("已解封用户 " + Svc.str(u.get("username")), null);
    }

    @PostMapping("/users/{id}/reset-password")
    public Object resetUserPassword(@PathVariable long id, @RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) {
        String pw = Svc.str(b.get("new_password"));
        if (pw.length() < 8) return err(resp, 422, "新密码至少 8 位");
        if (Db.one("SELECT id FROM users WHERE id=?", id) == null) return err(resp, 404, "用户不存在");
        Db.upd("UPDATE users SET pass_hash=? WHERE id=?", Sess.BC.hash(pw), id);
        logChange(id, "password", "******", "******", operator(q), "console");
        return Resp.ok("密码已重置", null);
    }

    // ============================ 统计 ============================

    @GetMapping("/stats/overview")
    public Object overview() {
        return Resp.ok(Resp.map(
                "user_total", num(Db.scalar("SELECT COUNT(*) FROM users")),
                "user_today", num(Db.scalar("SELECT COUNT(*) FROM users WHERE created_at>=CURDATE()")),
                "user_yesterday", num(Db.scalar("SELECT COUNT(*) FROM users WHERE created_at>=CURDATE()-INTERVAL 1 DAY AND created_at<CURDATE()")),
                "user_week", num(Db.scalar("SELECT COUNT(*) FROM users WHERE created_at>=CURDATE()-INTERVAL 6 DAY")),
                "user_month", num(Db.scalar("SELECT COUNT(*) FROM users WHERE created_at>=CURDATE()-INTERVAL 29 DAY")),
                "active_today", num(Db.scalar("SELECT COUNT(DISTINCT user_id) FROM app_user_login_log WHERE success=1 AND created_at>=CURDATE()")),
                "active_week", num(Db.scalar("SELECT COUNT(DISTINCT user_id) FROM app_user_login_log WHERE success=1 AND created_at>=CURDATE()-INTERVAL 6 DAY")),
                "active_month", num(Db.scalar("SELECT COUNT(DISTINCT user_id) FROM app_user_login_log WHERE success=1 AND created_at>=CURDATE()-INTERVAL 29 DAY")),
                "session_total", num(Db.scalar("SELECT COUNT(*) FROM chat_sessions")),
                "message_total", num(Db.scalar("SELECT COUNT(*) FROM chat_messages")),
                "order_total", num(Db.scalar("SELECT COUNT(*) FROM member_orders")),
                "order_paid", num(Db.scalar("SELECT COUNT(*) FROM member_orders WHERE status='paid'")),
                "income_total", money("SELECT COALESCE(SUM(CAST(amount AS DECIMAL(12,2))),0) FROM member_orders WHERE status='paid'")));
    }

    @GetMapping("/stats/trend")
    public Object trend(@RequestParam(defaultValue = "30") int days) {
        if (days < 1) days = 1;
        if (days > 180) days = 180;
        LocalDate from = LocalDate.now().minusDays(days - 1L);
        Map<String, Long> reg = byDay("SELECT DATE(created_at) d, COUNT(*) c FROM users WHERE created_at>=? GROUP BY DATE(created_at)", from.toString());
        Map<String, Long> act = byDay("SELECT DATE(created_at) d, COUNT(DISTINCT user_id) c FROM app_user_login_log WHERE success=1 AND created_at>=? GROUP BY DATE(created_at)", from.toString());
        List<Map<String, Object>> items = new ArrayList<>();
        for (int i = 0; i < days; i++) {
            String d = from.plusDays(i).format(DF);
            items.add(Resp.map("date", d, "registers", reg.getOrDefault(d, 0L), "actives", act.getOrDefault(d, 0L)));
        }
        return Resp.ok(Resp.map("days", days, "items", items));
    }

    @GetMapping("/stats/retention")
    public Object retention(@RequestParam(defaultValue = "7") int days) {
        if (days < 2) days = 2;
        if (days > 30) days = 30;
        LocalDate from = LocalDate.now().minusDays(days - 1L);
        // cohort 注册用户 + 各自登录日期
        List<Map<String, Object>> rows = Db.rows(
                "SELECT u.id uid, DATE(u.created_at) cd, DATE(l.created_at) ld FROM users u " +
                "LEFT JOIN app_user_login_log l ON l.user_id=u.id AND l.success=1 " +
                "WHERE u.created_at>=? LIMIT 50000", from.toString() + " 00:00:00");
        Map<String, Map<Long, Set<String>>> cohorts = new LinkedHashMap<>();
        for (Map<String, Object> r : rows) {
            String cd = Svc.str(r.get("cd"));
            if (cd.isEmpty()) continue;
            Map<Long, Set<String>> m = cohorts.computeIfAbsent(cd, k -> new LinkedHashMap<>());
            long uid = num(r.get("uid"));
            m.computeIfAbsent(uid, k -> new HashSet<>());
            String ld = Svc.str(r.get("ld"));
            if (!ld.isEmpty()) m.get(uid).add(ld);
        }
        List<Map<String, Object>> out = new ArrayList<>();
        for (int i = 0; i < days; i++) {
            String cd = from.plusDays(i).format(DF);
            Map<Long, Set<String>> m = cohorts.get(cd);
            if (m == null || m.isEmpty()) {
                out.add(Resp.map("date", cd, "registered", 0, "retained", retentionEmpty(days)));
                continue;
            }
            List<Map<String, Object>> retained = new ArrayList<>();
            for (int d = 0; d < days; d++) {
                String target = LocalDate.parse(cd).plusDays(d).format(DF);
                long cnt = 0;
                for (Set<String> days2 : m.values()) if (days2.contains(target)) cnt++;
                double rate = Math.round((double) cnt / m.size() * 10000d) / 10000d;
                retained.add(Resp.map("day", d, "count", cnt, "rate", rate));
            }
            out.add(Resp.map("date", cd, "registered", m.size(), "retained", retained));
        }
        return Resp.ok(Resp.map("days", days, "cohorts", out));
    }

    private static List<Map<String, Object>> retentionEmpty(int days) {
        List<Map<String, Object>> l = new ArrayList<>();
        for (int d = 0; d < days; d++) l.add(Resp.map("day", d, "count", 0, "rate", 0));
        return l;
    }

    private static Map<String, Long> byDay(String sql, String arg) {
        Map<String, Long> m = new LinkedHashMap<>();
        for (Map<String, Object> r : Db.rows(sql, arg)) m.put(Svc.str(r.get("d")), num(r.get("c")));
        return m;
    }

    // ============================ 管理员与角色 ============================

    @GetMapping("/admins")
    public Object admins() {
        List<Map<String, Object>> rows = Db.rows("SELECT a.id,a.username,a.nickname,a.role_id,a.status,a.last_login_at,a.last_login_ip,a.created_at," +
                "r.name AS role_name, r.code AS role_code FROM sys_admin a LEFT JOIN sys_role r ON r.id=a.role_id ORDER BY a.id");
        return Resp.ok(Resp.map("items", rows));
    }

    @PostMapping("/admins")
    public Object adminCreate(@RequestBody Map<String, Object> b, HttpServletResponse resp) {
        String username = Svc.str(b.get("username")).trim();
        String password = Svc.str(b.get("password"));
        if (!username.matches("[A-Za-z0-9_@.-]{3,32}")) return err(resp, 422, "用户名需为 3~32 位字母、数字、下划线、点、短横线或 @");
        if (password.length() < 8) return err(resp, 422, "密码至少 8 位");
        if (Db.one("SELECT id FROM sys_admin WHERE username=?", username) != null) return err(resp, 422, "用户名已存在");
        long roleId = (long) Svc.num(b.get("role_id"), 2);
        if (Db.one("SELECT id FROM sys_role WHERE id=?", roleId) == null) return err(resp, 422, "角色不存在");
        long id = Db.insert("INSERT INTO sys_admin(username,password_hash,nickname,role_id,status) VALUES(?,?,?,?,1)",
                username, org.mindrot.jbcrypt.BCrypt.hashpw(password, org.mindrot.jbcrypt.BCrypt.gensalt(10)),
                Svc.str(b.getOrDefault("nickname", username)), roleId);
        return Resp.ok("管理员已创建", Resp.map("id", id));
    }

    @PutMapping("/admins/{id}")
    public Object adminUpdate(@PathVariable long id, @RequestBody Map<String, Object> b, HttpServletResponse resp) {
        Map<String, Object> a = Db.one("SELECT * FROM sys_admin WHERE id=?", id);
        if (a == null) return err(resp, 404, "管理员不存在");
        Long roleId = b.get("role_id") == null ? null : (long) Svc.num(b.get("role_id"), 0);
        if (roleId != null && Db.one("SELECT id FROM sys_role WHERE id=?", roleId) == null) return err(resp, 422, "角色不存在");
        int status = b.get("status") == null ? (int) num(a.get("status")) : (int) Svc.num(b.get("status"), 1);
        if (id == 1 && status != 1) return err(resp, 422, "内置超级管理员不可禁用");
        Db.upd("UPDATE sys_admin SET nickname=?, role_id=?, status=? WHERE id=?",
                b.get("nickname") == null ? Svc.str(a.get("nickname")) : Svc.str(b.get("nickname")),
                roleId == null ? num(a.get("role_id")) : roleId, status, id);
        return Resp.ok("已保存", null);
    }

    @PostMapping("/admins/{id}/reset-password")
    public Object adminResetPassword(@PathVariable long id, @RequestBody Map<String, Object> b, HttpServletResponse resp) {
        String pw = Svc.str(b.get("new_password"));
        if (pw.length() < 8) return err(resp, 422, "新密码至少 8 位");
        if (Db.one("SELECT id FROM sys_admin WHERE id=?", id) == null) return err(resp, 404, "管理员不存在");
        Db.upd("UPDATE sys_admin SET password_hash=? WHERE id=?",
                org.mindrot.jbcrypt.BCrypt.hashpw(pw, org.mindrot.jbcrypt.BCrypt.gensalt(10)), id);
        return Resp.ok("密码已重置", null);
    }

    @DeleteMapping("/admins/{id}")
    public Object adminDelete(@PathVariable long id, HttpServletRequest q, HttpServletResponse resp) {
        var ctx = (QkApiApplication.ConsoleAuth) q.getAttribute("console");
        if (id == 1) return err(resp, 422, "内置超级管理员不可删除");
        if (id == ctx.id()) return err(resp, 422, "不能删除当前登录账号");
        if (Db.one("SELECT id FROM sys_admin WHERE id=?", id) == null) return err(resp, 404, "管理员不存在");
        Db.upd("DELETE FROM sys_admin WHERE id=?", id);
        return Resp.ok("已删除", null);
    }

    @GetMapping("/roles")
    public Object roles() {
        List<Map<String, Object>> rows = Db.rows("SELECT r.id,r.name,r.code,r.perms,r.remark,r.created_at," +
                "(SELECT COUNT(*) FROM sys_admin a WHERE a.role_id=r.id) AS admin_count FROM sys_role r ORDER BY r.id");
        for (Map<String, Object> r : rows) r.put("perms", parsePerms(Svc.str(r.get("perms"))));
        return Resp.ok(Resp.map("items", rows));
    }

    @PostMapping("/roles")
    public Object roleCreate(@RequestBody Map<String, Object> b, HttpServletResponse resp) {
        String name = Svc.str(b.get("name")).trim();
        String code = Svc.str(b.get("code")).trim();
        if (name.isEmpty() || code.isEmpty()) return err(resp, 422, "角色名称与编码必填");
        if (Db.one("SELECT id FROM sys_role WHERE code=?", code) != null) return err(resp, 422, "角色编码已存在");
        long id = Db.insert("INSERT INTO sys_role(name,code,perms,remark) VALUES(?,?,?,?)",
                name, code, permsJson(b.get("perms")), Svc.str(b.get("remark")));
        return Resp.ok("角色已创建", Resp.map("id", id));
    }

    @PutMapping("/roles/{id}")
    public Object roleUpdate(@PathVariable long id, @RequestBody Map<String, Object> b, HttpServletResponse resp) {
        Map<String, Object> r = Db.one("SELECT * FROM sys_role WHERE id=?", id);
        if (r == null) return err(resp, 404, "角色不存在");
        if (id == 1) return err(resp, 422, "内置超级管理员角色不可修改");
        Db.upd("UPDATE sys_role SET name=?, perms=?, remark=? WHERE id=?",
                b.get("name") == null ? Svc.str(r.get("name")) : Svc.str(b.get("name")),
                b.get("perms") == null ? Svc.str(r.get("perms")) : permsJson(b.get("perms")),
                b.get("remark") == null ? Svc.str(r.get("remark")) : Svc.str(b.get("remark")), id);
        return Resp.ok("已保存", null);
    }

    @DeleteMapping("/roles/{id}")
    public Object roleDelete(@PathVariable long id, HttpServletResponse resp) {
        if (id == 1) return err(resp, 422, "内置超级管理员角色不可删除");
        if (Db.one("SELECT id FROM sys_role WHERE id=?", id) == null) return err(resp, 404, "角色不存在");
        if (num(Db.scalar("SELECT COUNT(*) FROM sys_admin WHERE role_id=?", id)) > 0)
            return err(resp, 422, "该角色下仍有管理员，无法删除");
        Db.upd("DELETE FROM sys_role WHERE id=?", id);
        return Resp.ok("已删除", null);
    }

    // ============================ 操作日志 ============================

    @GetMapping("/logs")
    public Object logs(@RequestParam(defaultValue = "1") int page,
                       @RequestParam(defaultValue = "20") int size,
                       @RequestParam(required = false) String keyword,
                       @RequestParam(required = false) Long admin_id,
                       @RequestParam(required = false) String date_from,
                       @RequestParam(required = false) String date_to) {
        StringBuilder w = new StringBuilder(" WHERE 1=1");
        List<Object> args = new ArrayList<>();
        if (keyword != null && !keyword.isBlank()) {
            w.append(" AND (action LIKE ? OR path LIKE ? OR admin_name LIKE ? OR ip LIKE ?)");
            String k = "%" + keyword.trim() + "%";
            args.add(k); args.add(k); args.add(k); args.add(k);
        }
        if (admin_id != null) { w.append(" AND admin_id=?"); args.add(admin_id); }
        if (date_from != null && !date_from.isBlank()) { w.append(" AND created_at>=?"); args.add(date_from + " 00:00:00"); }
        if (date_to != null && !date_to.isBlank()) { w.append(" AND created_at<=?"); args.add(date_to + " 23:59:59"); }
        long total = num(Db.scalar("SELECT COUNT(*) FROM sys_operation_log" + w, args.toArray()));
        List<Object> pa = new ArrayList<>(args);
        pa.add(size); pa.add((page - 1) * size);
        List<Map<String, Object>> rows = Db.rows("SELECT * FROM sys_operation_log" + w + " ORDER BY id DESC LIMIT ? OFFSET ?", pa.toArray());
        return Resp.ok(Resp.map("total", total, "page", page, "size", size, "items", rows));
    }

    // ============================ 系统配置 ============================

    @GetMapping("/config")
    public Object config() {
        Map<String, Object> m = new LinkedHashMap<>();
        for (String k : CONFIG_KEYS) m.put(k, "");
        for (Map<String, Object> r : Db.rows("SELECT k,v FROM sys_config")) {
            if (CONFIG_KEYS.contains(Svc.str(r.get("k")))) m.put(Svc.str(r.get("k")), Svc.str(r.get("v")));
        }
        return Resp.ok(m);
    }

    @PutMapping("/config")
    public Object configSave(@RequestBody Map<String, Object> b) {
        int n = 0;
        for (Map.Entry<String, Object> e : b.entrySet()) {
            if (!CONFIG_KEYS.contains(e.getKey())) continue;
            String v = e.getValue() == null ? "" : String.valueOf(e.getValue());
            Db.upd("INSERT INTO sys_config(k,v) VALUES(?,?) ON DUPLICATE KEY UPDATE v=VALUES(v)", e.getKey(), v);
            n++;
        }
        return Resp.ok("已保存 " + n + " 项配置", null);
    }

    // ============================ 公告 ============================

    @GetMapping("/announcements")
    public Object announcements() {
        return Resp.ok(Resp.map("items", Db.rows("SELECT * FROM app_announcement ORDER BY id DESC")));
    }

    @PostMapping("/announcements")
    public Object announcementCreate(@RequestBody Map<String, Object> b, HttpServletResponse resp) {
        String title = Svc.str(b.get("title")).trim();
        if (title.isEmpty()) return err(resp, 422, "公告标题必填");
        long id = Db.insert("INSERT INTO app_announcement(title,content,type,enabled,start_at,end_at) VALUES(?,?,?,?,?,?)",
                title, Svc.str(b.get("content")), Svc.str(b.getOrDefault("type", "notice")),
                (int) Svc.num(b.get("enabled"), 1), blankToNull(b.get("start_at")), blankToNull(b.get("end_at")));
        return Resp.ok("公告已创建", Resp.map("id", id));
    }

    @PutMapping("/announcements/{id}")
    public Object announcementUpdate(@PathVariable long id, @RequestBody Map<String, Object> b, HttpServletResponse resp) {
        if (Db.one("SELECT id FROM app_announcement WHERE id=?", id) == null) return err(resp, 404, "公告不存在");
        Db.upd("UPDATE app_announcement SET title=?,content=?,type=?,enabled=?,start_at=?,end_at=? WHERE id=?",
                Svc.str(b.get("title")), Svc.str(b.get("content")), Svc.str(b.getOrDefault("type", "notice")),
                (int) Svc.num(b.get("enabled"), 1), blankToNull(b.get("start_at")), blankToNull(b.get("end_at")), id);
        return Resp.ok("已保存", null);
    }

    @DeleteMapping("/announcements/{id}")
    public Object announcementDelete(@PathVariable long id) {
        Db.upd("DELETE FROM app_announcement WHERE id=?", id);
        return Resp.ok("已删除", null);
    }

    // ============================ 版本 ============================

    @GetMapping("/versions")
    public Object versions() {
        return Resp.ok(Resp.map("items", Db.rows("SELECT * FROM app_version ORDER BY id DESC")));
    }

    @PostMapping("/versions")
    public Object versionCreate(@RequestBody Map<String, Object> b, HttpServletResponse resp) {
        String v = Svc.str(b.get("version")).trim();
        if (v.isEmpty()) return err(resp, 422, "版本号必填");
        long id = Db.insert("INSERT INTO app_version(platform,version,build,force_update,download_url,notes,enabled) VALUES(?,?,?,?,?,?,?)",
                Svc.str(b.getOrDefault("platform", "iOS")), v, (int) Svc.num(b.get("build"), 1),
                (int) Svc.num(b.get("force_update"), 0), Svc.str(b.get("download_url")), Svc.str(b.get("notes")),
                (int) Svc.num(b.get("enabled"), 1));
        return Resp.ok("版本已创建", Resp.map("id", id));
    }

    @PutMapping("/versions/{id}")
    public Object versionUpdate(@PathVariable long id, @RequestBody Map<String, Object> b, HttpServletResponse resp) {
        if (Db.one("SELECT id FROM app_version WHERE id=?", id) == null) return err(resp, 404, "版本不存在");
        Db.upd("UPDATE app_version SET platform=?,version=?,build=?,force_update=?,download_url=?,notes=?,enabled=? WHERE id=?",
                Svc.str(b.getOrDefault("platform", "iOS")), Svc.str(b.get("version")), (int) Svc.num(b.get("build"), 1),
                (int) Svc.num(b.get("force_update"), 0), Svc.str(b.get("download_url")), Svc.str(b.get("notes")),
                (int) Svc.num(b.get("enabled"), 1), id);
        return Resp.ok("已保存", null);
    }

    @DeleteMapping("/versions/{id}")
    public Object versionDelete(@PathVariable long id) {
        Db.upd("DELETE FROM app_version WHERE id=?", id);
        return Resp.ok("已删除", null);
    }

    // ============================ 内部工具 ============================

    static Object err(HttpServletResponse resp, int status, String msg) {
        resp.setStatus(status);
        return Resp.map("code", status, "message", msg, "data", null);
    }

    static void normalizeUser(Map<String, Object> r) {
        if (r == null) return;
        if (r.containsKey("id")) r.put("id", num(r.get("id")));
        if (r.containsKey("status")) r.put("status", num(r.get("status")));
        if (r.containsKey("live_trading")) r.put("live_trading", num(r.get("live_trading")));
        if (r.get("nickname") == null || Svc.str(r.get("nickname")).isEmpty()) r.put("nickname", Svc.str(r.get("username")));
        if (r.get("email") == null) r.put("email", "");
        r.put("banned", num(r.get("status")) == 0);
    }

    static void logChange(long userId, String field, String oldV, String newV, String operator, String source) {
        try {
            Db.upd("INSERT INTO app_user_change_log(user_id,field,old_value,new_value,operator,source) VALUES(?,?,?,?,?,?)",
                    userId, field, oldV, newV, operator, source);
        } catch (Exception ignore) {}
    }

    static String operator(HttpServletRequest q) {
        var ctx = (QkApiApplication.ConsoleAuth) q.getAttribute("console");
        return ctx == null ? "system" : ctx.username();
    }

    static long num(Object o) { return o instanceof Number n ? n.longValue() : 0; }

    static Long parseLong(String s) { try { return Long.parseLong(s.trim()); } catch (Exception e) { return -1L; } }

    static Object blankToNull(Object o) {
        String s = Svc.str(o);
        return s.isBlank() ? null : s;
    }

    static double money(String sql) {
        Object v = Db.scalar(sql);
        if (v instanceof Number n) return Math.round(n.doubleValue() * 100d) / 100d;
        try { return Math.round(Double.parseDouble(String.valueOf(v)) * 100d) / 100d; } catch (Exception e) { return 0; }
    }

    @SuppressWarnings("unchecked")
    static String permsJson(Object perms) {
        if (perms == null) return "[]";
        if (perms instanceof List<?> l) {
            StringBuilder sb = new StringBuilder("[");
            for (Object o : l) {
                if (sb.length() > 1) sb.append(',');
                sb.append(Json.escape(String.valueOf(o)));
            }
            return sb.append(']').toString();
        }
        String s = String.valueOf(perms).trim();
        if (s.startsWith("[")) return s;
        return "[]";
    }

    /** 解析 JSON 数组形式的权限码（轻量解析，避免引入额外依赖） */
    static List<String> parsePerms(String json) {
        List<String> out = new ArrayList<>();
        if (json == null || json.isBlank()) return out;
        int i = 0;
        while (true) {
            int a = json.indexOf('"', i);
            if (a < 0) break;
            int b = json.indexOf('"', a + 1);
            if (b < 0) break;
            out.add(json.substring(a + 1, b));
            i = b + 1;
        }
        return out;
    }
}
