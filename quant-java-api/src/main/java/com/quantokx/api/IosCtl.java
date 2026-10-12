package com.quantokx.api;

import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;

@RestController
@RequestMapping("/api/ios")
public class IosCtl {

    @GetMapping("/ping")
    public Map<String, Object> ping(HttpServletRequest req, jakarta.servlet.http.HttpServletResponse resp) {
        String token = QkApiApplication.cookie(req, Sess.COOKIE);
        String csrf = token != null ? Sess.csrfOf(token) : "";
        if (csrf.isEmpty()) {
            token = Sess.newToken();
            Sess.create(token);
            csrf = Sess.csrfOf(token);
            resp.addHeader("Set-Cookie", Sess.COOKIE + "=" + token + "; Path=/; HttpOnly; Max-Age=604800");
        }
        return Resp.ok(Resp.map("app","QuantOKX","version","1.5","csrf_token",csrf));
    }

    @PostMapping("/login")
    public Map<String, Object> login(@RequestBody Map<String, Object> body, HttpServletResponse resp) {
        String username = Svc.str(body.get("username"));
        String password = Svc.str(body.get("password"));
        var r = Sess.login(username, password);
        if (!r.ok()) { resp.setStatus(401); return Resp.map("code", "AUTH_FAILED", "message", r.message(), "data", null); }
        String token = Sess.create(r.userId());
        resp.addHeader("Set-Cookie", Sess.COOKIE + "=" + token + "; Path=/; HttpOnly; Max-Age=604800");
        return payload(r.userId(), Sess.csrfOf(token), "登录成功");
    }

    @PostMapping("/register")
    public Map<String, Object> register(@RequestBody Map<String, Object> body, HttpServletResponse resp) {
        var r = Sess.register(Svc.str(body.get("username")), Svc.str(body.get("password")), Svc.str(body.get("email")));
        if (!r.ok()) { resp.setStatus(422); return Resp.map("code", "REGISTER_FAILED", "message", r.message(), "data", null); }
        String token = Sess.create(r.userId());
        resp.addHeader("Set-Cookie", Sess.COOKIE + "=" + token + "; Path=/; HttpOnly; Max-Age=604800");
        return payload(r.userId(), Sess.csrfOf(token), "注册成功");
    }

    @GetMapping("/me")
    public Map<String, Object> me(HttpServletRequest req) {
        Long uid = (Long) req.getAttribute("uid");
        String tk = (String) req.getAttribute("tk");
        if (uid == null) return Resp.map("code","UNAUTHORIZED","message","未登录","data",null);
        return payload(uid, tk != null ? Sess.csrfOf(tk) : "", "success");
    }

    @PostMapping("/logout")
    public Map<String, Object> logout(HttpServletRequest req) {
        String token = (String) req.getAttribute("tk");
        if (token != null) Sess.drop(token);
        return Resp.ok(null);
    }

    static Map<String, Object> payload(long uid, String csrf, String message) {
        var u = Db.one("SELECT * FROM users WHERE id=?", uid);
        if (u == null) return Resp.map("code","USER_NOT_FOUND","message","用户不存在","data",null);
        String role = Svc.str(u.get("role"));
        String level = Svc.str(u.get("level"));
        Map<String, Object> user = Resp.map(
            "id", ((Number)u.get("id")).longValue(),
            "username", Svc.str(u.get("username")),
            "nickname", Svc.str(u.get("username")),
            "email", Svc.str(u.get("email")),
            "role", role,
            "membership_level", level,
            "live_trading_enabled", ((Number)u.getOrDefault("live_trading", 0)).intValue() == 1
        );
        Map<String, Object> badge = Resp.map("level", level, "name", Member.levelName(level), "is_admin", "admin".equals(role), "expire_at", null, "days_left", null, "auto_renew", false);
        return Resp.ok(message, Resp.map("user", user, "csrf_token", csrf, "badge", badge));
    }
}
