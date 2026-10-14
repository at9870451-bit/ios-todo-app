package com.quantokx.api;
import java.util.*;

/**
 * 会员服务：等级、定价、套餐、升级开通。
 * 到期时间存 users.membership_expire；续费自动从「当前到期日」往后叠加，未到期不损失剩余时长。
 */
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

    /** 到期时间（字符串，无则为 null）；已过期返回 null 但保留原值由调用方判断 */
    public static String expireOf(long userId) {
        Object v = Db.scalar("SELECT membership_expire FROM users WHERE id=?", userId);
        return v == null ? null : v.toString();
    }

    /** 剩余天数；无到期时间或已过期 => null；有效 => 天数（向上取整，至少 1） */
    public static Integer daysLeftOf(long userId) {
        String exp = expireOf(userId);
        if (exp == null || exp.isBlank()) return null;
        try {
            java.time.LocalDateTime until = java.time.LocalDateTime.parse(exp.replace(' ', 'T'));
            long mins = java.time.Duration.between(java.time.LocalDateTime.now(), until).toMinutes();
            if (mins <= 0) return null;
            return (int) Math.ceil(mins / 1440.0);
        } catch (Exception e) { return null; }
    }

    /** 是否仍在有效期内（level != free 且未过期） */
    public static boolean active(long userId, String level) {
        if ("free".equals(level) || level == null || level.isBlank()) return false;
        Integer d = daysLeftOf(userId);
        return d != null && d > 0;
    }

    /**
     * 开通/续费：从 max(现在, 当前到期日) 起叠加 months 个月。
     * 同为降级操作时（新等级低于当前），也按剩余时间处理，由业务层决定是否允许。
     */
    public static String upgrade(long userId, String level, int months) {
        String now = new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date());
        String base = now;
        String cur = expireOf(userId);
        if (cur != null && !cur.isBlank()) {
            try {
                java.time.LocalDateTime until = java.time.LocalDateTime.parse(cur.replace(' ', 'T'));
                if (until.isAfter(java.time.LocalDateTime.now())) base = cur; // 未到期 → 从到期日续
            } catch (Exception ignore) {}
        }
        String newExpire;
        try {
            java.time.LocalDateTime b = java.time.LocalDateTime.parse(base.replace(' ', 'T'));
            newExpire = b.plusMonths(months).format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        } catch (Exception e) {
            newExpire = java.time.LocalDateTime.now().plusMonths(months).format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        }
        Db.upd("UPDATE users SET level=?, membership_expire=? WHERE id=?", level, newExpire, userId);
        SystemLog.write("member", "会员开通/续费 user=" + userId + " level=" + level + " months=" + months + " 到期=" + newExpire);
        return newExpire;
    }

    /** 读取用户的会员 badge（含真实到期与剩余天数；过期自动降级为 free） */
    public static Map<String, Object> badgeOf(long userId) {
        Map<String, Object> u = Db.one("SELECT level, membership_expire FROM users WHERE id=?", userId);
        String level = u == null ? "free" : Svc.str(u.get("level"));
        String exp = u == null || u.get("membership_expire") == null ? null : u.get("membership_expire").toString();
        Integer days = null;
        String expireAt = null;
        if (!"free".equals(level) && exp != null && !exp.isBlank()) {
            try {
                java.time.LocalDateTime until = java.time.LocalDateTime.parse(exp.replace(' ', 'T'));
                long mins = java.time.Duration.between(java.time.LocalDateTime.now(), until).toMinutes();
                if (mins <= 0) {
                    // 已过期 → 自动降级
                    Db.upd("UPDATE users SET level='free', membership_expire=NULL WHERE id=? AND level<>'free'", userId);
                    level = "free";
                } else {
                    days = (int) Math.ceil(mins / 1440.0);
                    expireAt = exp;
                }
            } catch (Exception ignore) {}
        }
        return Resp.map("level", level, "name", name(level), "is_admin", false,
                "expire_at", expireAt, "days_left", days, "auto_renew", false);
    }

    private MemberSvc() {}
}
