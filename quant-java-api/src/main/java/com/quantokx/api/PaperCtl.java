package com.quantokx.api;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;

@RestController @RequestMapping("/api")
public class PaperCtl {
  Long uid(HttpServletRequest q) { return (Long) q.getAttribute("uid"); }

  @GetMapping("/paper/status") public Map<String, Object> status(@RequestParam String market_type, HttpServletRequest q) {
    long uid = uid(q);
    var pos = Db.rows("SELECT * FROM positions WHERE user_id=? AND status='OPEN' AND market_type=?", uid, market_type);
    return Resp.ok(Resp.map("exchange", "okx", "market_type", market_type, "local_trading_enabled", true, "configured", true, "positions", pos));
  }
  @PostMapping("/paper/place") public Map<String, Object> place(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q);
    String sym = Svc.str(b.get("symbol")); String side = Svc.str(b.get("side"));
    long id = Db.ins("INSERT INTO orders(user_id,symbol,market_type,mode,side,order_type,status) VALUES(?,?,?, 'paper', ?, 'MARKET', 'FILLED')", uid, sym, Svc.str(b.get("market_type")), side);
    return Resp.ok("订单已提交", Resp.map("id", id, "status", "FILLED"));
  }
  @PostMapping("/paper/local-trading") public Map<String, Object> localTrading(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    return Resp.ok("本地交易开关已更新", Resp.map("enabled", Boolean.TRUE.equals(b.get("enabled"))));
  }
  @PostMapping("/paper/reset") public Map<String, Object> reset(HttpServletRequest q) { return Resp.ok("模拟盘已重置", null); }
  @GetMapping("/paper/local-trading") public Map<String, Object> getLocalTrading(HttpServletRequest q) { return Resp.ok(Resp.map("enabled", true)); }
}
