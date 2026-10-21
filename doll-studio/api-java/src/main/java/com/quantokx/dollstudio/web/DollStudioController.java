package com.quantokx.dollstudio.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quantokx.dollstudio.auth.AuthInterceptor;
import com.quantokx.dollstudio.auth.TokenUtil;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

import java.io.IOException;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Doll Studio 3D 用户端 + 管理端接口
 * 端点（context-path=/api）：
 *   POST /auth/login            GET /dolls
 *   GET  /clothes/categories    GET /clothes[?category=|?id=]
 *   GET  /config                GET /assets
 *   GET|POST|DELETE /outfits[?id=]                       （Bearer）
 *   GET|POST /ai/outfits                                 （Bearer）
 *   POST /admin/login   GET|POST|DELETE /admin/clothes[?id=]
 *   GET|POST|DELETE /admin/dolls   GET|POST|DELETE /admin/categories[?key=]
 *   GET|POST /admin/ai-config      GET /admin/ai-logs    GET /admin/stats
 */
@RestController
public class DollStudioController {

    @Autowired private JdbcTemplate jdbc;
    @Autowired private AuthInterceptor auth;

    @Value("${dollstudio.token-secret}") private String tokenSecret;
    @Value("${dollstudio.uploads-dir}") private String uploadsDir;
    @Value("${dollstudio.rate-limit-per-minute:120}") private int rateLimit;

    private final ObjectMapper om = new ObjectMapper();
    private final BCryptPasswordEncoder bcrypt = new BCryptPasswordEncoder();
    private final RestTemplate http = new RestTemplate();

    /** 内存限流：ip → 秒级时间窗计数 */
    private final Map<String, int[]> rate = new ConcurrentHashMap<>();

    private Map<String, Object> ok(Map<String, Object> data) {
        Map<String, Object> m = new HashMap<>();
        m.put("ok", true);
        m.put("data", data);
        return m;
    }

    // 为了让代码直白：错误统一抛自定义异常
    public static class ApiError extends RuntimeException {
        public final int status;
        public ApiError(int status, String msg) { super(msg); this.status = status; }
    }

    @ExceptionHandler(ApiError.class)
    public ResponseEntity<Map<String, Object>> onApiError(ApiError e) {
        Map<String, Object> m = new HashMap<>();
        m.put("ok", false);
        m.put("error", e.getMessage());
        return ResponseEntity.status(e.status).body(m);
    }

    private void rateLimit() {
        String key = "global";
        long now = System.currentTimeMillis() / 1000;
        int[] win = rate.computeIfAbsent(key, k -> new int[]{(int) now, 0});
        if (win[0] != (int) now) { win[0] = (int) now; win[1] = 0; }
        if (++win[1] > rateLimit) throw new ApiError(429, "请求过于频繁，请稍后再试");
    }

    // ================= 公开接口 =================

    @GetMapping("/health")
    public Map<String, Object> health() {
        return ok(Map.of("service", "doll-studio-api", "time", new Date().toString()));
    }

    @PostMapping("/auth/login")
    public Map<String, Object> login(@RequestBody Map<String, Object> body) {
        String username = str(body.get("username"));
        String password = str(body.get("password"));
        if (username.isEmpty() || password.isEmpty()) throw new ApiError(400, "用户名和密码不能为空");
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT id, password_hash, nickname FROM users WHERE username = ?", username);
        if (rows.isEmpty() || !bcrypt.matches(password, (String) rows.get(0).get("password_hash")))
            throw new ApiError(401, "用户名或密码错误");
        long uid = ((Number) rows.get(0).get("id")).longValue();
        String nickname = (String) rows.get(0).get("nickname");
        return ok(Map.of("token", TokenUtil.issue(uid, tokenSecret),
                         "nickname", nickname == null || nickname.isEmpty() ? username : nickname));
    }

    @GetMapping("/dolls")
    public Map<String, Object> dolls() {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT id, name, gender, skin, height_scale, usdz_url FROM dolls WHERE enabled = 1 ORDER BY sort");
        List<Map<String, Object>> list = rows.stream().map(r -> Map.of(
                "id", r.get("id"), "name", r.get("name"), "gender", r.get("gender"),
                "skin", r.get("skin"), "height_scale", ((Number) r.get("height_scale")).doubleValue(),
                "url", r.get("usdz_url") == null ? "" : r.get("usdz_url"))).map(m -> (Map<String, Object>) new HashMap<String, Object>(m)).toList();
        return ok(Map.of("dolls", list));
    }

    @GetMapping("/clothes/categories")
    public Map<String, Object> categories() {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT `key`, title, sort FROM categories WHERE enabled = 1 ORDER BY sort");
        return ok(Map.of("categories", rows));
    }

    @GetMapping("/clothes")
    public Map<String, Object> clothes(@RequestParam(required = false) String category,
                                       @RequestParam(required = false) String id) {
        rateLimit();
        if (id != null && !id.isEmpty()) {
            List<Map<String, Object>> rows = jdbc.queryForList(
                    "SELECT id, name, category, kind, color, price, thumb_url, model_url, exclusive_group FROM clothes WHERE id = ? AND enabled = 1", id);
            if (rows.isEmpty()) throw new ApiError(404, "服装不存在");
            return ok(rows.get(0));
        }
        List<Map<String, Object>> rows;
        if (category != null && !category.isEmpty()) {
            rows = jdbc.queryForList("SELECT id, name, category, kind, color, price, thumb_url AS thumb, model_url, exclusive_group FROM clothes WHERE enabled = 1 AND category = ? ORDER BY sort", category);
        } else {
            rows = jdbc.queryForList("SELECT id, name, category, kind, color, price, thumb_url AS thumb, model_url, exclusive_group FROM clothes WHERE enabled = 1 ORDER BY category, sort");
        }
        return ok(Map.of("clothes", rows));
    }

    @GetMapping("/config")
    public Map<String, Object> config() {
        Map<String, Object> map = new HashMap<>();
        jdbc.queryForList("SELECT k, v FROM settings").forEach(r -> map.put((String) r.get("k"), r.get("v")));
        return ok(Map.of("config", map));
    }

    @GetMapping("/assets")
    public Map<String, Object> assets() throws IOException {
        List<Map<String, Object>> list = new ArrayList<>();
        Path dir = Path.of(uploadsDir);
        if (Files.isDirectory(dir)) {
            try (var walk = Files.walk(dir)) {
                walk.filter(Files::isRegularFile).forEach(f -> {
                    try {
                        list.add(Map.of("name", f.getFileName().toString(),
                                "size", Files.size(f),
                                "mtime", Files.getLastModifiedTime(f).toMillis()));
                    } catch (IOException ignored) {}
                });
            }
        }
        return ok(Map.of("assets", list,
                "note", "USDZ/GLB 模型与缩略图上传到 uploads 目录，通过 clothes.model_url/thumb_url 引用"));
    }

    // ================= 用户接口（Bearer） =================

    private long uid() {
        Long v = AuthInterceptor.CURRENT_USER.get();
        if (v == null) throw new ApiError(401, "未登录");
        return v;
    }

    @GetMapping("/outfits")
    public Map<String, Object> listOutfits() {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT id, name, doll_id, gender, skin, slots, created_at FROM outfits WHERE user_id = ? ORDER BY created_at DESC LIMIT 100", uid());
        rows.forEach(r -> r.put("slots", parseJson((String) r.get("slots"))));
        return ok(Map.of("outfits", rows));
    }

    @GetMapping("/outfits/detail")
    public Map<String, Object> outfitDetail(@RequestParam long id) {
        Map<String, Object> r = getOwnOutfit(id);
        r.put("slots", parseJson((String) r.get("slots")));
        return ok(r);
    }

    @PostMapping("/outfits")
    public Map<String, Object> saveOutfit(@RequestBody Map<String, Object> body) {
        String name = truncate(str(body.getOrDefault("name", "我的穿搭")), 64);
        String dollId = str(body.get("doll_id"));
        String gender = str(body.get("gender"));
        if (!List.of("male", "female", "neutral").contains(gender)) gender = "female";
        String skin = str(body.getOrDefault("skin", "#F3C6A5"));
        if (!skin.matches("^#[0-9A-Fa-f]{6}$")) skin = "#F3C6A5";
        Object slotsObj = body.get("slots");
        if (!(slotsObj instanceof Map) || ((Map<?, ?>) slotsObj).size() > 16)
            throw new ApiError(400, "slots 无效");
        String slotsJson = toJson(slotsObj);
        jdbc.update("INSERT INTO outfits (user_id, name, doll_id, gender, skin, slots) VALUES (?,?,?,?,?,?)",
                uid(), name, dollId, gender, skin, slotsJson);
        return ok(Map.of("id", jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class)));
    }

    @DeleteMapping("/outfits")
    public Map<String, Object> deleteOutfit(@RequestParam long id) {
        int n = jdbc.update("DELETE FROM outfits WHERE id = ? AND user_id = ?", id, uid());
        return ok(Map.of("deleted", n));
    }

    // ================= AI（Bearer，Key 仅服务端） =================

    @GetMapping("/ai/outfits")
    public Map<String, Object> aiInfo() {
        return ok(Map.of("message", "POST {gender, prompt, catalog} 生成 AI 搭配"));
    }

    @PostMapping("/ai/outfits")
    public Map<String, Object> aiOutfit(@RequestBody Map<String, Object> body) {
        rateLimit();
        long userId = uid();
        String gender = str(body.getOrDefault("gender", "female"));
        if (!List.of("male", "female", "neutral").contains(gender)) gender = "female";
        String prompt = truncate(str(body.getOrDefault("prompt", "")), 200);
        if (prompt.isEmpty()) throw new ApiError(400, "prompt 不能为空");
        Object catalog = body.get("catalog");
        if (!(catalog instanceof List)) throw new ApiError(400, "catalog 必须是数组");

        Map<String, Object> cfg = aiConfig();

        // 拼系统提示词：只允许真实存在的服装
        StringBuilder catText = new StringBuilder();
        for (Object o : (List<?>) catalog) {
            if (!(o instanceof Map)) continue;
            Map<?, ?> c = (Map<?, ?>) o;
            String cid = str(c.get("id"));
            if (cid.isEmpty()) continue;
            catText.append("- ").append(cid).append(" | ").append(c.get("category")).append(" | ")
                   .append(c.get("name")).append('\n');
        }
        String sys = """
                你是 Doll Studio 3D 的穿搭师。玩偶性别：%s。
                只能从以下真实存在的服装里选（格式：id | 分类 | 名称）：
                %s
                输出严格 JSON：{"items":[{"category":"分类","cloth_id":"id"}, ...],"reason":"50字内理由"}
                规则：每个分类最多 1 件；上衣/下装/鞋子必须有；cloth_id 必须来自上面的列表；帽类互斥只选 1 顶。
                """.formatted(gender, catText);

        long t0 = System.currentTimeMillis();
        String content = callLLM(cfg, sys, prompt);
        int latency = (int) (System.currentTimeMillis() - t0);

        Map<String, Object> plan;
        try {
            plan = om.readValue(content, Map.class);
        } catch (Exception e) {
            logAI(userId, prompt, (String) cfg.get("model"), "error", latency, "JSON 解析失败");
            throw new ApiError(502, "AI 返回格式无法解析");
        }

        // 服务端二次校验：只保留真实存在且启用的服装
        List<Map<String, Object>> valid = new ArrayList<>();
        Object items = plan.get("items");
        if (items instanceof List<?> list) {
            for (Object o : list) {
                if (!(o instanceof Map)) continue;
                String cid = str(((Map<?, ?>) o).get("cloth_id"));
                if (cid.isEmpty()) continue;
                List<Map<String, Object>> hit = jdbc.queryForList(
                        "SELECT id, category FROM clothes WHERE id = ? AND enabled = 1", cid);
                if (!hit.isEmpty()) {
                    valid.add(Map.of("category", hit.get(0).get("category"), "cloth_id", hit.get(0).get("id")));
                }
            }
        }
        logAI(userId, prompt, (String) cfg.get("model"), "ok", latency, null);
        return ok(Map.of("items", valid,
                         "reason", String.valueOf(plan.getOrDefault("reason", "")),
                         "source", "server-ai"));
    }

    private Map<String, Object> aiConfig() {
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT * FROM ai_config WHERE id = 1");
        if (rows.isEmpty()) throw new ApiError(503, "AI 功能未开启");
        Map<String, Object> cfg = rows.get(0);
        if (!Objects.equals(cfg.get("enabled"), (Object) 1) && !Boolean.TRUE.equals(cfg.get("enabled")))
            throw new ApiError(503, "AI 功能未开启");
        String key = (String) cfg.get("api_key");
        if (key == null || key.isEmpty()) throw new ApiError(503, "AI 未配置（请在管理后台配置 API Key）");
        Integer used = jdbc.queryForObject(
                "SELECT COUNT(*) FROM ai_logs WHERE status = 'ok' AND created_at >= CURDATE()", Integer.class);
        int limit = ((Number) cfg.get("daily_limit")).intValue();
        if (used != null && used >= limit) throw new ApiError(429, "今日 AI 调用已达上限");
        return cfg;
    }

    @SuppressWarnings("unchecked")
    private String callLLM(Map<String, Object> cfg, String sys, String prompt) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.setBearerAuth((String) cfg.get("api_key"));
            Map<String, Object> payload = Map.of(
                    "model", cfg.get("model"),
                    "temperature", 0.4,
                    "response_format", Map.of("type", "json_object"),
                    "messages", List.of(
                            Map.of("role", "system", "content", sys),
                            Map.of("role", "user", "content", prompt)));
            ResponseEntity<Map> resp = http.postForEntity(
                    trimSlash((String) cfg.get("api_base")) + "/chat/completions",
                    new HttpEntity<>(payload, headers), Map.class);
            if (!resp.getStatusCode().is2xxSuccessful())
                throw new ApiError(502, "AI 服务 HTTP " + resp.getStatusCode().value());
            List<Map<String, Object>> choices = (List<Map<String, Object>>) resp.getBody().get("choices");
            if (choices == null || choices.isEmpty())
                throw new ApiError(502, "AI 空响应");
            Map<String, Object> message = (Map<String, Object>) choices.get(0).get("message");
            return (String) message.get("content");
        } catch (ApiError e) {
            throw e;
        } catch (Exception e) {
            throw new ApiError(502, "AI 调用失败：" + e.getMessage());
        }
    }

    private void logAI(long userId, String prompt, String model, String status, int latency, String err) {
        try {
            jdbc.update("INSERT INTO ai_logs (user_id, endpoint, prompt, model, status, latency_ms, error_msg) VALUES (?,?,?,?,?,?,?)",
                    userId, "outfit", truncate(prompt, 500), model, status, latency, err);
        } catch (Exception ignored) {}
    }

    // ================= 管理端 =================

    @PostMapping("/admin/login")
    public Map<String, Object> adminLogin(@RequestBody Map<String, Object> body) {
        String username = str(body.get("username"));
        String password = str(body.get("password"));
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT id, password_hash FROM admins WHERE username = ?", username);
        if (rows.isEmpty() || !bcrypt.matches(password, (String) rows.get(0).get("password_hash")))
            throw new ApiError(401, "用户名或密码错误");
        long adminId = ((Number) rows.get(0).get("id")).longValue();
        adminLog(adminId, "login", username);
        // 管理员 token：uid 取负（拦截器判定负数 = 管理员）
        return ok(Map.of("token", TokenUtil.issue(-adminId, tokenSecret)));
    }

    @GetMapping("/admin/clothes")
    public Map<String, Object> adminClothes(@RequestParam(required = false) String category) {
        List<Map<String, Object>> rows = category == null || category.isEmpty()
                ? jdbc.queryForList("SELECT * FROM clothes ORDER BY category, sort")
                : jdbc.queryForList("SELECT * FROM clothes WHERE category = ? ORDER BY sort", category);
        return ok(Map.of("clothes", rows));
    }

    @PostMapping("/admin/clothes")
    public Map<String, Object> saveCloth(@RequestBody Map<String, Object> body) {
        String id = str(body.get("id"));
        if (id.isEmpty()) throw new ApiError(400, "id 必填");
        jdbc.update("""
            INSERT INTO clothes (id, name, category, kind, color, price, thumb_url, model_url, exclusive_group, sort, enabled)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE name=VALUES(name), category=VALUES(category), kind=VALUES(kind),
              color=VALUES(color), price=VALUES(price), thumb_url=VALUES(thumb_url),
              model_url=VALUES(model_url), exclusive_group=VALUES(exclusive_group),
              sort=VALUES(sort), enabled=VALUES(enabled)
            """,
                id, str(body.getOrDefault("name", id)), str(body.getOrDefault("category", "other")),
                str(body.getOrDefault("kind", "tee")), str(body.getOrDefault("color", "#888888")),
                num(body.get("price")), str(body.get("thumb_url")), str(body.get("model_url")),
                str(body.get("exclusive_group")), (int) num(body.getOrDefault("sort", 0)),
                (int) num(body.getOrDefault("enabled", 1)));
        adminLog(-AuthInterceptor.CURRENT_USER.get(), "save_cloth", id);
        return ok(Map.of("id", id));
    }

    @DeleteMapping("/admin/clothes")
    public Map<String, Object> deleteCloth(@RequestParam String id) {
        jdbc.update("DELETE FROM clothes WHERE id = ?", id);
        adminLog(-AuthInterceptor.CURRENT_USER.get(), "delete_cloth", id);
        return ok(Map.of("deleted", id));
    }

    @GetMapping("/admin/dolls")
    public Map<String, Object> adminDolls() {
        return ok(Map.of("dolls", jdbc.queryForList("SELECT * FROM dolls ORDER BY sort")));
    }

    @PostMapping("/admin/dolls")
    public Map<String, Object> saveDoll(@RequestBody Map<String, Object> body) {
        String id = str(body.get("id"));
        if (id.isEmpty()) throw new ApiError(400, "id 必填");
        jdbc.update("""
            INSERT INTO dolls (id, name, gender, skin, height_scale, usdz_url, sort, enabled)
            VALUES (?,?,?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE name=VALUES(name), gender=VALUES(gender), skin=VALUES(skin),
              height_scale=VALUES(height_scale), usdz_url=VALUES(usdz_url),
              sort=VALUES(sort), enabled=VALUES(enabled)
            """,
                id, str(body.getOrDefault("name", id)), str(body.getOrDefault("gender", "female")),
                str(body.getOrDefault("skin", "#F3C6A5")), num(body.getOrDefault("height_scale", 1.0)),
                str(body.get("usdz_url")), (int) num(body.getOrDefault("sort", 0)),
                (int) num(body.getOrDefault("enabled", 1)));
        return ok(Map.of("id", id));
    }

    @DeleteMapping("/admin/dolls")
    public Map<String, Object> deleteDoll(@RequestParam String id) {
        jdbc.update("DELETE FROM dolls WHERE id = ?", id);
        return ok(Map.of("deleted", id));
    }

    @GetMapping("/admin/categories")
    public Map<String, Object> adminCategories() {
        return ok(Map.of("categories", jdbc.queryForList("SELECT * FROM categories ORDER BY sort")));
    }

    @PostMapping("/admin/categories")
    public Map<String, Object> saveCategory(@RequestBody Map<String, Object> body) {
        String key = str(body.get("key"));
        if (key.isEmpty()) throw new ApiError(400, "key 必填");
        jdbc.update("INSERT INTO categories (`key`, title, sort, enabled) VALUES (?,?,?,?) " +
                        "ON DUPLICATE KEY UPDATE title=VALUES(title), sort=VALUES(sort), enabled=VALUES(enabled)",
                key, str(body.getOrDefault("title", key)), (int) num(body.getOrDefault("sort", 0)),
                (int) num(body.getOrDefault("enabled", 1)));
        return ok(Map.of("key", key));
    }

    @DeleteMapping("/admin/categories")
    public Map<String, Object> deleteCategory(@RequestParam String key) {
        jdbc.update("UPDATE categories SET enabled = 0 WHERE `key` = ?", key); // 软删，避免外键破坏
        return ok(Map.of("disabled", key));
    }

    @GetMapping("/admin/ai-config")
    public Map<String, Object> aiConfigGet() {
        Map<String, Object> cfg = jdbc.queryForList("SELECT * FROM ai_config WHERE id = 1").stream().findFirst().orElse(Map.of());
        // 脱敏：不回传完整 Key
        Map<String, Object> safe = new HashMap<>(cfg);
        String key = (String) safe.get("api_key");
        safe.put("api_key_masked", key == null || key.length() < 8 ? "" : key.substring(0, 4) + "****");
        safe.remove("api_key");
        return ok(safe);
    }

    @PostMapping("/admin/ai-config")
    public Map<String, Object> aiConfigSet(@RequestBody Map<String, Object> body) {
        jdbc.update("""
            UPDATE ai_config SET api_base=?, api_key=COALESCE(NULLIF(?,''), api_key), model=?,
              timeout_sec=?, max_retries=?, daily_limit=?, enabled=? WHERE id = 1
            """,
                str(body.getOrDefault("api_base", "https://api.openai.com/v1")),
                str(body.getOrDefault("api_key", "")),
                str(body.getOrDefault("model", "gpt-4o-mini")),
                (int) num(body.getOrDefault("timeout_sec", 20)),
                (int) num(body.getOrDefault("max_retries", 2)),
                (int) num(body.getOrDefault("daily_limit", 1000)),
                (int) num(body.getOrDefault("enabled", 1)));
        return ok(Map.of("saved", true));
    }

    @GetMapping("/admin/ai-logs")
    public Map<String, Object> aiLogs(@RequestParam(defaultValue = "50") int limit) {
        int n = Math.min(Math.max(limit, 1), 200);
        return ok(Map.of("logs", jdbc.queryForList(
                "SELECT id, user_id, endpoint, prompt, model, status, latency_ms, error_msg, created_at FROM ai_logs ORDER BY created_at DESC LIMIT ?", n)));
    }

    @GetMapping("/admin/stats")
    public Map<String, Object> stats() {
        return ok(Map.of(
                "users", count("SELECT COUNT(*) FROM users"),
                "clothes", count("SELECT COUNT(*) FROM clothes WHERE enabled = 1"),
                "outfits", count("SELECT COUNT(*) FROM outfits"),
                "ai_calls_today", count("SELECT COUNT(*) FROM ai_logs WHERE created_at >= CURDATE()")));
    }

    private long count(String sql) {
        Long v = jdbc.queryForObject(sql, Long.class);
        return v == null ? 0 : v;
    }

    // ================= 工具 =================

    private Map<String, Object> getOwnOutfit(long id) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT id, name, doll_id, gender, skin, slots, created_at FROM outfits WHERE id = ? AND user_id = ?", id, uid());
        if (rows.isEmpty()) throw new ApiError(404, "作品不存在");
        return rows.get(0);
    }

    private Object parseJson(String s) {
        try { return om.readValue(s == null ? "{}" : s, Object.class); }
        catch (Exception e) { return Map.of(); }
    }

    private String toJson(Object o) {
        try { return om.writeValueAsString(o); }
        catch (Exception e) { return "{}"; }
    }

    private void adminLog(long adminId, String action, String detail) {
        try {
            jdbc.update("INSERT INTO admin_logs (admin_id, action, detail) VALUES (?,?,?)", adminId, action, detail);
        } catch (Exception ignored) {}
    }

    private String str(Object o) { return o == null ? "" : String.valueOf(o); }

    private double num(Object o) {
        if (o instanceof Number n) return n.doubleValue();
        try { return Double.parseDouble(String.valueOf(o)); } catch (Exception e) { return 0; }
    }

    private String truncate(String s, int n) { return s == null ? "" : s.substring(0, Math.min(s.length(), n)); }

    private String trimSlash(String s) { return s.endsWith("/") ? s.substring(0, s.length() - 1) : s; }
}
