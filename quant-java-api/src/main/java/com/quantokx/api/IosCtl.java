package com.quantokx.api;

import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.util.*;

/**
 * iOS App 接口（/api/ios/**）。响应形状与 v1.x 完全兼容（{code:0,message,data}），
 * v2.0 增强：注册/登录写入真实登录日志与设备信息、封禁拦截、注册开关、资料读取与更新、公告与配置下发。
 */
@RestController
@RequestMapping("/api/ios")
public class IosCtl {

    @GetMapping("/ping")
    public Object ping(HttpServletRequest req, HttpServletResponse resp) {
        String token = QkApiApplication.cookie(req, Sess.COOKIE);
        String csrf = token != null ? Sess.csrfOf(token) : "";
        if (csrf.isEmpty()) {
            token = Sess.newToken();
            Sess.createWith(token);
            resp.addHeader("Set-Cookie", Sess.COOKIE + "=" + token + "; Path=/; HttpOnly; Max-Age=604800");
        }
        return Resp.ok(Resp.map("app", cfg("site_name", "Amore"), "version", cfg("app_version", "3.7"), "csrf_token", csrf));
    }

    @PostMapping("/login")
    public Object login(@RequestBody Map<String, Object> body, HttpServletRequest req, HttpServletResponse resp) {
        String username = Svc.str(body.get("username"));
        String password = Svc.str(body.get("password"));
        var r = Sess.login(username, password);
        if (!r.ok()) {
            recordLogin(req, findUserId(username), 0, body);
            resp.setStatus(401);
            return Resp.map("code", "AUTH_FAILED", "message", r.message(), "data", null);
        }
        Map<String, Object> u = Db.one("SELECT status,ban_reason,ban_until FROM users WHERE id=?", r.userId());
        if (u != null && num(u.get("status")) != 1) {
            String reason = Svc.str(u.get("ban_reason"));
            if (reason.isBlank()) reason = "违反用户协议";
            recordLogin(req, r.userId(), 0, body);
            resp.setStatus(403);
            return Resp.map("code", "ACCOUNT_BANNED", "message", "账号已被封禁：" + reason, "data", null);
        }
        String token = Sess.create(r.userId());
        resp.addHeader("Set-Cookie", Sess.COOKIE + "=" + token + "; Path=/; HttpOnly; Max-Age=604800");
        String ip = QkApiApplication.ip(req);
        Db.upd("UPDATE users SET last_login_at=NOW(), last_login_ip=? WHERE id=?", ip, r.userId());
        recordLogin(req, r.userId(), 1, body);
        recordDevice(req, r.userId(), body);
        return payload(r.userId(), Sess.csrfOf(token), "登录成功");
    }

    @PostMapping("/register")
    public Object register(@RequestBody Map<String, Object> body, HttpServletRequest req, HttpServletResponse resp) {
        if (!"1".equals(cfg("register_enabled", "1"))) {
            resp.setStatus(422);
            return Resp.map("code", "REGISTER_FAILED", "message", "注册已关闭，请联系管理员", "data", null);
        }
        String username = Svc.str(body.get("username"));
        String password = Svc.str(body.get("password"));
        String email = Svc.str(body.get("email"));
        if ("1".equals(cfg("register_need_email", "0")) && email.isBlank()) {
            resp.setStatus(422);
            return Resp.map("code", "REGISTER_FAILED", "message", "请填写邮箱", "data", null);
        }
        if (!email.isBlank() && !email.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) {
            resp.setStatus(422);
            return Resp.map("code", "REGISTER_FAILED", "message", "邮箱格式不正确", "data", null);
        }
        var r = Sess.register(username, password, email);
        if (!r.ok()) {
            resp.setStatus(422);
            return Resp.map("code", "REGISTER_FAILED", "message", r.message(), "data", null);
        }
        String ip = QkApiApplication.ip(req);
        Db.upd("UPDATE users SET nickname=?, email=?, created_at=NOW(), register_ip=?, last_login_at=NOW(), last_login_ip=?, status=1 WHERE id=?",
                username, email.isBlank() ? null : email, ip, ip, r.userId());
        String token = Sess.create(r.userId());
        resp.addHeader("Set-Cookie", Sess.COOKIE + "=" + token + "; Path=/; HttpOnly; Max-Age=604800");
        recordLogin(req, r.userId(), 1, body);
        recordDevice(req, r.userId(), body);
        return payload(r.userId(), Sess.csrfOf(token), "注册成功");
    }

    @GetMapping("/me")
    public Object me(HttpServletRequest req) {
        Long uid = (Long) req.getAttribute("uid");
        String tk = (String) req.getAttribute("tk");
        if (uid == null) return Resp.map("code", "UNAUTHORIZED", "message", "未登录", "data", null);
        return payload(uid, tk != null ? Sess.csrfOf(tk) : "", "success");
    }

    /** 新增：获取个人资料 */
    @GetMapping("/profile")
    public Object profile(HttpServletRequest req, HttpServletResponse resp) {
        Long uid = (Long) req.getAttribute("uid");
        Map<String, Object> u = Db.one("SELECT id,username,nickname,email,role,level,live_trading,status,created_at,last_login_at,last_login_ip FROM users WHERE id=?", uid);
        if (u == null) {
            resp.setStatus(404);
            return Resp.map("code", "USER_NOT_FOUND", "message", "用户不存在", "data", null);
        }
        return Resp.ok("success", Resp.map("user", profileView(u)));
    }

    /** 新增：更新个人资料（昵称 / 邮箱） */
    @PostMapping("/profile")
    public Object updateProfile(@RequestBody Map<String, Object> body, HttpServletRequest req, HttpServletResponse resp) {
        Long uid = (Long) req.getAttribute("uid");
        Map<String, Object> old = Db.one("SELECT nickname,email FROM users WHERE id=?", uid);
        if (old == null) {
            resp.setStatus(404);
            return Resp.map("code", "USER_NOT_FOUND", "message", "用户不存在", "data", null);
        }
        String nickname = body.get("nickname") == null ? Svc.str(old.get("nickname")) : Svc.str(body.get("nickname")).trim();
        String email = body.get("email") == null ? Svc.str(old.get("email")) : Svc.str(body.get("email")).trim();
        if (nickname.length() > 20) {
            resp.setStatus(422);
            return Resp.map("code", "INVALID_NICKNAME", "message", "昵称最多 20 个字符", "data", null);
        }
        if (!email.isBlank() && !email.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) {
            resp.setStatus(422);
            return Resp.map("code", "INVALID_EMAIL", "message", "邮箱格式不正确", "data", null);
        }
        Db.upd("UPDATE users SET nickname=?, email=? WHERE id=?", nickname, email.isBlank() ? null : email, uid);
        if (!nickname.equals(Svc.str(old.get("nickname")))) ConsoleCtl.logChange(uid, "nickname", Svc.str(old.get("nickname")), nickname, "user", "ios");
        if (!email.equals(Svc.str(old.get("email")))) ConsoleCtl.logChange(uid, "email", Svc.str(old.get("email")), email, "user", "ios");
        Map<String, Object> u = Db.one("SELECT id,username,nickname,email,role,level,live_trading,status,created_at,last_login_at,last_login_ip FROM users WHERE id=?", uid);
        return Resp.ok("资料已更新", Resp.map("user", profileView(u)));
    }

    @PostMapping("/logout")
    public Object logout(HttpServletRequest req) {
        String token = (String) req.getAttribute("tk");
        if (token != null) Sess.drop(token);
        return Resp.ok("已退出登录", null);
    }

    /** 新增：公告下发（取当前生效的最新一条） */
    @GetMapping("/announcement")
    public Object announcement() {
        Map<String, Object> a = Db.one("SELECT id,title,content,type,updated_at FROM app_announcement " +
                "WHERE enabled=1 AND (start_at IS NULL OR start_at<=NOW()) AND (end_at IS NULL OR end_at>=NOW()) " +
                "ORDER BY id DESC LIMIT 1");
        return Resp.ok("success", a);
    }

    /** 新增：客户端配置下发（注册开关/维护模式/版本） */
    @GetMapping("/config")
    public Object config() {
        Map<String, Object> latest = Db.one("SELECT version,build,force_update,download_url FROM app_version WHERE enabled=1 ORDER BY id DESC LIMIT 1");
        String latestVer = latest == null ? cfg("app_version", "3.7") : Svc.str(latest.get("version"));
        String minVer = cfg("min_version", "3.0");
        boolean force = false;
        if (latest != null) force = num(latest.get("force_update")) == 1;
        return Resp.ok("success", Resp.map(
                "register_enabled", cfg("register_enabled", "1"),
                "register_need_email", cfg("register_need_email", "0"),
                "maintain_mode", cfg("maintain_mode", "0"),
                "site_name", cfg("site_name", "Amore"),
                "announcement", cfg("announcement", ""),
                "latest_version", latestVer,
                "min_version", minVer,
                "force_update", force,
                "download_url", latest == null ? "" : Svc.str(latest.get("download_url"))));
    }

    // ---------------- 内部工具 ----------------

    static Object payload(long uid, String csrf, String message) {
        var u = Db.one("SELECT * FROM users WHERE id=?", uid);
        if (u == null) return Resp.map("code", "USER_NOT_FOUND", "message", "用户不存在", "data", null);
        String role = Svc.str(u.get("role"));
        String level = Svc.str(u.get("level"));
        Map<String, Object> user = Resp.map(
            "id", num(u.get("id")),
            "username", Svc.str(u.get("username")),
            "nickname", Svc.str(u.get("nickname")).isEmpty() ? Svc.str(u.get("username")) : Svc.str(u.get("nickname")),
            "email", Svc.str(u.get("email")),
            "role", role,
            "membership_level", level,
            "live_trading_enabled", num(u.get("live_trading")) == 1
        );
        Map<String, Object> badge = MemberSvc.badgeOf(uid);
        badge.put("is_admin", "admin".equals(role));
        return Resp.ok(message, Resp.map("user", user, "csrf_token", csrf, "badge", badge));
    }

    static Map<String, Object> profileView(Map<String, Object> u) {
        return Resp.map(
            "id", num(u.get("id")),
            "username", Svc.str(u.get("username")),
            "nickname", Svc.str(u.get("nickname")).isEmpty() ? Svc.str(u.get("username")) : Svc.str(u.get("nickname")),
            "email", Svc.str(u.get("email")),
            "role", Svc.str(u.get("role")),
            "membership_level", Svc.str(u.get("level")),
            "live_trading_enabled", num(u.get("live_trading")) == 1,
            "created_at", u.get("created_at"),
            "last_login_at", u.get("last_login_at"));
    }

    static String cfg(String k, String def) {
        Object v = Db.scalar("SELECT v FROM sys_config WHERE k=?", k);
        String s = v == null ? null : v.toString();
        return (s == null || s.isBlank()) ? def : s;
    }

    static long num(Object o) { return o instanceof Number n ? n.longValue() : 0; }

    static Long findUserId(String username) {
        if (username == null || username.isBlank()) return null;
        Object v = Db.scalar("SELECT id FROM users WHERE username=?", username);
        return v instanceof Number n ? n.longValue() : null;
    }

    /** 写入登录日志（含设备信息），供管理后台「登录记录」展示 */
    static void recordLogin(HttpServletRequest req, Long userId, int success, Map<String, Object> body) {
        if (userId == null) return;
        try {
            Map<String, Object> d = device(body);
            Db.upd("INSERT INTO app_user_login_log(user_id,ip,ua,device_model,os_version,app_version,success) VALUES(?,?,?,?,?,?,?)",
                    userId, QkApiApplication.ip(req), trim(req.getHeader("User-Agent"), 500),
                    Svc.str(d.get("device_model")), Svc.str(d.get("os_version")), Svc.str(d.get("app_version")), success);
        } catch (Exception ignore) {}
    }

    /** 设备指纹 upsert */
    static void recordDevice(HttpServletRequest req, Long userId, Map<String, Object> body) {
        if (userId == null) return;
        try {
            Map<String, Object> d = device(body);
            String deviceId = Svc.str(d.get("device_id"));
            if (deviceId.isBlank()) deviceId = "ua-" + Math.abs(Objects.hashCode(req.getHeader("User-Agent")));
            Db.upd("INSERT INTO app_user_device(user_id,device_id,device_model,os_version,app_version,last_seen_at,created_at) " +
                    "VALUES(?,?,?,?,?,NOW(),NOW()) ON DUPLICATE KEY UPDATE device_model=VALUES(device_model), " +
                    "os_version=VALUES(os_version), app_version=VALUES(app_version), last_seen_at=NOW()",
                    userId, deviceId, Svc.str(d.get("device_model")), Svc.str(d.get("os_version")), Svc.str(d.get("app_version")));
        } catch (Exception ignore) {}
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> device(Map<String, Object> body) {
        if (body == null) return new LinkedHashMap<>();
        Object d = body.get("device");
        if (d instanceof Map<?, ?> m) {
            Map<String, Object> out = new LinkedHashMap<>();
            for (Map.Entry<?, ?> e : m.entrySet()) out.put(String.valueOf(e.getKey()), e.getValue());
            return out;
        }
        return new LinkedHashMap<>();
    }

    static String trim(String s, int max) { return s == null ? null : (s.length() > max ? s.substring(0, max) : s); }
}
