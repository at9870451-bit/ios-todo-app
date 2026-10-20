package com.quantokx.api;

import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.util.*;
import java.util.concurrent.TimeUnit;

/**
 * Web 本地终端（仅超级管理员）：在服务器上执行 shell 命令并返回输出。
 * 安全约束：role_code=superadmin；单次执行超时 15s；写入操作日志。
 */
@RestController
@RequestMapping("/api/console/terminal")
public class TerminalCtl {

    private Map<String, Object> deny(HttpServletResponse resp, int code, String msg) throws Exception {
        resp.setStatus(code);
        return null;
    }

    static Object err(HttpServletResponse resp, int status, String msg) {
        resp.setStatus(status);
        return Resp.map("code", status, "message", msg, "data", null);
    }

    private boolean guard(HttpServletRequest q, HttpServletResponse resp) throws Exception {
        var ctx = (QkApiApplication.ConsoleAuth) q.getAttribute("console");
        if (ctx == null) { deny(resp, 401, "未登录"); return false; }
        if (!"superadmin".equals(ctx.roleCode())) { deny(resp, 403, "仅超级管理员可用终端"); return false; }
        return true;
    }

    @PostMapping("/exec")
    public Object exec(@RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) throws Exception {
        if (!guard(q, resp)) return null;
        String cmd = Svc.str(b.get("cmd")).trim();
        if (cmd.isEmpty()) return err(resp, 422, "命令不能为空");
        if (cmd.length() > 4000) return err(resp, 422, "命令过长");

        long t0 = System.currentTimeMillis();
        int exit = -1;
        String out;
        try {
            ProcessBuilder pb = new ProcessBuilder("/bin/sh", "-c", cmd);
            pb.directory(new java.io.File("/opt"));
            pb.redirectErrorStream(true);
            Process p = pb.start();
            boolean done = p.waitFor(15, TimeUnit.SECONDS);
            if (!done) {
                p.destroyForcibly();
                out = "[超时] 命令执行超过 15 秒，已终止。\n(部分输出)\n" + new String(p.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
            } else {
                exit = p.exitValue();
                out = new String(p.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
            }
        } catch (Exception e) {
            out = "[异常] " + e.getMessage();
        }
        long ms = System.currentTimeMillis() - t0;
        try {
            var ctx = (QkApiApplication.ConsoleAuth) q.getAttribute("console");
            Db.upd("INSERT INTO sys_operation_log(admin_id,admin_name,action,method,path,params,ip,status) VALUES(?,?,?,?,?,?,?,?)",
                    ctx.id(), ctx.username(), "终端命令", "POST", "/api/console/terminal/exec",
                    cmd.length() > 500 ? cmd.substring(0, 500) : cmd,
                    QkApiApplication.ip(q), exit == 0 ? 200 : 500);
        } catch (Exception ignore) {}

        if (out.length() > 100_000) out = out.substring(0, 100_000) + "\n...[输出过长已截断]";
        return Resp.ok(Resp.map("exit", exit, "output", out, "ms", ms));
    }

    /** 环境信息（打开终端时展示） */
    @GetMapping("/info")
    public Object info(HttpServletRequest q, HttpServletResponse resp) throws Exception {
        if (!guard(q, resp)) return null;
        String user = Svc.str(Db.scalar("SELECT CURRENT_USER()"));
        String host = java.net.InetAddress.getLocalHost().getHostName();
        return Resp.ok(Resp.map("user", user, "host", host, "cwd", "/opt"));
    }
}
