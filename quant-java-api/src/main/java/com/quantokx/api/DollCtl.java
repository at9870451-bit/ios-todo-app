package com.quantokx.api;

import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.util.*;

/**
 * Doll Studio 3D —— iOS 玩偶换装接口（/api/doll/**，需登录会话）。
 * 目录由 doll_categories / doll_items 驱动（管理台维护，SchemaBoot 已内置种子）；
 * AI 推荐复用 ChatCtl.callAI（密钥只存在服务端），调用全程写 doll_ai_logs 审计。
 */
@RestController
@RequestMapping("/api/doll")
public class DollCtl {

    Long uid(HttpServletRequest q) { return (Long) q.getAttribute("uid"); }

    static long num(Object o) { return o instanceof Number n ? n.longValue() : 0; }
    static double dbl(Object o, double d) {
        if (o instanceof Number n) return n.doubleValue();
        try { return Double.parseDouble(String.valueOf(o)); } catch (Exception e) { return d; }
    }

    // ============================ 目录 ============================

    /** 服装目录：分类 + 条目（仅启用，App 离线时有内置兜底） */
    @GetMapping("/catalog")
    public Object catalog() {
        var cats = Db.rows("SELECT code,name,sort FROM doll_categories WHERE enabled=1 ORDER BY sort ASC, id ASC");
        for (var c : cats) c.put("sort", (int) num(c.get("sort")));
        var items = Db.rows("SELECT id,category,name,style,color,premium,model_url,model_scale,model_offset_y " +
                "FROM doll_items WHERE enabled=1 ORDER BY sort ASC, id ASC");
        for (var it : items) {
            it.put("id", num(it.get("id")));
            it.put("premium", num(it.get("premium")) == 1);
            it.put("model_scale", dbl(it.get("model_scale"), 1.0));
            it.put("model_offset_y", dbl(it.get("model_offset_y"), 0.0));
            String mu = Svc.str(it.get("model_url"));
            it.put("model_url", mu.isEmpty() ? null : mu);
        }
        return Resp.ok(Resp.map("categories", cats, "items", items));
    }

    // ============================ 穿搭记录 ============================

    @GetMapping("/outfits")
    public Object outfits(HttpServletRequest q) {
        long uid = uid(q);
        var rows = Db.rows("SELECT id,name,gender,skin,state,favorite,created_at,updated_at FROM doll_outfits " +
                "WHERE user_id=? ORDER BY updated_at DESC, id DESC LIMIT 100", uid);
        for (var r : rows) {
            r.put("id", num(r.get("id")));
            r.put("favorite", num(r.get("favorite")) == 1);
        }
        return Resp.ok(rows);
    }

    @PostMapping("/outfits")
    public Object saveOutfit(@RequestBody Map<String, Object> b, HttpServletRequest q, HttpServletResponse resp) {
        long uid = uid(q);
        String name = Svc.str(b.get("name")).trim();
        String gender = Svc.str(b.get("gender"));
        String skin = Svc.str(b.get("skin"));
        String state = Svc.str(b.get("state"));
        if (name.isEmpty()) name = "未命名搭配";
        if (name.length() > 24) name = name.substring(0, 24);
        if (!gender.matches("male|female|neutral")) gender = "neutral";
        if (!skin.matches("^#[0-9A-Fa-f]{6}$")) skin = "#F6D7BE";
        if (state.isEmpty() || state.length() > 8000) {
            resp.setStatus(422);
            return Resp.map("code", "INVALID_PARAM", "message", "搭配数据无效或过大", "data", null);
        }
        long count = num(Db.scalar("SELECT COUNT(*) FROM doll_outfits WHERE user_id=?", uid));
        if (count >= 60) {
            resp.setStatus(422);
            return Resp.map("code", "LIMIT_REACHED", "message", "最多保存 60 套穿搭，请先删除旧的", "data", null);
        }
        long id = Db.ins("INSERT INTO doll_outfits(user_id,name,gender,skin,state,favorite,created_at,updated_at) " +
                "VALUES(?,?,?,?,?,0,NOW(),NOW())", uid, name, gender, skin, state);
        return Resp.ok("已保存", Resp.map("id", id));
    }

    @PostMapping("/outfits/delete")
    public Object deleteOutfit(@RequestBody Map<String, Object> b, HttpServletRequest q) {
        long uid = uid(q);
        long id = b.get("id") instanceof Number n ? n.longValue() : 0;
        Db.upd("DELETE FROM doll_outfits WHERE id=? AND user_id=?", id, uid);
        return Resp.ok("已删除", null);
    }

    @PostMapping("/outfits/favorite")
    public Object favorite(@RequestBody Map<String, Object> b, HttpServletRequest q) {
        long uid = uid(q);
        long id = b.get("id") instanceof Number n ? n.longValue() : 0;
        boolean fav = Boolean.TRUE.equals(b.get("favorite")) || "1".equals(Svc.str(b.get("favorite"))) || "true".equalsIgnoreCase(Svc.str(b.get("favorite")));
        Db.upd("UPDATE doll_outfits SET favorite=?, updated_at=NOW() WHERE id=? AND user_id=?", fav ? 1 : 0, id, uid);
        return Resp.ok(fav ? "已收藏" : "已取消收藏", null);
    }

    // ============================ AI 穿搭推荐 ============================

    /**
     * AI 推荐：用户描述风格 → 服务端组装目录并调用 AI → 校验款式 → 返回 {items, reason}。
     * 频控：30 次/天/用户；失败路径也落库，管理台可查。
     */
    @PostMapping("/ai/recommend")
    public Object aiRecommend(@RequestBody Map<String, Object> b, HttpServletRequest q) {
        long uid = uid(q);
        String prompt = Svc.str(b.get("prompt")).trim();
        String gender = Svc.str(b.get("gender"));
        if (!gender.matches("male|female|neutral")) gender = "neutral";
        if (prompt.isEmpty()) {
            return Resp.map("code", "INVALID_PARAM", "message", "请描述你想要的穿搭风格", "data", null);
        }
        if (prompt.length() > 200) prompt = prompt.substring(0, 200);

        long today = num(Db.scalar("SELECT COUNT(*) FROM doll_ai_logs WHERE user_id=? AND status='ok' AND created_at>=CURDATE()", uid));
        if (today >= 30) {
            return Resp.map("code", "RATE_LIMIT", "message", "今日推荐次数已达上限（30 次/天）", "data", null);
        }

        long t0 = System.currentTimeMillis();
        try {
            var cfg = aiConfig(uid);
            if (cfg == null) {
                log(uid, prompt, "", "error", "未配置 AI 接口", (int) (System.currentTimeMillis() - t0));
                return Resp.map("code", "AI_NO_CONFIG", "message", "服务端未配置 AI 接口，请先在「对话」页配置可用的 AI", "data", null);
            }
            String reply = ChatCtl.callAI(cfg, DollSvc.buildMessages(gender, prompt), "");
            Map<String, Object> out = DollSvc.parseRecommend(reply);
            int ms = (int) (System.currentTimeMillis() - t0);
            if (out == null) {
                log(uid, prompt, reply, "error", "AI 返回格式无法解析", ms);
                return Resp.map("code", "AI_PARSE", "message", "AI 返回的搭配无法解析，请重试或换个描述", "data", null);
            }
            log(uid, prompt, reply, "ok", "", ms);
            return Resp.ok(out);
        } catch (Exception e) {
            log(uid, prompt, "", "error", e.getMessage(), (int) (System.currentTimeMillis() - t0));
            return Resp.map("code", "AI_ERROR", "message", e.getMessage(), "data", null);
        }
    }

    /** AI 配置来源：优先用户 chat 配置，其次任意启用的配置（密钥保存在服务端，绝不下发） */
    static Map<String, Object> aiConfig(long uid) {
        var cfg = Db.one("SELECT * FROM ai_configs WHERE user_id=? AND enabled=1 AND mode='chat' ORDER BY id DESC LIMIT 1", uid);
        if (cfg == null) cfg = Db.one("SELECT * FROM ai_configs WHERE user_id=? AND enabled=1 ORDER BY id DESC LIMIT 1", uid);
        return cfg;
    }

    static void log(long uid, String prompt, String result, String status, String message, int ms) {
        try {
            String r = result == null ? "" : result.substring(0, Math.min(result.length(), 4000));
            String m = message == null ? "" : message.substring(0, Math.min(message.length(), 400));
            Db.upd("INSERT INTO doll_ai_logs(user_id,prompt,result,status,message,duration_ms) VALUES(?,?,?,?,?,?)",
                    uid, prompt, r, status, m, ms);
        } catch (Exception ignore) { }
    }
}
