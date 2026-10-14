package com.quantokx.api;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ResponseBody;

import jakarta.servlet.http.HttpServletResponse;
import java.io.InputStream;

/**
 * 管理后台 Web 面板静态资源入口。
 * Vue 构建产物位于 classpath:/static/panel/，通过 /panel 与 /panel/** 访问（hash 路由，SPA 单页）。
 */
@Controller
public class AdminPageCtl {

    @GetMapping({"/panel", "/panel/", "/panel/index.html"})
    public void index(HttpServletResponse r) throws Exception {
        serve(r, "/static/panel/index.html");
    }

    /** 静态资源（js/css/图片等），命中不了则回落 index.html（SPA） */
    @GetMapping("/panel/**")
    public void asset(jakarta.servlet.http.HttpServletRequest q, HttpServletResponse r) throws Exception {
        String uri = q.getRequestURI();
        String rel = uri.substring("/panel/".length());
        if (rel.contains("..")) { r.setStatus(404); return; }
        if (rel.isBlank()) { serve(r, "/static/panel/index.html"); return; }
        InputStream in = AdminPageCtl.class.getResourceAsStream("/static/panel/" + rel);
        if (in == null) { serve(r, "/static/panel/index.html"); return; }
        in.close();
        serve(r, "/static/panel/" + rel);
    }

    /** 面板健康检查（无需登录） */
    @GetMapping("/panel/health")
    @ResponseBody
    public Object health() {
        return Resp.ok(Resp.map("panel", "ok", "db", dbOk(), "redis", Rds.available() ? "up" : "degraded(memory)"));
    }

    private static boolean dbOk() {
        try { return Db.scalar("SELECT 1") != null; } catch (Exception e) { return false; }
    }

    private static void serve(HttpServletResponse r, String path) throws Exception {
        ClassPathResource res = new ClassPathResource(path);
        if (!res.exists()) {
            r.setStatus(404);
            r.setContentType("text/html; charset=utf-8");
            r.getWriter().write("<h1>管理面板未打包</h1><p>请先执行 admin-web 的 npm run build 并将 dist 复制到 src/main/resources/static/panel/</p>");
            return;
        }
        String name = path.toLowerCase();
        if (name.endsWith(".html")) r.setContentType("text/html; charset=utf-8");
        else if (name.endsWith(".js")) r.setContentType("application/javascript; charset=utf-8");
        else if (name.endsWith(".css")) r.setContentType("text/css; charset=utf-8");
        else if (name.endsWith(".json")) r.setContentType("application/json; charset=utf-8");
        else if (name.endsWith(".svg")) r.setContentType("image/svg+xml");
        else if (name.endsWith(".png")) r.setContentType("image/png");
        else if (name.endsWith(".woff2")) r.setContentType("font/woff2");
        else if (name.endsWith(".woff")) r.setContentType("font/woff");
        else if (name.endsWith(".ttf")) r.setContentType("font/ttf");
        else r.setContentType("application/octet-stream");
        r.setHeader("Cache-Control", name.endsWith(".html") ? "no-store" : "public, max-age=604800");
        try (InputStream in = res.getInputStream()) {
            r.getOutputStream().write(in.readAllBytes());
        }
    }
}
