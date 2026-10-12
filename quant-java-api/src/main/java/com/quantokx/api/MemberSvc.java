package com.quantokx.api;
import java.util.*;

public final class MemberSvc {
    public static final List<String> LEVELS = List.of("free", "gold", "diamond", "ultimate");
    public static final Map<String, String> NAMES = Map.of("free","免费版","gold","黄金版","diamond","钻石版","ultimate","至尊版");
    public static int rank(String level) { return switch (level == null ? "free" : level) { case "gold" -> 1; case "diamond" -> 2; case "ultimate" -> 3; default -> 0; }; }
    public static String name(String level) { return NAMES.getOrDefault(level, "免费版"); }
    public static double priceFor(String level, int months) {
        double monthly = switch (level) { case "gold" -> 99; case "diamond" -> 299; case "ultimate" -> 599; default -> 0; };
        if (months >= 12) return monthly * 12 * 0.8;
        if (months >= 3) return monthly * 3 * 0.9;
        return monthly * months;
    }
    public static void upgrade(long userId, String level, int months) {
        String expire = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date());
        Db.upd("UPDATE users SET level=?, membership_expire=? WHERE id=?", level, expire, userId);
        SystemLog.write("member", "会员升级 user=" + userId + " level=" + level + " months=" + months);
    }
    private MemberSvc() {}
}
