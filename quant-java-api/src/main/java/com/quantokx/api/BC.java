package com.quantokx.api;
import java.security.MessageDigest;
import java.security.SecureRandom;
public final class BC {
    private static final SecureRandom RND = new SecureRandom();
    public static String hash(String pw) {
        byte[] salt = new byte[16]; RND.nextBytes(salt);
        return "$qk$" + b64(salt) + "$" + b64(sha256(concat(salt, pw.getBytes())));
    }
    public static boolean verify(String pw, String stored) {
        try {
            if (stored == null || !stored.startsWith("$qk$")) return false;
            String[] parts = stored.split("\\$");
            byte[] salt = unb64(parts[2]);
            return b64(sha256(concat(salt, pw.getBytes()))).equals(parts[3]);
        } catch (Exception e) { return false; }
    }
    static byte[] sha256(byte[] b) { try { return MessageDigest.getInstance("SHA-256").digest(b); } catch (Exception e) { throw new RuntimeException(e); } }
    static byte[] concat(byte[] a, byte[] b) { byte[] c = new byte[a.length + b.length]; System.arraycopy(a, 0, c, 0, a.length); System.arraycopy(b, 0, c, a.length, b.length); return c; }
    static String b64(byte[] b) { return java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(b); }
    static byte[] unb64(String s) { return java.util.Base64.getUrlDecoder().decode(s); }
    private BC() {}
}
