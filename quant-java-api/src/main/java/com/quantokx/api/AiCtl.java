package com.quantokx.api;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;

@RestController @RequestMapping("/api")
public class AiCtl {
  Long uid(HttpServletRequest q) { return (Long) q.getAttribute("uid"); }

  @GetMapping("/ai/list") public Object list(HttpServletRequest q) {
    return Resp.ok(Db.rows("SELECT * FROM ai_configs WHERE user_id=? ORDER BY id DESC", uid(q)));
  }
  @GetMapping("/ai/get") public Object get(@RequestParam long id, HttpServletRequest q) {
    return Resp.ok(Db.one("SELECT * FROM ai_configs WHERE user_id=? AND id=?", uid(q), id));
  }
  @PostMapping("/ai/config") public Object save(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = b.get("id") instanceof Number n ? n.longValue() : 0;
    String name = Svc.str(b.get("name")); if (name.isEmpty()) return Resp.map("code","INVALID_PARAM","message","请填写配置名称","data",null);
    if (id > 0) { Db.upd("UPDATE ai_configs SET name=?,api_url=?,model=?,api_key=?,api_style=? WHERE id=? AND user_id=?", name, Svc.str(b.get("api_url")), Svc.str(b.get("model")), Svc.str(b.get("api_key")), Svc.str(b.getOrDefault("api_style","chat_completions")), id, uid); return Resp.ok("AI 配置已保存", Resp.map("id", id)); }
    long newId = Db.ins("INSERT INTO ai_configs(user_id,name,provider_type,api_url,model,api_key,api_style) VALUES(?,?,?,?,?,?,?)", uid, name, Svc.str(b.getOrDefault("provider_type","openai")), Svc.str(b.get("api_url")), Svc.str(b.get("model")), Svc.str(b.get("api_key")), Svc.str(b.getOrDefault("api_style","chat_completions")));
    return Resp.ok("AI 配置已保存", Resp.map("id", newId));
  }
  @PostMapping("/ai/delete") public Object delete(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = b.get("id") instanceof Number n ? n.longValue() : 0;
    Db.upd("DELETE FROM ai_configs WHERE id=? AND user_id=?", id, uid); return Resp.ok("AI 配置已删除", null);
  }
  @PostMapping("/ai/test") public Object test(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = b.get("id") instanceof Number n ? n.longValue() : 0;
    var row = Db.one("SELECT * FROM ai_configs WHERE id=? AND user_id=?", id, uid);
    if (row == null) return Resp.map("code","AI_CONFIG_ERROR","message","配置不存在","data",null);
    String apiKey = Svc.str(row.get("api_key")); String apiUrl = Svc.str(row.get("api_url")); String model = Svc.str(row.get("model"));
    if (!apiUrl.endsWith("/chat/completions")) apiUrl += "/v1/chat/completions";
    try (var c = java.net.http.HttpClient.newHttpClient()) {
      var req = java.net.http.HttpRequest.newBuilder().uri(java.net.URI.create(apiUrl)).header("Content-Type","application/json").header("Authorization","Bearer "+apiKey).POST(java.net.http.HttpRequest.BodyPublishers.ofString("{\"model\":\""+model+"\",\"messages\":[{\"role\":\"user\",\"content\":\"回复OK\"}],\"max_tokens\":5}")).build();
      var resp = c.send(req, java.net.http.HttpResponse.BodyHandlers.ofString());
      Db.upd("UPDATE ai_configs SET test_status=?,test_message=? WHERE id=?", resp.statusCode()==200?"success":"failed", "HTTP "+resp.statusCode(), id);
      return Resp.ok("HTTP "+resp.statusCode(), Resp.map("http_status", resp.statusCode()));
    } catch (Exception e) { Db.upd("UPDATE ai_configs SET test_status='failed',test_message=? WHERE id=?", e.getMessage(), id); return Resp.map("code","AI_TEST_ERROR","message",e.getMessage(),"data",null); }
  }
  @PostMapping("/ai/diagnose") public Object diagnose(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = b.get("id") instanceof Number n ? n.longValue() : 0;
    var row = Db.one("SELECT * FROM ai_configs WHERE id=? AND user_id=?", id, uid);
    if (row == null) return Resp.map("code","AI_CONFIG_ERROR","message","配置不存在","data",null);
    return Resp.ok(Resp.map("success", true, "config_id", id, "steps", List.of(Resp.map("name","配置", "status","passed", "message","已加载配置 #"+id), Resp.map("name","API Key", "status","passed", "message","已保存，长度 "+Svc.str(row.get("api_key")).length()))));
  }
  @GetMapping("/ai/auto/status") public Object autoStatus(HttpServletRequest q) {
    long uid = uid(q); var cfgs = Db.rows("SELECT * FROM ai_configs WHERE user_id=? AND mode='auto' AND enabled=1", uid);
    var risk = Db.one("SELECT * FROM risk_configs WHERE user_id=?", uid);
    boolean em = risk != null && ((Number)risk.getOrDefault("emergency_stop",0)).intValue()==1;
    boolean live = risk != null && ((Number)risk.getOrDefault("live_trading",0)).intValue()==1;
    boolean running = cfgs.stream().anyMatch(c -> ((Number)c.getOrDefault("running",0)).intValue()==1);
    var signals = Db.rows("SELECT * FROM ai_signals WHERE user_id=? ORDER BY id DESC LIMIT 20", uid);
    var sigList = new ArrayList<Map<String, Object>>();
    for (var s : signals) sigList.add(Resp.map("id",((Number)s.get("id")).intValue(),"symbol",Svc.str(s.get("symbol")),"signal",Svc.str(s.get("signal")),"confidence",Svc.str(s.get("confidence")),"entry",Svc.str(s.get("entry")),"stop_loss",Svc.str(s.get("stop_loss")),"take_profit",Svc.str(s.get("take_profit")),"reason",Svc.str(s.get("reason")),"executed",((Number)s.getOrDefault("executed",0)).intValue(),"created_at",Svc.str(s.get("created_at"))));
    return Resp.ok(Resp.map("running",running,"running_count",running?cfgs.size():0,"auto_config_count",cfgs.size(),"emergency_stop",em,"live_trading_enabled",live,"local_trading_enabled",true,"max_leverage",risk!=null?((Number)risk.getOrDefault("max_leverage",20)).intValue():20,"cron_url","/api/ai/cron","configs",cfgs,"recent_signals",sigList,"recent_reviews",new ArrayList<>()));
  }
  @PostMapping("/ai/auto/start") public Object autoStart(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = b.get("id") instanceof Number n ? n.longValue() : 0;
    if (id > 0) Db.upd("UPDATE ai_configs SET running=1 WHERE id=? AND user_id=?", id, uid);
    else Db.upd("UPDATE ai_configs SET running=1 WHERE user_id=? AND mode='auto' AND enabled=1", uid);
    return Resp.ok("AI 自动交易已启动", null);
  }
  @PostMapping("/ai/auto/stop") public Object autoStop(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = b.get("id") instanceof Number n ? n.longValue() : 0;
    if (id > 0) Db.upd("UPDATE ai_configs SET running=0 WHERE id=? AND user_id=?", id, uid);
    else Db.upd("UPDATE ai_configs SET running=0 WHERE user_id=?", uid);
    return Resp.ok("AI 自动交易已停止", null);
  }
  @GetMapping("/ai/reviews") public Object reviews(HttpServletRequest q) {
    return Resp.ok(Db.rows("SELECT * FROM ai_reviews WHERE user_id=? ORDER BY id DESC LIMIT 20", uid(q)));
  }
}
