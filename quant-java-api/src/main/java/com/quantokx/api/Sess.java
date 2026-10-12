package com.quantokx.api;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.security.SecureRandom;

public final class Sess {
    public static final String COOKIE = "QBSESSID";
    private static final SecureRandom RND = new SecureRandom();
    private static final Map<String, String[]> SESSIONS = new ConcurrentHashMap<>();

    public record AuthUser(long id, String username, String nickname, String email, String role, String membershipLevel, boolean liveTrading) {}
    public record Reg(boolean ok, String message, long userId) {}
    public record Login(boolean ok, String message, long userId) {}

    static String hex(int n) {
        byte[] b = new byte[n]; RND.nextBytes(b);
        StringBuilder s = new StringBuilder();
        for (byte x : b) s.append(String.format("%02x", x));
        return s.toString();
    }
    public static String newToken() { return hex(24); }
    public static String newCsrf() { return hex(24); }
    public static String create(long uid) { String t = newToken(); SESSIONS.put(t, new String[]{String.valueOf(uid), newCsrf()}); return t; }
    public static String csrfOf(String t) { String[] s = SESSIONS.get(t); return s == null ? "" : s[1]; }
    public static Long userIdOf(String t) { String[] s = SESSIONS.get(t); return s == null ? null : Long.valueOf(s[0]); }
    public static void drop(String t) { SESSIONS.remove(t); }

    public static Reg register(String username, String password, String email) {
        if (username == null || username.isBlank()) return new Reg(false, "请输入用户名", 0);
        if (!username.matches("[A-Za-z0-9_@.-]{3,32}")) return new Reg(false, "用户名需为 3~32 位字母、数字、下划线、点、短横线或 @", 0);
        if (password == null || password.length() < 8) return new Reg(false, "密码至少 8 位", 0);
        Long exists = (Long) Db.scalar("SELECT id FROM users WHERE username=?", username);
        if (exists != null) return new Reg(false, "用户名已被注册", 0);
        String hash = BC.hash(password);
        long id = Db.insert("INSERT INTO users(username,pass_hash,role,level) VALUES(?,?, 'user','free')", username, hash);
        return new Reg(true, "注册成功", id);
    }

    public static Login login(String username, String password) {
        if (username == null || username.isBlank() || password == null || password.isBlank())
            return new Login(false, "请输入用户名和密码", 0);
        Map<String, Object> u = Db.one("SELECT id,pass_hash,status FROM users WHERE username=?", username);
        if (u == null) return new Login(false, "用户名或密码错误", 0);
        if (((Number) u.get("status")).intValue() != 1) return new Login(false, "账号已禁用", 0);
        if (!BC.verify(password, (String) u.get("pass_hash"))) return new Login(false, "用户名或密码错误", 0);
        return new Login(true, "登录成功", ((Number) u.get("id")).longValue());
    }

    public static final class BC {
        private static final int ITER = 12000;
        public static String hash(String p) {
            byte[] salt = new byte[16]; RND.nextBytes(salt);
            return "$qk$" + ITER + "$" + Hex.encode(salt) + "$" + Hex.encode(pbkdf2(p, salt, ITER));
        }
        public static boolean verify(String p, String stored) {
            try {
                if (stored == null) return false;
                String[] parts = stored.split("\\$");
                if (parts.length != 5 || !parts[1].equals("qk")) return false;
                byte[] salt = Unhex.decode(parts[3]);
                byte[] expect = Unhex.decode(parts[4]);
                return java.security.MessageDigest.isEqual(pbkdf2(p, salt, Integer.parseInt(parts[2])), expect);
            } catch (Exception e) { return false; }
        }
        private static byte[] pbkdf2(String pw, byte[] salt, int iter) {
            try {
                var spec = new javax.crypto.spec.PBEKeySpec(pw.toCharArray(), salt, iter, 256);
                return javax.crypto.SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded();
            } catch (Exception e) { throw new RuntimeException(e); }
        }
    }

    public static final class Hex {
        private static final char[] C = "0123456789abcdef".toCharArray();
        public static String encode(byte[] b) {
            char[] o = new char[b.length * 2];
            for (int i = 0; i < b.length; i++) { o[i*2] = C[(b[i] >> 4) & 0xF]; o[i*2+1] = C[b[i] & 0xF]; }
            return new String(o);
        }
    }
    public static final class Unhex {
        public static byte[] decode(String s) {
            byte[] o = new byte[s.length() / 2];
            for (int i = 0; i < o.length; i++) o[i] = (byte) Integer.parseInt(s.substring(i*2, i*2+2), 16);
            return o;
        }
    }
}
