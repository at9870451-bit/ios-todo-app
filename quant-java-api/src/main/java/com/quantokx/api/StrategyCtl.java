package com.quantokx.api;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;

@RestController @RequestMapping("/api")
public class StrategyCtl {
  Long uid(HttpServletRequest q) { return (Long) q.getAttribute("uid"); }

  @GetMapping("/strategies") public Object list(HttpServletRequest q) {
    return Resp.ok(Db.rows("SELECT * FROM strategies WHERE user_id=? ORDER BY id DESC", uid(q)));
  }
  @GetMapping("/strategy/meta") public Object meta() {
    var items = new LinkedHashMap<String, Object>();
    for (String k : java.util.Arrays.asList("ma","ema","macd","rsi","boll","kdj","atr","donchian","supertrend","momentum","grid","dca","volume","macd_rsi","signal","martin","dip","range_grid","fvg","ob","sweep")) {
      items.put(k, Resp.map("name", StrategyEngine.strategyName(k), "group", "趋势", "markets", List.of("spot","swap"), "desc", StrategyEngine.strategyDesc(k), "params", StrategyEngine.paramsFor(k)));
    }
    return Resp.ok(Resp.map("strategies", items, "groups", Resp.map("趋势", "趋势", "震荡", "震荡"), "markets", Resp.map("spot","Spot 现货","swap","Swap 永续"), "direction_modes", Resp.map("long_only","只做多","short_only","只做空","long_short","多空双向"), "modes", Resp.map("paper","本地模拟","testnet","OKX 模拟盘","live","实盘"), "intervals", java.util.Arrays.asList("1m","3m","5m","15m","30m","1h","2h","4h","6h","12h","1d")));
  }
  @PostMapping("/strategy/create") public Object create(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); String name = Svc.str(b.get("name"));
    if (name.isEmpty()) return Resp.map("code","STRATEGY_ERROR","message","请填写策略名称","data",null);
    String sym = Svc.str(b.getOrDefault("symbol", b.getOrDefault("symbols", "BTC-USDT-SWAP")));
    List<String> symbols = Svc.normalizeSymbols(sym, Svc.str(b.getOrDefault("market_type", "swap")));
    String symStr = String.join(",", symbols);
    long id = Db.ins("INSERT INTO strategies(user_id,name,class_name,market_type,direction_mode,symbol,symbols,interval,mode,position_percent,leverage,min_confidence,quantity,td_mode,parameters) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
      uid, name, Svc.str(b.get("class_name")), Svc.str(b.getOrDefault("market_type","swap")), Svc.str(b.getOrDefault("direction_mode","long_only")), symbols.get(0), symStr, Svc.str(b.getOrDefault("interval","15m")), Svc.str(b.getOrDefault("mode","paper")), Svc.num(b.get("position_percent"),5), ((Number)b.getOrDefault("leverage",3)).intValue(), Svc.num(b.get("min_confidence"),0.6), Svc.str(b.getOrDefault("quantity","0.001")), Svc.str(b.getOrDefault("td_mode","cross")), Svc.str(b.getOrDefault("parameters","{}")));
    return Resp.ok("策略已创建", Db.one("SELECT * FROM strategies WHERE id=?", id));
  }
  @PostMapping("/strategy/update") public Object update(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = ((Number)b.get("id")).longValue();
    Db.upd("UPDATE strategies SET name=? WHERE id=? AND user_id=?", Svc.str(b.get("name")), id, uid);
    return Resp.ok("策略已更新", Db.one("SELECT * FROM strategies WHERE id=?", id));
  }
  @PostMapping("/strategy/delete") public Object delete(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = ((Number)b.get("id")).longValue();
    Db.upd("DELETE FROM strategies WHERE id=? AND user_id=?", id, uid); return Resp.ok("策略已删除", null);
  }
  @PostMapping("/strategy/start") public Object start(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = ((Number)b.get("id")).longValue();
    Db.upd("UPDATE strategies SET enabled=1 WHERE id=? AND user_id=?", id, uid);
    return Resp.ok("策略已启动", Resp.map("id", id, "enabled", true));
  }
  @PostMapping("/strategy/stop") public Object stop(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    long uid = uid(q); long id = ((Number)b.get("id")).longValue();
    Db.upd("UPDATE strategies SET enabled=0 WHERE id=? AND user_id=?", id, uid);
    return Resp.ok("策略已停止", Resp.map("id", id, "enabled", false));
  }
  @GetMapping("/strategy/monitor") public Object monitor(HttpServletRequest q) {
    return Resp.ok(new ArrayList<>());
  }
  @PostMapping("/strategy/backtest") public Object backtest(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    String sym = Svc.str(b.getOrDefault("symbol", "BTC-USDT-SWAP"));
    return Resp.ok(Resp.map("symbol", sym, "interval", Svc.str(b.get("interval")), "initial_capital", 10000.0, "final_capital", 10000.0, "total_return", 0, "return_rate", 0, "max_drawdown", 0, "win_rate", 0, "win_count", 0, "loss_count", 0, "profit_factor", 0, "trade_count", 0, "equity_curve", new ArrayList<>()));
  }
  @PostMapping("/strategy/analyze") public Object analyze(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    String sym = Svc.str(b.getOrDefault("symbol", "BTC-USDT-SWAP"));
    return Resp.ok(Resp.map("signal", "HOLD", "confidence", 0.5, "price", 0, "reason", "信号分析", "symbol", sym, "strategy", Svc.str(b.get("class_name"))));
  }
}
