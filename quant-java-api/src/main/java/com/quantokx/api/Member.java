package com.quantokx.api;
import java.util.*;

public final class Member {
    public static final List<String> LEVELS = List.of("free", "gold", "diamond", "ultimate");
    public static final Map<String, String> NAMES = Map.of(
        "free", "免费版", "gold", "黄金版", "diamond", "钻石版", "ultimate", "至尊版"
    );
    public static int rank(String level) {
        return switch (level == null ? "free" : level) { case "gold" -> 1; case "diamond" -> 2; case "ultimate" -> 3; default -> 0; };
    }
    public static String levelName(String level) { return NAMES.getOrDefault(level, "免费版"); }
    public static Map<String, Object> limits(String level) {
        int r = rank(level);
        return Resp.map(
            "level", level, "name", levelName(level),
            "strategy_limit", r >= 3 ? 99 : r >= 2 ? 20 : r >= 1 ? 10 : 1,
            "ai_config_limit", r >= 3 ? 99 : r >= 2 ? 10 : r >= 1 ? 5 : 1,
            "account_limit", r >= 3 ? 10 : r >= 2 ? 5 : 2,
            "max_leverage", r >= 3 ? 125 : r >= 2 ? 50 : r >= 1 ? 20 : 3,
            "backtest_daily", r >= 3 ? -1 : r >= 2 ? 50 : r >= 1 ? 20 : 3,
            "ai_daily", r >= 3 ? -1 : r >= 2 ? 200 : r >= 1 ? 50 : 10,
            "multi_symbol_limit", r >= 3 ? 12 : r >= 2 ? 8 : r >= 1 ? 5 : 1,
            "auto_trade", r >= 1, "live_trade", r >= 3
        );
    }
    public static double priceFor(String level, int months) {
        double monthly = switch (level) { case "gold" -> 99; case "diamond" -> 299; case "ultimate" -> 599; default -> 0; };
        if (months >= 12) return monthly * 12 * 0.8;
        if (months >= 3) return monthly * 3 * 0.9;
        return monthly * months;
    }
    public static List<Map<String, Object>> plans() {
        List<Map<String, Object>> out = new ArrayList<>();
        for (String level : List.of("free", "gold", "diamond", "ultimate")) {
            double pm = priceFor(level, 1);
            out.add(Resp.map(
                "id", String.valueOf(out.size() + 1), "level", level, "name", levelName(level),
                "price_month", String.format("%.2f", pm), "price_quarter", String.format("%.2f", pm * 3 * 0.9),
                "price_year", String.format("%.2f", pm * 12 * 0.8),
                "strategy_limit", r(level) >= 3 ? 99 : r(level) >= 2 ? 20 : r(level) >= 1 ? 10 : 1,
                "ai_config_limit", r(level) >= 3 ? 99 : r(level) >= 2 ? 10 : r(level) >= 1 ? 5 : 1,
                "account_limit", r(level) >= 3 ? 10 : 2, "max_leverage", r(level) >= 3 ? 125 : r(level) >= 2 ? 50 : r >= 1 ? 20 : 3,
                "backtest_daily", r(level) >= 3 ? -1 : r(level) >= 2 ? 50 : 3,
                "ai_daily", r(level) >= 3 ? -1 : r(level) >= 2 ? 200 : 10,
                "multi_symbol_limit", r(level) >= 3 ? 12 : r(level) >= 2 ? 8 : 1,
                "auto_trade", r(level) >= 1 ? 1 : 0, "live_trade", r(level) >= 3 ? 1 : 0,
                "features", String.join("\n", List.of("行情与交易", "AI 分析", "自动交易", "止损止盈")),
                "sort", out.size() + 1, "enabled", 1
            ));
        }
        return out;
    }
    private static int r(String level) { return rank(level); }
    private Member() {}
}
