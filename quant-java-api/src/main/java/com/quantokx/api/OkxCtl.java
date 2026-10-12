package com.quantokx.api;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;

@RestController @RequestMapping("/api")
public class OkxCtl {
  Long uid(HttpServletRequest q) { return (Long) q.getAttribute("uid"); }

  @GetMapping("/okx/accounts") public Map<String, Object> accounts(HttpServletRequest q) {
    return Resp.ok(Db.rows("SELECT id,name,market_type,environment,testnet,enabled FROM okx_accounts WHERE user_id=? AND deleted_at IS NULL", uid(q)));
  }
  @GetMapping("/okx/config") public Map<String, Object> config(HttpServletRequest q) {
    return Resp.ok(Resp.map("spot", Resp.map("configured", false, "exchange", "okx", "market_type", "spot"), "swap", Resp.map("configured", false, "exchange", "okx", "market_type", "swap")));
  }
  @GetMapping("/okx/positions") public Map<String, Object> positions(@RequestParam String market_type, HttpServletRequest q) { return Resp.ok(new ArrayList<>()); }
  @GetMapping("/positions/local") public Map<String, Object> positionsLocal(HttpServletRequest q) { return Resp.ok(Db.rows("SELECT * FROM positions WHERE user_id=? AND status='OPEN'", uid(q))); }
  @PostMapping("/position/close") public Map<String, Object> closePos(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); String sym = Svc.str(b.get("symbol"));
    Db.upd("UPDATE positions SET status='CLOSED', unrealized_pnl='0' WHERE user_id=? AND symbol=? AND status='OPEN'", uid, sym);
    return Resp.ok("持仓已平仓", Resp.map("symbol", sym, "pnl", 0));
  }
  @GetMapping("/okx/tickers") public Map<String, Object> tickers(@RequestParam String market_type, HttpServletRequest q) { return Resp.ok(new ArrayList<>()); }
  @GetMapping("/okx/ticker") public Map<String, Object> ticker(@RequestParam String symbol, @RequestParam String market_type, HttpServletRequest q) {
    return Resp.ok(Resp.map("symbol", symbol, "lastPrice", "0", "highPrice", "0", "lowPrice", "0", "volume", "0", "priceChangePercent", "0"));
  }
  @GetMapping("/okx/kline") public Map<String, Object> kline(@RequestParam String symbol, @RequestParam String market_type, @RequestParam String interval, HttpServletRequest q) { return Resp.ok(new ArrayList<>()); }
  @PostMapping("/okx/order/cancel") public Map<String, Object> cancelOrder(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = b.get("id") instanceof Number n ? n.longValue() : 0;
    Db.upd("UPDATE orders SET status='CANCELED' WHERE id=? AND user_id=?", id, uid); return Resp.ok("订单已撤销", null);
  }
  @GetMapping("/okx/position-mode") public Map<String, Object> positionMode(@RequestParam String market_type, HttpServletRequest q) { return Resp.ok(Resp.map("configured", false, "pos_mode", null, "hedged", false)); }
  @PostMapping("/okx/reconcile") public Map<String, Object> reconcile(HttpServletRequest q) { return Resp.ok("对账完成", Resp.eo()); }
}
