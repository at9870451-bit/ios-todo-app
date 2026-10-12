package com.quantokx.api;

public final class SystemLog {
    public static void write(String channel, String message) { write(channel, "info", message, 0); }
    public static void write(String channel, String level, String message, long userId) {
        try { Db.ins("INSERT INTO system_logs(user_id,level,channel,message) VALUES(?,?,?,?)", userId, level, channel, message); }
        catch (Exception e) { /* 静默 */ }
    }
    private SystemLog() {}
}
