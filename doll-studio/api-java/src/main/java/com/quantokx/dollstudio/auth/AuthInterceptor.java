package com.quantokx.dollstudio.auth;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import java.util.Map;

/**
 * 认证拦截器：
 *  - /outfits/**、/ai/outfits  → 用户 Bearer token
 *  - /admin/**（除 login）     → 管理员 token（uid 前缀 A:）
 */
@Component
public class AuthInterceptor implements HandlerInterceptor {

    @Value("${dollstudio.token-secret}")
    private String secret;

    private final ObjectMapper om = new ObjectMapper();

    public static final ThreadLocal<Long> CURRENT_USER = new ThreadLocal<>();
    public static final ThreadLocal<Boolean> IS_ADMIN = new ThreadLocal<>();

    @Override
    public boolean preHandle(HttpServletRequest req, HttpServletResponse resp, Object handler) throws Exception {
        String path = req.getRequestURI(); // context-path /api 已被剥掉
        boolean needsUser = path.startsWith("/outfits") || path.startsWith("/ai/");
        boolean needsAdmin = path.startsWith("/admin/") && !path.equals("/admin/login");
        if (!needsUser && !needsAdmin) return true;

        String auth = req.getHeader("Authorization");
        if (auth == null || !auth.matches("(?i)^Bearer\\s+\\S+$")) {
            return reject(resp, 401, "未登录");
        }
        String token = auth.replaceFirst("(?i)^Bearer\\s+", "");
        long uid;
        try {
            uid = TokenUtil.verify(token, secret);
        } catch (Exception e) {
            return reject(resp, 401, "凭证无效：" + e.getMessage());
        }
        if (needsAdmin) {
            // 管理员 token：uid 为负数（-adminId）
            if (uid >= 0) return reject(resp, 403, "需要管理员权限");
            IS_ADMIN.set(true);
        } else {
            CURRENT_USER.set(uid);
        }
        return true;
    }

    private boolean reject(HttpServletResponse resp, int code, String msg) throws Exception {
        resp.setStatus(code);
        resp.setContentType("application/json;charset=utf-8");
        resp.getWriter().write(om.writeValueAsString(Map.of("ok", false, "error", msg)));
        return false;
    }

    @Override
    public void afterCompletion(HttpServletRequest r, HttpServletResponse s, Object h, Exception e) {
        CURRENT_USER.remove();
        IS_ADMIN.remove();
    }
}
