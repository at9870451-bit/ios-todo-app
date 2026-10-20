package com.quantokx.api;

import java.util.*;

/**
 * Doll Studio 3D —— AI 穿搭推荐服务。
 * 款式键与 iOS 端程序化 3D 构建器一一对应（缺一个客户端就渲染不出来），
 * 服务端负责：构建提示词（附目录清单）→ 调用 AI（复用 ChatCtl.callAI，密钥不出服务端）→ 解析校验。
 */
public final class DollSvc {

    /** 分类 → 有效款式键（与 iOS DollCatalog.styleKeys 严格一致） */
    static final Map<String, List<String>> STYLES = linkedMap(
        "hair", List.of("short", "bob", "long", "twintails", "bun", "spiky"),
        "top", List.of("tee", "hoodie", "shirt", "vest", "sweater", "jacket"),
        "bottom", List.of("shorts", "pants", "skirt", "wide_leg"),
        "scarf", List.of("scarf", "bandana"),
        "hat", List.of("beanie", "cap", "bucket", "beret"),
        "shoes", List.of("sneakers", "boots", "loafers", "sandals"),
        "accessory", List.of("glasses", "necklace", "backpack", "earrings", "flower", "watch")
    );

    static final Map<String, String> CAT_NAMES = Map.of(
        "hair", "发型", "top", "上衣", "bottom", "下装",
        "scarf", "围巾", "hat", "帽子", "shoes", "鞋子", "accessory", "配饰"
    );

    static boolean validStyle(String category, String style) {
        List<String> l = STYLES.get(category);
        return l != null && style != null && l.contains(style);
    }

    /** 组装 AI 消息（system 规则 + user 诉求与目录清单） */
    static List<Map<String, Object>> buildMessages(String gender, String prompt) {
        StringBuilder sb = new StringBuilder();
        sb.append("玩偶性别：").append(genderName(gender)).append("\n");
        sb.append("搭配诉求：").append(prompt).append("\n");
        sb.append("可用服饰清单（分类: 款式(名称,默认色)）：\n");
        for (var e : STYLES.entrySet()) {
            List<String> parts = new ArrayList<>();
            for (String s : e.getValue()) {
                var row = Db.one("SELECT name,color FROM doll_items WHERE category=? AND style=? AND enabled=1 ORDER BY sort ASC, id ASC LIMIT 1", e.getKey(), s);
                String name = row == null ? s : Svc.str(row.get("name"));
                String color = row == null ? "#CCCCCC" : Svc.str(row.get("color"));
                parts.add(s + "(" + name + "," + color + ")");
            }
            sb.append(CAT_NAMES.getOrDefault(e.getKey(), e.getKey()))
              .append("(").append(e.getKey()).append("): ")
              .append(String.join(", ", parts)).append("\n");
        }
        var system = Resp.map("role", "system", "content",
            "你是潮玩换装应用 Doll Studio 3D 的 AI 搭配师。根据用户诉求，为 Q 版盲盒玩偶挑选一套完整穿搭。" +
            "只能使用清单中给出的款式(style)，颜色用 #RRGGBB 十六进制（可用清单默认色或自行搭配协调色）。" +
            "必须只输出一个 JSON 对象，不要输出任何其它文字、注释或代码块标记，格式：" +
            "{\"items\":{\"top\":{\"style\":\"...\",\"color\":\"#...\"},\"bottom\":{\"style\":\"...\",\"color\":\"#...\"}," +
            "\"scarf\":{\"style\":\"...\",\"color\":\"#...\"},\"hat\":{\"style\":\"...\",\"color\":\"#...\"}," +
            "\"shoes\":{\"style\":\"...\",\"color\":\"#...\"},\"hair\":{\"style\":\"...\",\"color\":\"#...\"}," +
            "\"accessory\":{\"style\":\"...\",\"color\":\"#...\"}},\"reason\":\"不超过40字的搭配说明\"}。" +
            "某分类确实不需要时可在 items 中省略该分类。reason 用中文。");
        var user = Resp.map("role", "user", "content", sb.toString());
        return List.of(system, user);
    }

    /**
     * 解析 AI 返回：宽容提取 JSON（容忍代码块围栏），校验款式合法性，
     * 颜色非法时回退该款式默认色。返回 {items:{cat:{style,color,item_id,name}}, reason}；失败返回 null。
     */
    static Map<String, Object> parseRecommend(String reply) {
        if (reply == null || reply.isBlank()) return null;
        String s = reply.trim().replace("```json", "").replace("```", "");
        int a = s.indexOf('{'), b = s.lastIndexOf('}');
        if (a < 0 || b <= a) return null;
        try {
            var root = new com.fasterxml.jackson.databind.ObjectMapper().readTree(s.substring(a, b + 1));
            var itemsNode = root.path("items");
            if (!itemsNode.isObject()) return null;
            Map<String, Object> items = new LinkedHashMap<>();
            for (var e : STYLES.entrySet()) {
                String cat = e.getKey();
                var node = itemsNode.path(cat);
                if (!node.isObject()) continue;
                String style = node.path("style").asText("");
                if (!validStyle(cat, style)) continue;
                String color = node.path("color").asText("");
                if (!color.matches("^#[0-9A-Fa-f]{6}$")) {
                    var row = Db.one("SELECT color FROM doll_items WHERE category=? AND style=? AND enabled=1 ORDER BY sort ASC, id ASC LIMIT 1", cat, style);
                    color = row == null ? "#CCCCCC" : Svc.str(row.get("color"));
                }
                Map<String, Object> it = new LinkedHashMap<>();
                it.put("style", style);
                it.put("color", color.toUpperCase());
                var row = Db.one("SELECT id,name FROM doll_items WHERE category=? AND style=? AND enabled=1 ORDER BY sort ASC, id ASC LIMIT 1", cat, style);
                if (row != null) {
                    it.put("item_id", num(row.get("id")));
                    it.put("name", Svc.str(row.get("name")));
                }
                items.put(cat, it);
            }
            if (items.isEmpty()) return null;
            String reason = root.path("reason").asText("为你挑选了这套搭配");
            if (reason.length() > 60) reason = reason.substring(0, 60);
            Map<String, Object> out = new LinkedHashMap<>();
            out.put("outfit", items);
            out.put("reason", reason);
            return out;
        } catch (Exception e) {
            return null;
        }
    }

    static String genderName(String g) {
        if ("male".equals(g)) return "男性";
        if ("female".equals(g)) return "女性";
        return "中性";
    }

    private static Map<String, List<String>> linkedMap(Object... kv) {
        Map<String, List<String>> m = new LinkedHashMap<>();
        for (int i = 0; i + 1 < kv.length; i += 2) m.put((String) kv[i], (List<String>) kv[i + 1]);
        return m;
    }

    static long num(Object o) { return o instanceof Number n ? n.longValue() : 0; }

    private DollSvc() {}
}
