package com.quantokx.api;

import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import jakarta.servlet.http.HttpServletResponse;
import java.nio.file.*;
import java.util.*;

/**
 * Doll Studio 3D —— 管理台接口（/api/console/doll/**，JWT + doll:manage 权限）。
 * 覆盖：服装分类/款式管理、3D 模型文件上传、用户穿搭记录、AI 调用日志、AI 配置（掩码）。
 */
@RestController
@RequestMapping("/api/console/doll")
public class DollAdminCtl {

    static long num(Object o) { return o instanceof Number n ? n.longValue() : 0; }

    static String str(Map<String, Object> b, String k) { return b == null ? "" : Svc.str(b.get(k)); }

    static boolean flag(Map<String, Object> b, String k, boolean def) {
        if (b == null || !b.containsKey(k)) return def;
        Object v = b.get(k);
        if (v instanceof Boolean bb) return bb;
        String s = Svc.str(v);
        if (s.equals("1") || s.equalsIgnoreCase("true")) return true;
        if (s.equals("0") || s.equalsIgnoreCase("false")) return false;
        return def;
    }

    // ============================ 概览 ============================

    @GetMapping("/meta")
    public Object meta() {
        return Resp.ok(Resp.map(
            "categories", num(Db.scalar("SELECT COUNT(*) FROM doll_categories")),
            "items", num(Db.scalar("SELECT COUNT(*) FROM doll_items")),
            "enabled_items", num(Db.scalar("SELECT COUNT(*) FROM doll_items WHERE enabled=1")),
            "outfits", num(Db.scalar("SELECT COUNT(*) FROM doll_outfits")),
            "favorites", num(Db.scalar("SELECT COUNT(*) FROM doll_outfits WHERE favorite=1")),
            "ai_calls", num(Db.scalar("SELECT COUNT(*) FROM doll_ai_logs")),
            "ai_errors", num(Db.scalar("SELECT COUNT(*) FROM doll_ai_logs WHERE status='error'")),
            "styles", DollSvc.STYLES
        ));
    }

    // ============================ 服装分类 ============================

    @GetMapping("/categories")
    public Object categories() {
        var rows = Db.rows("SELECT id,code,name,sort,enabled,created_at FROM doll_categories ORDER BY sort ASC, id ASC");
        for (var r : rows) {
            r.put("id", num(r.get("id")));
            r.put("sort", (int) num(r.get("sort")));
            r.put("enabled", num(r.get("enabled")) == 1);
            r.put("item_count", num(Db.scalar("SELECT COUNT(*) FROM doll_items WHERE category=?", Svc.str(r.get("code")))));
        }
        return Resp.ok(Resp.map("items", rows));
    }

    @PutMapping("/categories/{id}")
    public Object updateCategory(@PathVariable long id, @RequestBody Map<String, Object> b, HttpServletResponse resp) {
        var old = Db.one("SELECT id,code FROM doll_categories WHERE id=?", id);
        if (old == null) { resp.setStatus(404); return Resp.map("code", "NOT_FOUND", "message", "分类不存在", "data", null); }
        String name = str(b, "name").trim();
        if (name.isEmpty() || name.length() > 20) { resp.setStatus(422); return Resp.map("code", "INVALID", "message", "分类名需 1~20 字", "data", null); }
        Db.upd("UPDATE doll_categories SET name=?, sort=?, enabled=? WHERE id=?",
                name, (int) Svc.num(b.get("sort"), 0), flag(b, "enabled", true) ? 1 : 0, id);
        return Resp.ok("已更新", null);
    }

    // ============================ 服装款式 / 3D 模型 ============================

    @GetMapping("/items")
    public Object items(@RequestParam(defaultValue = "1") int page,
                        @RequestParam(defaultValue = "50") int size,
                        @RequestParam(required = false) String category,
                        @RequestParam(required = false) String keyword) {
        StringBuilder w = new StringBuilder(" WHERE 1=1");
        List<Object> args = new ArrayList<>();
        if (category != null && !category.isBlank()) { w.append(" AND category=?"); args.add(category.trim()); }
        if (keyword != null && !keyword.isBlank()) { w.append(" AND name LIKE ?"); args.add("%" + keyword.trim() + "%"); }
        long total = num(Db.scalar("SELECT COUNT(*) FROM doll_items" + w, args.toArray()));
        List<Object> pa = new ArrayList<>(args);
        pa.add(size);
        pa.add((long) (page - 1) * size);
        var rows = Db.rows("SELECT id,category,name,style,color,premium,sort,enabled,model_url,model_scale,model_offset_y,created_at " +
                "FROM doll_items" + w + " ORDER BY category ASC, sort ASC, id ASC LIMIT ? OFFSET ?", pa.toArray());
        for (var r : rows) normalizeItem(r);
        return Resp.ok(Resp.map("total", total, "page", page, "size", size, "items", rows));
    }

    private static void normalizeItem(Map<String, Object> r) {
        r.put("id", num(r.get("id")));
        r.put("premium", num(r.get("premium")) == 1);
        r.put("enabled", num(r.get("enabled")) == 1);
        r.put("sort", (int) num(r.get("sort")));
        r.put("model_scale", Svc.num(r.get("model_scale"), 1));
        r.put("model_offset_y", Svc.num(r.get("model_offset_y"), 0));
        String mu = Svc.str(r.get("model_url"));
        r.put("model_url", mu.isEmpty() ? null : mu);
    }

    private static String validateItem(Map<String, Object> b, Long selfId) {
        String category = str(b, "category");
        String style = str(b, "style");
        String name = str(b, "name").trim();
        String color = str(b, "color").trim();
        if (!DollSvc.STYLES.containsKey(category)) return "无效分类：" + category;
        if (!DollSvc.validStyle(category, style)) return "无效款式：" + style;
        if (name.isEmpty() || name.length() > 20) return "名称需 1~20 字";
        if (!color.matches("^#[0-9A-Fa-f]{6}$")) return "颜色需 #RRGGBB 格式";
        String modelUrl = str(b, "model_url").trim();
        if (!modelUrl.isEmpty() && !modelUrl.startsWith("/doll-assets/") && !modelUrl.startsWith("http")) return "模型地址需为 /doll-assets/ 或 http(s) 链接";
        Long dup = null;
        Object v = Db.scalar("SELECT id FROM doll_items WHERE category=? AND style=?", category, style);
        if (v instanceof Number n) dup = n.longValue();
        if (dup != null && (selfId == null || dup != selfId)) return "该分类下此款式已存在";
        return null;
    }

    @PostMapping("/items")
    public Object createItem(@RequestBody Map<String, Object> b, HttpServletResponse resp) {
        String err = validateItem(b, null);
        if (err != null) { resp.setStatus(422); return Resp.map("code", "INVALID", "message", err, "data", null); }
        long id = Db.ins("INSERT INTO doll_items(category,name,style,color,premium,sort,enabled,model_url,model_scale,model_offset_y) VALUES(?,?,?,?,?,?,?,?,?,?)",
                str(b, "category"), str(b, "name").trim(), str(b, "style"), str(b, "color").trim(),
                flag(b, "premium", false) ? 1 : 0, (int) Svc.num(b.get("sort"), 0), flag(b, "enabled", true) ? 1 : 0,
                emptyNull(str(b, "model_url")), Svc.num(b.get("model_scale"), 1), Svc.num(b.get("model_offset_y"), 0));
        return Resp.ok("已创建", Resp.map("id", id));
    }

    @PutMapping("/items/{id}")
    public Object updateItem(@PathVariable long id, @RequestBody Map<String, Object> b, HttpServletResponse resp) {
        var old = Db.one("SELECT * FROM doll_items WHERE id=?", id);
        if (old == null) { resp.setStatus(404); return Resp.map("code", "NOT_FOUND", "message", "条目不存在", "data", null); }
        Map<String, Object> merged = new LinkedHashMap<>();
        merged.put("category", b.containsKey("category") ? str(b, "category") : Svc.str(old.get("category")));
        merged.put("style", b.containsKey("style") ? str(b, "style") : Svc.str(old.get("style")));
        merged.put("name", b.containsKey("name") ? str(b, "name") : Svc.str(old.get("name")));
        merged.put("color", b.containsKey("color") ? str(b, "color") : Svc.str(old.get("color")));
        merged.put("model_url", b.containsKey("model_url") ? str(b, "model_url") : Svc.str(old.get("model_url")));
        String err = validateItem(merged, id);
        if (err != null) { resp.setStatus(422); return Resp.map("code", "INVALID", "message", err, "data", null); }
        Db.upd("UPDATE doll_items SET category=?, name=?, style=?, color=?, premium=?, sort=?, enabled=?, model_url=?, model_scale=?, model_offset_y=? WHERE id=?",
                merged.get("category"), Svc.str(merged.get("name")).trim(), merged.get("style"), Svc.str(merged.get("color")).trim(),
                flag(b, "premium", num(old.get("premium")) == 1) ? 1 : 0,
                (int) Svc.num(b.get("sort"), Svc.num(old.get("sort"), 0)),
                flag(b, "enabled", num(old.get("enabled")) == 1) ? 1 : 0,
                emptyNull(Svc.str(merged.get("model_url")).trim()),
                Svc.num(b.get("model_scale"), Svc.num(old.get("model_scale"), 1)),
                Svc.num(b.get("model_offset_y"), Svc.num(old.get("model_offset_y"), 0)),
                id);
        return Resp.ok("已更新", null);
    }

    @DeleteMapping("/items/{id}")
    public Object deleteItem(@PathVariable long id) {
        Db.upd("DELETE FROM doll_items WHERE id=?", id);
        return Resp.ok("已删除", null);
    }

    /** 3D 模型上传：.usdz/.glb/.gltf/.reality ≤30MB，存 data/doll-models/，经 /doll-assets/** 静态下发 */
    @PostMapping("/upload")
    public Object upload(@RequestParam("file") MultipartFile file, HttpServletResponse resp) throws Exception {
        if (file == null || file.isEmpty()) { resp.setStatus(422); return Resp.map("code", "INVALID", "message", "请选择文件", "data", null); }
        String orig = file.getOriginalFilename() == null ? "model.usdz" : file.getOriginalFilename();
        String lower = orig.toLowerCase();
        String ext = lower.endsWith(".usdz") ? "usdz" : lower.endsWith(".glb") ? "glb" : lower.endsWith(".gltf") ? "gltf" : lower.endsWith(".reality") ? "reality" : null;
        if (ext == null) { resp.setStatus(422); return Resp.map("code", "INVALID", "message", "仅支持 .usdz / .glb / .gltf / .reality", "data", null); }
        if (file.getSize() > 30L * 1024 * 1024) { resp.setStatus(422); return Resp.map("code", "INVALID", "message", "文件超过 30MB", "data", null); }
        Path dir = Paths.get(System.getProperty("user.dir"), "data", "doll-models");
        Files.createDirectories(dir);
        String name = System.currentTimeMillis() + "-" + Integer.toHexString(orig.hashCode()) + "." + ext;
        file.transferTo(dir.resolve(name).toFile());
        return Resp.ok("上传成功", Resp.map("url", "/doll-assets/" + name, "name", orig, "size", file.getSize()));
    }

    private static String emptyNull(String s) { return s == null || s.isBlank() ? null : s; }

    // ============================ 用户穿搭记录 ============================

    @GetMapping("/outfits")
    public Object outfits(@RequestParam(defaultValue = "1") int page,
                          @RequestParam(defaultValue = "20") int size,
                          @RequestParam(required = false) String keyword) {
        StringBuilder w = new StringBuilder(" WHERE 1=1");
        List<Object> args = new ArrayList<>();
        if (keyword != null && !keyword.isBlank()) {
            w.append(" AND (o.name LIKE ? OR u.username LIKE ?)");
            String k = "%" + keyword.trim() + "%";
            args.add(k); args.add(k);
        }
        long total = num(Db.scalar("SELECT COUNT(*) FROM doll_outfits o LEFT JOIN users u ON u.id=o.user_id" + w, args.toArray()));
        List<Object> pa = new ArrayList<>(args);
        pa.add(size);
        pa.add((long) (page - 1) * size);
        var rows = Db.rows("SELECT o.id,o.user_id,u.username,o.name,o.gender,o.skin,o.state,o.favorite,o.created_at,o.updated_at " +
                "FROM doll_outfits o LEFT JOIN users u ON u.id=o.user_id" + w + " ORDER BY o.updated_at DESC, o.id DESC LIMIT ? OFFSET ?", pa.toArray());
        for (var r : rows) {
            r.put("id", num(r.get("id")));
            r.put("user_id", num(r.get("user_id")));
            r.put("favorite", num(r.get("favorite")) == 1);
        }
        return Resp.ok(Resp.map("total", total, "page", page, "size", size, "items", rows));
    }

    @DeleteMapping("/outfits/{id}")
    public Object deleteOutfit(@PathVariable long id) {
        Db.upd("DELETE FROM doll_outfits WHERE id=?", id);
        return Resp.ok("已删除", null);
    }

    // ============================ AI 调用日志 / 配置 ============================

    @GetMapping("/ai-logs")
    public Object aiLogs(@RequestParam(defaultValue = "1") int page,
                         @RequestParam(defaultValue = "20") int size,
                         @RequestParam(required = false) String status) {
        StringBuilder w = new StringBuilder(" WHERE 1=1");
        List<Object> args = new ArrayList<>();
        if (status != null && !status.isBlank() && !"all".equals(status)) { w.append(" AND l.status=?"); args.add(status.trim()); }
        long total = num(Db.scalar("SELECT COUNT(*) FROM doll_ai_logs l" + w, args.toArray()));
        List<Object> pa = new ArrayList<>(args);
        pa.add(size);
        pa.add((long) (page - 1) * size);
        var rows = Db.rows("SELECT l.id,l.user_id,u.username,l.prompt,l.status,l.message,l.duration_ms,l.created_at " +
                "FROM doll_ai_logs l LEFT JOIN users u ON u.id=l.user_id" + w + " ORDER BY l.id DESC LIMIT ? OFFSET ?", pa.toArray());
        for (var r : rows) {
            r.put("id", num(r.get("id")));
            r.put("user_id", num(r.get("user_id")));
        }
        return Resp.ok(Resp.map("total", total, "page", page, "size", size, "items", rows));
    }

    @GetMapping("/ai-logs/{id}")
    public Object aiLogDetail(@PathVariable long id, HttpServletResponse resp) {
        var r = Db.one("SELECT l.*,u.username FROM doll_ai_logs l LEFT JOIN users u ON u.id=l.user_id WHERE l.id=?", id);
        if (r == null) { resp.setStatus(404); return Resp.map("code", "NOT_FOUND", "message", "日志不存在", "data", null); }
        r.put("id", num(r.get("id")));
        return Resp.ok(r);
    }

    /** 用户的 AI 配置（密钥掩码，仅展示；真实密钥只在服务端用于调用） */
    @GetMapping("/ai-configs")
    public Object aiConfigs(@RequestParam(defaultValue = "1") int page,
                            @RequestParam(defaultValue = "20") int size) {
        long total = num(Db.scalar("SELECT COUNT(*) FROM ai_configs"));
        var rows = Db.rows("SELECT c.id,c.user_id,u.username,c.name,c.provider_type,c.api_style,c.api_url,c.model,c.mode,c.enabled,c.run_count,c.last_run_at, " +
                "CASE WHEN c.api_key IS NULL OR c.api_key='' THEN '' ELSE CONCAT('****', RIGHT(c.api_key, 4)) END AS api_key_masked " +
                "FROM ai_configs c LEFT JOIN users u ON u.id=c.user_id ORDER BY c.id DESC LIMIT ? OFFSET ?", size, (long) (page - 1) * size);
        for (var r : rows) {
            r.put("id", num(r.get("id")));
            r.put("user_id", num(r.get("user_id")));
            r.put("enabled", num(r.get("enabled")) == 1);
        }
        return Resp.ok(Resp.map("total", total, "page", page, "size", size, "items", rows));
    }
}
