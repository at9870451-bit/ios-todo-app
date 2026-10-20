package com.quantokx.api;

import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.util.*;

/**
 * 智能体模板管理（管理面板 CRUD + App 拉取）。
 * - /api/console/agents/** ：管理后台（JWT，config:manage）
 * - /api/ios/agents        ：iOS App（QBSESSID），返回启用中的智能体模板
 */
@RestController
public class AgentCtl {

    static Object err(HttpServletResponse resp, int status, String msg) {
        try { resp.setStatus(status); } catch (Exception ignore) {}
        return Resp.map("code", status, "message", msg, "data", null);
    }

    static void logOp(HttpServletRequest q, String action, String path, String params) {
        try {
            var ctx = (QkApiApplication.ConsoleAuth) q.getAttribute("console");
            Db.upd("INSERT INTO sys_operation_log(admin_id,admin_name,action,method,path,params,ip,status) VALUES(?,?,?,?,?,?,?,?)",
                    ctx.id(), ctx.username(), action, "POST", path, params, QkApiApplication.ip(q), 200);
        } catch (Exception ignore) {}
    }

    private boolean guard(HttpServletRequest q, HttpServletResponse resp) {
        var ctx = (QkApiApplication.ConsoleAuth) q.getAttribute("console");
        if (ctx == null) { err(resp, 401, "未登录"); return false; }
        if (!ctx.has("config:manage")) { err(resp, 403, "无权限"); return false; }
        return true;
    }

    @GetMapping("/api/console/agents")
    public Object list(HttpServletRequest q, HttpServletResponse resp) throws Exception {
        if (!guard(q, resp)) return null;
        var rows = Db.rows("SELECT * FROM agents ORDER BY sort ASC, id DESC");
        return Resp.ok(rows);
    }

    @PostMapping("/api/console/agents/save")
    public Object save(@RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) throws Exception {
        if (!guard(q, resp)) return null;
        long id = b.get("id") instanceof Number n ? n.longValue() : 0;
        String name = Svc.str(b.get("name")).trim();
        if (name.isEmpty()) return err(resp, 422, "名称不能为空");
        String desc = Svc.str(b.get("description"));
        String persona = Svc.str(b.get("persona"));
        String gender = Svc.str(b.get("gender"));
        String age = Svc.str(b.get("age"));
        String voiceEngine = Svc.str(b.get("voice_engine"));
        String voiceId = Svc.str(b.get("voice_id"));
        String modelHint = Svc.str(b.get("model_hint"));
        int sort = b.get("sort") instanceof Number n ? n.intValue() : 0;
        int status = b.get("status") instanceof Number n ? n.intValue() : 1;

        if (id > 0) {
            Db.upd("UPDATE agents SET name=?,description=?,persona=?,gender=?,age=?,voice_engine=?,voice_id=?,model_hint=?,sort=?,status=?,updated_at=NOW() WHERE id=?",
                    name, desc, persona, gender, age, voiceEngine, voiceId, modelHint, sort, status, id);
        } else {
            id = Db.ins("INSERT INTO agents(name,description,persona,gender,age,voice_engine,voice_id,model_hint,sort,status,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,NOW())",
                    name, desc, persona, gender, age, voiceEngine, voiceId, modelHint, sort, status);
        }
        logOp(q, "保存智能体", "/api/console/agents/save", "name=" + name);
        return Resp.ok("已保存", Resp.map("id", id));
    }

    @PostMapping("/api/console/agents/delete")
    public Object delete(@RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) throws Exception {
        if (!guard(q, resp)) return null;
        long id = b.get("id") instanceof Number n ? n.longValue() : 0;
        if (id <= 0) return err(resp, 422, "参数错误");
        Db.upd("DELETE FROM agents WHERE id=?", id);
        logOp(q, "删除智能体", "/api/console/agents/delete", "id=" + id);
        return Resp.ok("已删除", null);
    }

    /** App 端：登录用户拉取启用中的智能体模板 */
    @GetMapping("/api/ios/agents")
    public Object iosList(HttpServletRequest q) throws Exception {
        var rows = Db.rows("SELECT id,name,description,persona,gender,age,voice_engine,voice_id,model_hint FROM agents WHERE status=1 ORDER BY sort ASC, id DESC");
        return Resp.ok(rows);
    }
}
