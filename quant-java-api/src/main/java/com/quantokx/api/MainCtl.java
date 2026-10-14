package com.quantokx.api;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
@RestController @RequestMapping("/api")
public class MainCtl {
  Long uid(HttpServletRequest q) { return (Long) q.getAttribute("uid"); }
  @GetMapping("/dashboard") public Object dash(HttpServletRequest q) {
    long uid = uid(q);
    var positions = Db.rows("SELECT * FROM positions WHERE user_id=? AND status='OPEN'", uid);
    var orders = Db.rows("SELECT * FROM orders WHERE user_id=? ORDER BY id DESC LIMIT 50", uid);
    var risk = Db.one("SELECT * FROM risk_configs WHERE user_id=?", uid);
    boolean em = risk != null && ((Number) risk.getOrDefault("emergency_stop", 0)).intValue() == 1;
    boolean live = risk != null && ((Number) risk.getOrDefault("live_trading", 0)).intValue() == 1;
    int aiR = Db.rows("SELECT id FROM ai_configs WHERE user_id=? AND running=1 AND enabled=1", uid).size();
    int stC = Db.rows("SELECT id FROM strategies WHERE user_id=?", uid).size();
    return Resp.ok(Resp.map("okx", Resp.eo(), "orders", orders, "positions", positions, "pnl", Resp.map("today",0,"total_30d",0), "strategy_count", stC, "ai_running", aiR, "emergency_stop", em, "live_trading_enabled", live, "server_time", new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX").format(new Date())));
  }
  @PostMapping("/system/refresh") public Object refresh(HttpServletRequest q) { return Resp.ok("已刷新", Resp.eo()); }
  @PostMapping("/system/emergency-stop") public Object emStop(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); boolean en = Boolean.TRUE.equals(b.get("enabled"));
    Db.upd("INSERT INTO risk_configs(user_id,emergency_stop) VALUES(?,?) ON DUPLICATE KEY UPDATE emergency_stop=VALUES(emergency_stop)", uid, en?1:0);
    return Resp.ok(en?"紧急停止已开启":"紧急停止已解除", Resp.map("emergency_stop", en));
  }
  @PostMapping("/system/live-trading") public Object liveTrade(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); boolean en = Boolean.TRUE.equals(b.get("enabled"));
    Db.upd("UPDATE users SET live_trading=? WHERE id=?", en?1:0, uid);
    return Resp.ok(en?"实盘已开启":"实盘已关闭", Resp.map("live_trading_enabled", en));
  }
  @GetMapping("/system/automation/status") public Object autoStatus(HttpServletRequest q) {
    long uid = uid(q);
    return Resp.ok(Resp.map("strategy", Resp.map("state","healthy","runs",1,"last_error",null), "ai", Resp.map("state","healthy","runs",1,"last_error",null), "sync", Resp.map("state","healthy","runs",0,"last_error",null), "stale_after", 900, "checked_at", new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX").format(new Date()), "cron_url", "/api/system/automation/cron", "commands", Resp.eo(), "active_strategy_count", 0, "active_ai_count", 0));
  }
  @GetMapping("/risk/config") public Object riskGet(HttpServletRequest q) {
    long uid = uid(q); var rc = Db.one("SELECT * FROM risk_configs WHERE user_id=?", uid);
    if (rc == null) { Db.ins("INSERT INTO risk_configs(user_id) VALUES(?)", uid); rc = Db.one("SELECT * FROM risk_configs WHERE user_id=?", uid); }
    return Resp.ok(rc);
  }
  @PostMapping("/risk/config") public Object riskSave(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q);
    Db.upd("UPDATE risk_configs SET single_position_percent=?,max_leverage=? WHERE user_id=?", Svc.num(b.get("single_position_percent"),5), Svc.num(b.get("max_leverage"),20), uid);
    return Resp.ok("风控配置已保存", null);
  }
  @GetMapping("/trades") public Object trades(HttpServletRequest q) { return Resp.ok(Db.rows("SELECT * FROM trades WHERE user_id=? ORDER BY id DESC LIMIT 100", uid(q))); }
  @GetMapping("/trades/stats") public Object tradeStats(HttpServletRequest q) { return Resp.ok(Resp.map("total",0,"buy_count",0,"sell_count",0,"volume",0,"fee",0)); }
  @GetMapping("/profit") public Object profit(HttpServletRequest q) { return Resp.ok(Resp.map("days",30,"total_pnl",0,"daily",Resp.eo(),"curve",new ArrayList<>(),"assets",Resp.map("okx",Resp.eo()),"by_exchange",Resp.eo())); }
  @GetMapping("/logs/trading") public Object tLogs(HttpServletRequest q) { return Resp.ok(Db.rows("SELECT id,symbol,source,signal,price,result,pnl,created_at FROM trading_logs WHERE user_id=? ORDER BY id DESC LIMIT 200", uid(q))); }
  @GetMapping("/logs/system") public Object sLogs(HttpServletRequest q) { return Resp.ok(Db.rows("SELECT id,level,channel,message,created_at FROM system_logs ORDER BY id DESC LIMIT 200")); }
  @GetMapping("/orders") public Object orders(HttpServletRequest q) {
    var rows = Db.rows("SELECT * FROM orders WHERE user_id=? ORDER BY id DESC LIMIT 100", uid(q));
    var local = new ArrayList<Map<String, Object>>();
    for (var r : rows) local.add(Resp.map("id", ((Number)r.get("id")).intValue(), "symbol", Svc.str(r.get("symbol")), "side", Svc.str(r.get("side")), "order_type", Svc.str(r.get("order_type")), "price", Svc.str(r.get("price")), "quantity", Svc.str(r.get("quantity")), "status", Svc.str(r.get("status")), "mode", Svc.str(r.get("mode")), "created_at", Svc.str(r.get("created_at"))));
    return Resp.ok(Resp.map("local", local, "remote", new ArrayList<>()));
  }
  @PostMapping("/order/cancel") public Object cancel(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = ((Number)b.get("id")).longValue();
    Db.upd("UPDATE orders SET status='CANCELED' WHERE id=? AND user_id=?", id, uid);
    return Resp.ok("订单已撤销", null);
  }
  @GetMapping("/positions/local") public Object posLocal(HttpServletRequest q) { return Resp.ok(Db.rows("SELECT * FROM positions WHERE user_id=? AND status='OPEN'", uid(q))); }
  @PostMapping("/position/close") public Object closePos(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); String sym = Svc.str(b.get("symbol"));
    Db.upd("UPDATE positions SET status='CLOSED', unrealized_pnl='0' WHERE user_id=? AND symbol=? AND status='OPEN'", uid, sym);
    return Resp.ok("持仓已平仓", Resp.map("symbol", sym, "pnl", 0));
  }
}
