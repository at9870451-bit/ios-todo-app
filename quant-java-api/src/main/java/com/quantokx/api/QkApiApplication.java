package com.quantokx.api;

import io.jsonwebtoken.Claims;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.util.Map;

/**
 * 应用入口与拦截器链。
 *  - /api/**            ：iOS App 会话认证（QBSESSID Cookie + CSRF），行为与 v1.x 一致
 *  - /api/console/**    ：Web 管理后台（JWT Bearer + 权限码 + 操作日志）
 *  - /panel/**          ：管理后台 Vue 静态资源（无需认证，登录态由前端 JWT 控制）
 */
@SpringBootApplication
@EnableScheduling
public class QkApiApplication {

    public static void main(String[] args) {
        boolean migrate = java.util.Arrays.asList(args).contains("--migrate");
        SpringApplication app = new SpringApplication(QkApiApplication.class);
        if (migrate) app.setWebApplicationType(org.springframework.boot.WebApplicationType.NONE);
        app.run(args);
    }

    @Scheduled(fixedDelay = 60_000)
    void redisProbe() { Rds.probe(); }

    /** iOS App 侧免认证白名单 */
    static final String[] OPEN = {
        "/api/ios/ping", "/api/ios/login", "/api/ios/register", "/api/ios/announcement", "/api/ios/config",
        "/api/ai/cron", "/api/strategy/cron", "/api/member/notify", "/api/pay/notify", "/api/pay/return"
    };

    /** Console 侧免认证白名单 */
    static final String[] CONSOLE_OPEN = {"/api/console/auth/login"};

    @Bean
    WebMvcConfigurer wc() {
        return new WebMvcConfigurer() {
            @Override
            public void addCorsMappings(CorsRegistry r) {
                r.addMapping("/api/console/**").allowedOriginPatterns("*")
                        .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                        .allowedHeaders("*").allowCredentials(true).maxAge(3600);
            }

            /** Doll Studio 3D 模型文件静态下发（data/doll-models/ → /doll-assets/**，无需认证） */
            @Override
            public void addResourceHandlers(org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry r) {
                String dir = System.getProperty("user.dir") + "/data/doll-models";
                r.addResourceHandler("/doll-assets/**").addResourceLocations("file:" + dir + "/");
            }

            @Override
            public void addInterceptors(InterceptorRegistry r) {
                // ---- Console 管理后台：JWT ----
                r.addInterceptor(new HandlerInterceptor() {
                    @Override
                    public boolean preHandle(HttpServletRequest q, HttpServletResponse s, Object h) throws Exception {
                        String p = q.getRequestURI();
                        if ("OPTIONS".equalsIgnoreCase(q.getMethod())) return true;
                        for (String x : CONSOLE_OPEN) if (p.equals(x)) return true;

                        String auth = q.getHeader("Authorization");
                        String token = (auth != null && auth.startsWith("Bearer ")) ? auth.substring(7).trim() : null;
                        Claims cl = token == null ? null : JwtUtil.parse(token);
                        if (cl == null) return deny(s, 401, "登录已过期，请重新登录");
                        String jti = cl.getId();
                        // Redis 会话校验：显式登出后 token 立即失效；Redis 不可用时退化为纯 JWT 校验
                        String sess = Rds.get("qb:admintoken:" + jti);
                        if (sess == null && Rds.available()) return deny(s, 401, "登录已失效，请重新登录");
                        Long aid = cl.get("aid", Number.class) == null ? null : cl.get("aid", Number.class).longValue();
                        if (aid == null) return deny(s, 401, "登录已失效，请重新登录");

                        Map<String, Object> admin = Db.one("SELECT a.id,a.username,a.nickname,a.role_id,a.status,r.code AS role_code,r.name AS role_name,r.perms " +
                                "FROM sys_admin a LEFT JOIN sys_role r ON r.id=a.role_id WHERE a.id=?", aid);
                        if (admin == null) return deny(s, 401, "管理员不存在");
                        if (num(admin.get("status")) != 1) return deny(s, 403, "管理员账号已被禁用");

                        ConsoleAuth ctx = new ConsoleAuth(aid, Svc.str(admin.get("username")), Svc.str(admin.get("role_code")),
                                Svc.str(admin.get("perms")), Svc.str(admin.get("role_name")), num(admin.get("role_id")));
                        q.setAttribute("console", ctx);
                        q.setAttribute("adminId", aid);

                        // 权限码校验（所有方法，含 GET 读接口）
                        String m = q.getMethod().toUpperCase();
                        String need = ConsoleAuth.requiredPerm(p, m);
                        if (need != null && !ctx.has(need)) return deny(s, 403, "无权限执行该操作（需要 " + need + "）");
                        return true;
                    }

                    @Override
                    public void afterCompletion(HttpServletRequest q, HttpServletResponse s, Object h, Exception e) {
                        String m = q.getMethod().toUpperCase();
                        if (m.equals("GET") || m.equals("OPTIONS")) return;
                        ConsoleAuth ctx = (ConsoleAuth) q.getAttribute("console");
                        if (ctx == null) return;
                        try {
                            Db.upd("INSERT INTO sys_operation_log(admin_id,admin_name,action,method,path,params,ip,status) VALUES(?,?,?,?,?,?,?,?)",
                                    ctx.id(), ctx.username(), ConsoleAuth.actionName(q.getRequestURI(), m), m, q.getRequestURI(),
                                    trim(q.getQueryString(), 500), ip(q), s.getStatus());
                        } catch (Exception ignore) {}
                    }
                }).addPathPatterns("/api/console/**");

                // ---- iOS App：Cookie 会话 + CSRF ----
                r.addInterceptor(new HandlerInterceptor() {
                    @Override
                    public boolean preHandle(HttpServletRequest q, HttpServletResponse s, Object h) throws Exception {
                        String p = q.getRequestURI();
                        if ("OPTIONS".equalsIgnoreCase(q.getMethod())) return true;
                        for (String x : OPEN) if (p.equals(x)) return true;
                        String t = cookie(q, Sess.COOKIE);
                        Long uid = t == null ? null : Sess.userIdOf(t);
                        if (uid == null) return deny(s, 401, "未登录或会话已过期");
                        q.setAttribute("uid", uid);
                        q.setAttribute("tk", t);
                        String m = q.getMethod().toUpperCase();
                        if (m.equals("POST") || m.equals("PUT") || m.equals("DELETE")) {
                            String pv = q.getHeader("X-CSRF-TOKEN");
                            String ex = Sess.csrfOf(t);
                            if (ex.isEmpty() || pv == null || !ex.equals(pv)) return deny(s, 419, "CSRF 校验失败");
                        }
                        return true;
                    }
                }).addPathPatterns("/api/**").excludePathPatterns("/api/console/**");
            }
        };
    }

    static boolean deny(HttpServletResponse s, int status, String msg) throws Exception {
        s.setStatus(status);
        s.setContentType("application/json; charset=utf-8");
        s.getWriter().write("{\"code\":" + status + ",\"message\":\"" + msg + "\",\"data\":null}");
        return false;
    }

    static long num(Object o) { return o instanceof Number n ? n.longValue() : 0; }

    static String trim(String s, int max) { return s == null ? null : (s.length() > max ? s.substring(0, max) : s); }

    public static String cookie(HttpServletRequest q, String n) {
        Cookie[] cs = q.getCookies();
        if (cs == null) return null;
        for (Cookie c : cs) if (n.equals(c.getName())) return c.getValue();
        return null;
    }

    /** 真实客户端 IP（兼容宝塔 nginx 反代） */
    public static String ip(HttpServletRequest q) {
        for (String h : new String[]{"X-Real-IP", "X-Forwarded-For", "Proxy-Client-IP", "WL-Proxy-Client-IP"}) {
            String v = q.getHeader(h);
            if (v != null && !v.isBlank() && !"unknown".equalsIgnoreCase(v)) {
                int i = v.indexOf(',');
                return (i > 0 ? v.substring(0, i) : v).trim();
            }
        }
        return q.getRemoteAddr();
    }

    /** 当前登录管理员上下文 */
    public record ConsoleAuth(long id, String username, String roleCode, String perms, String roleName, long roleId) {
        public boolean isSuper() { return "superadmin".equals(roleCode); }
        public boolean has(String perm) {
            if (isSuper()) return true;
            if (perms == null || perms.isBlank()) return false;
            return perms.contains("\"" + perm + "\"");
        }
        public static String requiredPerm(String path, String method) {
            if (path.startsWith("/api/console/auth/")) return null;
            if (path.startsWith("/api/console/users")) {
                if (path.contains("/ban") || path.contains("/unban")) return "users:ban";
                if (path.contains("/reset-password")) return "users:resetpw";
                return "users:read";
            }
            if (path.startsWith("/api/console/stats")) return "stats:read";
            if (path.startsWith("/api/console/admins")) return "admins:manage";
            if (path.startsWith("/api/console/roles")) return "roles:manage";
            if (path.startsWith("/api/console/logs")) return "logs:read";
            if (path.startsWith("/api/console/config")) return "config:manage";
            if (path.startsWith("/api/console/announcements")) return "announcements:manage";
            if (path.startsWith("/api/console/versions")) return "versions:manage";
            if (path.startsWith("/api/console/doll")) return "doll:manage";
            return null;
        }
        public static String actionName(String path, String method) {
            if (path.contains("/ban")) return "封禁用户";
            if (path.contains("/unban")) return "解封用户";
            if (path.contains("/reset-password") && path.contains("/users")) return "重置用户密码";
            if (path.contains("/reset-password")) return "重置管理员密码";
            if (path.startsWith("/api/console/auth/login")) return "管理员登录";
            if (path.startsWith("/api/console/auth/logout")) return "管理员登出";
            if (path.startsWith("/api/console/auth/password")) return "修改密码";
            if (path.startsWith("/api/console/admins")) return "DELETE".equals(method) ? "删除管理员" : ("POST".equals(method) ? "新增管理员" : "修改管理员");
            if (path.startsWith("/api/console/roles")) return "DELETE".equals(method) ? "删除角色" : ("POST".equals(method) ? "新增角色" : "修改角色");
            if (path.startsWith("/api/console/config")) return "修改系统配置";
            if (path.startsWith("/api/console/announcements")) return "DELETE".equals(method) ? "删除公告" : ("POST".equals(method) ? "新增公告" : "修改公告");
            if (path.startsWith("/api/console/versions")) return "DELETE".equals(method) ? "删除版本" : ("POST".equals(method) ? "新增版本" : "修改版本");
            if (path.startsWith("/api/console/doll")) return "管理 Doll Studio（玩偶换装）";
            return method + " " + path;
        }
    }
}
