package com.quantokx.api;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.context.annotation.Bean;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import org.springframework.web.servlet.HandlerInterceptor;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.Cookie;

@SpringBootApplication
@EnableScheduling
public class QkApiApplication {
    public static void main(String[] args) {
        Db.init();
        SpringApplication.run(QkApiApplication.class, args);
    }

    @Bean
    WebMvcConfigurer wc() {
        return new WebMvcConfigurer() {
            @Override
            public void addInterceptors(InterceptorRegistry r) {
                r.addInterceptor(new HandlerInterceptor() {
                    @Override
                    public boolean preHandle(HttpServletRequest q, HttpServletResponse s, Object h) throws Exception {
                        String p = q.getRequestURI();
                        if ("OPTIONS".equalsIgnoreCase(q.getMethod())) return true;
                        for (String x : new String[]{"/api/ios/ping","/api/ios/login","/api/ios/register","/api/ai/cron","/api/strategy/cron","/api/member/pay","/api/pay/notify","/api/pay/return"}) {
                            if (p.equals(x)) return true;
                        }
                        String t = cookie(q, Sess.COOKIE);
                        Long uid = t == null ? null : Sess.userIdOf(t);
                        if (uid == null) {
                            s.setStatus(401);
                            s.setContentType("application/json; charset=utf-8");
                            s.getWriter().write("{\"code\":-1,\"message\":\"未登录或会话已过期\",\"data\":null}");
                            return false;
                        }
                        q.setAttribute("uid", uid);
                        q.setAttribute("tk", t);
                        String m = q.getMethod().toUpperCase();
                        if (m.equals("POST")||m.equals("PUT")||m.equals("DELETE")) {
                            String pv = q.getHeader("X-CSRF-TOKEN");
                            String ex = Sess.csrfOf(t);
                            if (ex.isEmpty()||pv==null||!ex.equals(pv)) {
                                s.setStatus(419);
                                s.setContentType("application/json; charset=utf-8");
                                s.getWriter().write("{\"code\":-1,\"message\":\"CSRF 校验失败\",\"data\":null}");
                                return false;
                            }
                        }
                        return true;
                    }
                }).addPathPatterns("/api/**");
            }
        };
    }

    static String cookie(HttpServletRequest q, String n) {
        Cookie[] cs = q.getCookies();
        if (cs==null) return null;
        for (Cookie c : cs) if (n.equals(c.getName())) return c.getValue();
        return null;
    }
}
