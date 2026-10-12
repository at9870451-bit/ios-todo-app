package com.quantokx.api;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import java.net.URI;
import java.net.http.*;

@RestController @RequestMapping("/api/chat")
public class ChatCtl {
  Long uid(HttpServletRequest q) { return (Long) q.getAttribute("uid"); }

  @GetMapping("/sessions")
  public Object sessions(HttpServletRequest q) {
    long uid = uid(q);
    var rows = Db.rows("SELECT s.*, (SELECT content FROM chat_messages m WHERE m.session_id=s.id ORDER BY m.id DESC LIMIT 1) AS last_msg FROM chat_sessions s WHERE s.user_id=? ORDER BY s.updated_at DESC", uid);
    for (var r : rows) {
      String last = Svc.str(r.get("last_msg"));
      if (last.length() > 60) last = last.substring(0, 60) + "...";
      r.put("last_msg", last);
      r.put("id", ((Number) r.get("id")).longValue());
    }
    return Resp.ok(rows);
  }

  @PostMapping("/session")
  public Object newSession(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q);
    String title = Svc.str(b.getOrDefault("title", "新对话"));
    long id = Db.ins("INSERT INTO chat_sessions(user_id,title,updated_at) VALUES(?,?,datetime('now','localtime'))", uid, title);
    return Resp.ok(Resp.map("id", id, "title", title));
  }

  @PostMapping("/session/rename")
  public Object rename(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = ((Number) b.get("id")).longValue();
    Db.upd("UPDATE chat_sessions SET title=? WHERE id=? AND user_id=?", Svc.str(b.get("title")), id, uid);
    return Resp.ok("已重命名", null);
  }

  @PostMapping("/session/delete")
  public Object del(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = ((Number) b.get("id")).longValue();
    Db.upd("DELETE FROM chat_messages WHERE session_id=?", id);
    Db.upd("DELETE FROM chat_sessions WHERE id=? AND user_id=?", id, uid);
    return Resp.ok("会话已删除", null);
  }

  @GetMapping("/messages")
  public Object messages(@RequestParam long session_id, HttpServletRequest q) {
    long uid = uid(q);
    var own = Db.one("SELECT id FROM chat_sessions WHERE id=? AND user_id=?", session_id, uid);
    if (own == null) return Resp.map("code", "NOT_FOUND", "message", "会话不存在", "data", null);
    return Resp.ok(Db.rows("SELECT id,role,content,created_at FROM chat_messages WHERE session_id=? ORDER BY id ASC", session_id));
  }

  /**
   * 发送消息。附件由客户端本地直传 AI（base64 多模态 content parts），服务端不保存附件文件。
   * body: {session_id?, content, attachments?: [{kind:"image"|"video"|"file", name, mime?, dataBase64?}], reasoning?: "low"|"medium"|"high"}
   */
  @PostMapping("/send")
  public Object send(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q);
    String content = Svc.str(b.get("content"));
    long sessionId = b.get("session_id") instanceof Number n ? n.longValue() : 0;
    String reasoning = Svc.str(b.get("reasoning"));
    var atts = parseAtts(b.get("attachments"));
    if (content.isEmpty() && atts.isEmpty()) return Resp.map("code", "INVALID_PARAM", "message", "消息不能为空", "data", null);

    var cfg = Db.one("SELECT * FROM ai_configs WHERE user_id=? AND mode='chat' AND enabled=1 ORDER BY id DESC LIMIT 1", uid);
    if (cfg == null) cfg = Db.one("SELECT * FROM ai_configs WHERE user_id=? ORDER BY id DESC LIMIT 1", uid);
    if (cfg == null) return Resp.map("code", "CHAT_NO_CONFIG", "message", "请先在设置中配置 AI 接口", "data", null);

    if (sessionId <= 0 || Db.one("SELECT id FROM chat_sessions WHERE id=? AND user_id=?", sessionId, uid) == null) {
      String title = content.isEmpty() ? (atts.isEmpty() ? "新对话" : Svc.str(atts.get(0).get("name"))) : content;
      if (title.length() > 20) title = title.substring(0, 20);
      sessionId = Db.ins("INSERT INTO chat_sessions(user_id,title,updated_at) VALUES(?,?,datetime('now','localtime'))", uid, title);
    }
    final long sid = sessionId;
    Db.ins("INSERT INTO chat_messages(session_id,role,content) VALUES(?,'user',?)", sid, content.isEmpty() ? "[附件]" : content);
    var history = Db.rows("SELECT role,content FROM chat_messages WHERE session_id=? ORDER BY id DESC LIMIT 20", sid);
    Collections.reverse(history);

    // 组装 messages：历史文本 + 最后一条为多模态 content parts（图片 base64 内联，视频/文件以文本元数据描述）
    var msgs = new ArrayList<Map<String, Object>>();
    for (var m : history) {
      String role = Svc.str(m.get("role"));
      String c = Svc.str(m.get("content"));
      if (role.equals("assistant")) {
        msgs.add(Resp.map("role", "assistant", "content", c));
      } else {
        msgs.add(Resp.map("role", "user", "content", c));
      }
    }
    if (!atts.isEmpty()) {
      var parts = new ArrayList<Map<String, Object>>();
      if (!content.isEmpty()) parts.add(textPart(content));
      for (var a : atts) {
        String kind = Svc.str(a.get("kind"));
        String name = Svc.str(a.get("name"));
        String data = Svc.str(a.get("dataBase64"));
        String mime = Svc.str(a.get("mime"));
        if (kind.equals("image") && !data.isEmpty()) {
          var url = Resp.map("url", "data:" + (mime.isEmpty() ? "image/jpeg" : mime) + ";base64," + data);
          parts.add(Resp.map("type", "image_url", "image_url", url));
        } else if (kind.equals("video")) {
          parts.add(textPart("[用户附带视频：" + name + "]"));
        } else {
          parts.add(textPart("[用户附带文件：" + name + "]"));
        }
      }
      int lastIdx = msgs.size() - 1;
      if (lastIdx >= 0) msgs.set(lastIdx, Resp.map("role", "user", "content", parts));
    }

    try {
      String reply = callAI(cfg, msgs, reasoning);
      Db.ins("INSERT INTO chat_messages(session_id,role,content) VALUES(?,'assistant',?)", sid, reply);
      Db.upd("UPDATE chat_sessions SET updated_at=datetime('now','localtime') WHERE id=?", sid);
      return Resp.ok(Resp.map("session_id", sid, "reply", reply));
    } catch (MultimodalUnsupportedException e) {
      // 模型不支持图片输入：去除 base64 图片降级为纯文本重试
      try {
        var fallback = new ArrayList<Map<String, Object>>(msgs);
        int lastIdx = fallback.size() - 1;
        if (lastIdx >= 0) {
          var parts = new ArrayList<Map<String, Object>>();
          parts.add(textPart(attTextDescription(atts, content)));
          fallback.set(lastIdx, Resp.map("role", "user", "content", parts));
        }
        String reply = callAI(cfg, fallback, reasoning);
        Db.ins("INSERT INTO chat_messages(session_id,role,content) VALUES(?,'assistant',?)", sid, reply);
        Db.upd("UPDATE chat_sessions SET updated_at=datetime('now','localtime') WHERE id=?", sid);
        return Resp.ok(Resp.map("session_id", sid, "reply", reply, "degraded", true));
      } catch (Exception e2) {
        return Resp.map("code", "CHAT_ERROR", "message", e2.getMessage(), "data", Resp.map("session_id", sid));
      }
    } catch (Exception e) {
      return Resp.map("code", "CHAT_ERROR", "message", e.getMessage(), "data", Resp.map("session_id", sid));
    }
  }

  // MARK: - 附件与多模态辅助

  @SuppressWarnings("unchecked")
  static List<Map<String, Object>> parseAtts(Object o) {
    var out = new ArrayList<Map<String, Object>>();
    if (!(o instanceof List<?> ls)) return out;
    for (Object item : ls) {
      if (!(item instanceof Map)) continue;
      Map<String, Object> m = (Map<String, Object>) item;
      Map<String, Object> a = new LinkedHashMap<>();
      a.put("kind", Svc.str(m.getOrDefault("kind", "file")));
      a.put("name", Svc.str(m.getOrDefault("name", "附件")));
      a.put("mime", Svc.str(m.getOrDefault("mime", "")));
      Object d = m.get("dataBase64");
      a.put("dataBase64", d == null ? "" : String.valueOf(d));
      out.add(a);
      if (out.size() >= 6) break; // 最多 6 个附件
    }
    return out;
  }

  static Map<String, Object> textPart(String t) {
    return Resp.map("type", "text", "text", t);
  }

  static String attTextDescription(List<Map<String, Object>> atts, String content) {
    StringBuilder sb = new StringBuilder(content.isEmpty() ? "请查看我的附件。" : content);
    for (var a : atts) {
      sb.append("\n[用户附带").append(Svc.str(a.get("kind")).equals("video") ? "视频：" : "文件：").append(Svc.str(a.get("name"))).append("]");
    }
    return sb.toString();
  }

  static class MultimodalUnsupportedException extends RuntimeException {
    MultimodalUnsupportedException(String msg) { super(msg); }
  }

  static String callAI(Map<String, Object> cfg, List<Map<String, Object>> messages, String reasoning) throws Exception {
    String apiKey = Svc.str(cfg.get("api_key"));
    String apiUrl = Svc.str(cfg.get("api_url"));
    String model = Svc.str(cfg.getOrDefault("model", "deepseek-chat"));
    double temperature = cfg.get("temperature") instanceof Number n ? n.doubleValue() : 0.7;
    if (!apiUrl.contains("/completions")) apiUrl = apiUrl.replaceAll("/+$", "") + "/v1/chat/completions";
    var root = Resp.eo();
    root.put("model", model);
    root.put("messages", messages);
    root.put("temperature", temperature);
    root.put("max_tokens", 2048);
    if (!reasoning.isEmpty() && !reasoning.equals("off")) root.put("reasoning_effort", reasoning);
    String body = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(root);
    HttpClient c = HttpClient.newBuilder().connectTimeout(java.time.Duration.ofSeconds(20)).build();
    HttpRequest req = HttpRequest.newBuilder().uri(URI.create(apiUrl)).header("Content-Type", "application/json").header("Authorization", "Bearer " + apiKey).timeout(java.time.Duration.ofMinutes(5)).POST(HttpRequest.BodyPublishers.ofString(body)).build();
    HttpResponse<String> resp = c.send(req, HttpResponse.BodyHandlers.ofString());
    if (resp.statusCode() != 200) {
      String eb = resp.body() == null ? "" : resp.body();
      String lower = eb.toLowerCase();
      if (!eb.isEmpty() && (lower.contains("image") || lower.contains("multimodal") || lower.contains("vision") || lower.contains("content parts") || lower.contains("invalid content"))) {
        throw new MultimodalUnsupportedException("HTTP " + resp.statusCode() + ": " + eb.substring(0, Math.min(200, eb.length())));
      }
      throw new RuntimeException("HTTP " + resp.statusCode() + ": " + eb.substring(0, Math.min(200, eb.length())));
    }
    return parseReply(resp.body());
  }

  static String parseReply(String json) {
    try {
      var root = new com.fasterxml.jackson.databind.ObjectMapper().readTree(json);
      var content = root.at("/choices/0/message/content").asText();
      if (content != null && !content.isEmpty()) return content;
    } catch (Exception ignore) {}
    return json.length() > 400 ? json.substring(0, 400) : (json.isEmpty() ? "(空响应)" : json);
  }
}
