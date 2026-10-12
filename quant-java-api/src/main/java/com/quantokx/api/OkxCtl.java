package com.quantokx.api;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;

@RestController @RequestMapping("/api")
public class OkxCtl {
  Long uid(HttpServletRequest q) { return (Long) q.getAttribute("uid"); }

  @GetMapping("/okx/accounts") public Object accounts(HttpServletRequest q) {
    return Resp.ok(Db.rows("SELECT id,name,market_type,environment,testnet,enabled FROM okx_accounts WHERE user_id=? AND deleted_at IS NULL", uid(q)));
  }
  @GetMapping("/okx/config") public Object config(HttpServletRequest q) {
    return Resp.ok(Resp.map("spot", Resp.map("configured", false, "exchange", "okx", "market_type", "spot"), "swap", Resp.map("configured", false, "exchange", "okx", "market_type", "swap")));
  }
  @GetMapping("/okx/positions") public Object positions(@RequestParam String market_type, HttpServletRequest q) { return Resp.ok(new ArrayList<>()); }
  @GetMapping("/okx/tickers") public Object tickers(@RequestParam String market_type, HttpServletRequest q) { return Resp.ok(new ArrayList<>()); }
  @GetMapping("/okx/ticker") public Object ticker(@RequestParam String symbol, @RequestParam String market_type, HttpServletRequest q) {
    return Resp.ok(Resp.map("symbol", symbol, "lastPrice", "0", "highPrice", "0", "lowPrice", "0", "volume", "0", "priceChangePercent", "0"));
  }
  @GetMapping("/okx/kline") public Object kline(@RequestParam String symbol, @RequestParam String market_type, @RequestParam String interval, HttpServletRequest q) { return Resp.ok(new ArrayList<>()); }
  @PostMapping("/okx/order/cancel") public Object cancelOrder(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = b.get("id") instanceof Number n ? n.longValue() : 0;
    Db.upd("UPDATE orders SET status='CANCELED' WHERE id=? AND user_id=?", id, uid); return Resp.ok("订单已撤销", null);
  }
  @GetMapping("/okx/position-mode") public Object positionMode(@RequestParam String market_type, HttpServletRequest q) { return Resp.ok(Resp.map("configured", false, "pos_mode", null, "hedged", false)); }
  @PostMapping("/okx/reconcile") public Object reconcile(HttpServletRequest q) { return Resp.ok("对账完成", Resp.eo()); }
}
