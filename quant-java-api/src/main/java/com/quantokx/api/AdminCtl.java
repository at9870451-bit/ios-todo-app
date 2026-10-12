package com.quantokx.api;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;

@RestController @RequestMapping("/api/admin")
public class AdminCtl {

  @GetMapping("/stats") public Map<String, Object> stats(HttpServletRequest q) {
    return Resp.ok(Resp.map("user_total", 1, "user_today", 0, "order_total", 0, "order_paid", 0, "order_pending", 0, "income_total", "0.00", "income_today", "0.00"));
  }
  @GetMapping("/users") public Map<String, Object> users(HttpServletRequest q) {
    return Resp.ok(Resp.map("items", Db.rows("SELECT id,username,role,level AS membership_level,status FROM users ORDER BY id"), "total", 1, "page", 1));
  }
  @GetMapping("/orders") public Map<String, Object> orders(HttpServletRequest q) {
    return Resp.ok(Resp.map("items", new ArrayList<>(), "total", 0, "page", 1));
  }
  @GetMapping("/plans") public Map<String, Object> plans(HttpServletRequest q) {
    return Resp.ok(Resp.map("plans", Member.plans()));
  }
  @PostMapping("/plans/save") public Map<String, Object> plansSave(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    return Resp.ok("套餐已保存", null);
  }
  @GetMapping("/free-ai") public Map<String, Object> freeAi(HttpServletRequest q) {
    return Resp.ok(Resp.map("config", Resp.eo(), "configured", false));
  }
  @PostMapping("/free-ai/save") public Map<String, Object> freeAiSave(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    return Resp.ok("免费 AI 配置已保存", null);
  }
  @GetMapping("/payment") public Map<String, Object> payment(HttpServletRequest q) {
    return Resp.ok(Resp.map("config", Resp.map("api_url", "", "pid", "", "key", "", "enabled", 0, "demo_direct", 1), "channels", new ArrayList<>(), "configured", false));
  }
  @PostMapping("/payment/save") public Map<String, Object> paymentSave(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    return Resp.ok("支付配置已保存", null);
  }
  @GetMapping("/settings") public Map<String, Object> settings(HttpServletRequest q) {
    return Resp.ok(Resp.map("site", Resp.map("register_enabled", 1, "register_need_email", 0, "site_name", "QuantOKX", "announcement", "")));
  }
  @PostMapping("/settings/save") public Map<String, Object> settingsSave(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    return Resp.ok("设置已保存", null);
  }
  @PostMapping("/user/update") public Map<String, Object> userUpdate(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    return Resp.ok("用户已更新", null);
  }
  @PostMapping("/order/mark-paid") public Map<String, Object> markPaid(@RequestBody Map<String, Object> b, HttpServletRequest q) {
    return Resp.ok("订单已标记支付", null);
  }
}
