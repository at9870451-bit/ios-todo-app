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

  @PostMapping("/send")
  public Object send(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q);
    String content = Svc.str(b.get("content"));
    if (content.isEmpty()) return Resp.map("code", "INVALID_PARAM", "message", "消息不能为空", "data", null);
    long sessionId = b.get("session_id") instanceof Number n ? n.longValue() : 0;
    var cfg = Db.one("SELECT * FROM ai_configs WHERE user_id=? AND mode='chat' AND enabled=1 ORDER BY id DESC LIMIT 1", uid);
    if (cfg == null) cfg = Db.one("SELECT * FROM ai_configs WHERE user_id=? ORDER BY id DESC LIMIT 1", uid);
    if (cfg == null) return Resp.map("code", "CHAT_NO_CONFIG", "message", "请先在设置中配置 AI 接口", "data", null);
    if (sessionId <= 0 || Db.one("SELECT id FROM chat_sessions WHERE id=? AND user_id=?", sessionId, uid) == null) {
      String title = content.length() > 20 ? content.substring(0, 20) : content;
      sessionId = Db.ins("INSERT INTO chat_sessions(user_id,title,updated_at) VALUES(?,?,datetime('now','localtime'))", uid, title);
    }
    final long sid = sessionId;
    Db.ins("INSERT INTO chat_messages(session_id,role,content) VALUES(?,'user',?)", sid, content);
    var history = Db.rows("SELECT role,content FROM chat_messages WHERE session_id=? ORDER BY id DESC LIMIT 20", sid);
    Collections.reverse(history);
    StringBuilder msgs = new StringBuilder("[");
    for (int i = 0; i < history.size(); i++) {
      var m = history.get(i);
      if (i > 0) msgs.append(",");
      msgs.append("{\"role\":\"").append(Svc.str(m.get("role"))).append("\",\"content\":")
           .append(com.quantokx.api.Json.escape(Svc.str(m.get("content")))).append("}");
    }
    msgs.append("]");
    try {
      String reply = callAI(cfg, msgs.toString());
      Db.ins("INSERT INTO chat_messages(session_id,role,content) VALUES(?,'assistant',?)", sid, reply);
      Db.upd("UPDATE chat_sessions SET updated_at=datetime('now','localtime') WHERE id=?", sid);
      return Resp.ok(Resp.map("session_id", sid, "reply", reply));
    } catch (Exception e) {
      return Resp.map("code", "CHAT_ERROR", "message", e.getMessage(), "data", Resp.map("session_id", sid));
    }
  }

  static String callAI(Map<String, Object> cfg, String messagesJson) throws Exception {
    String apiKey = Svc.str(cfg.get("api_key"));
    String apiUrl = Svc.str(cfg.get("api_url"));
    String model = Svc.str(cfg.getOrDefault("model", "deepseek-chat"));
    double temperature = cfg.get("temperature") instanceof Number n ? n.doubleValue() : 0.7;
    if (!apiUrl.contains("/completions")) apiUrl = apiUrl.replaceAll("/+$", "") + "/v1/chat/completions";
    String body = "{\"model\":\"" + com.quantokx.api.Json.escape(model) + "\",\"messages\":" + messagesJson + ",\"temperature\":" + temperature + ",\"max_tokens\":2048}";
    HttpClient c = HttpClient.newBuilder().connectTimeout(java.time.Duration.ofSeconds(20)).build();
    HttpRequest req = HttpRequest.newBuilder().uri(URI.create(apiUrl)).header("Content-Type", "application/json").header("Authorization", "Bearer " + apiKey).timeout(java.time.Duration.ofMinutes(5)).POST(HttpRequest.BodyPublishers.ofString(body)).build();
    HttpResponse<String> resp = c.send(req, HttpResponse.BodyHandlers.ofString());
    if (resp.statusCode() != 200) throw new RuntimeException("HTTP " + resp.statusCode() + ": " + resp.body().substring(0, Math.min(200, resp.body().length())));
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
