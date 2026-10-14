package com.quantokx.api;

import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Redis 访问包装：Redis 可用时全部走 Redis；不可用时自动降级为进程内 Map（保证服务不中断）。
 * 用于：iOS 会话（QBSESSID）、Console JWT 会话、登录限流计数。
 */
@Component
public final class Rds {
    private static volatile StringRedisTemplate tpl;
    private static volatile boolean up = false;
    private static final Map<String, String> MEM = new ConcurrentHashMap<>();
    private static final Map<String, Long> EXP = new ConcurrentHashMap<>();

    public Rds(StringRedisTemplate t) { tpl = t; }

    /** 探测 Redis 可用性（首次使用与定时巡检调用） */
    public static boolean probe() {
        StringRedisTemplate t = tpl;
        if (t == null) { up = false; return false; }
        try { t.opsForValue().get("qb:probe"); up = true; } catch (Exception e) { up = false; }
        return up;
    }

    public static boolean available() {
        if (!up) probe();
        return up;
    }

    private static void gc() {
        if (EXP.size() > 4096) {
            long now = System.currentTimeMillis();
            EXP.entrySet().removeIf(e -> e.getValue() != 0 && e.getValue() < now);
        }
    }

    public static void set(String k, String v, long ttlSec) {
        StringRedisTemplate t = tpl;
        if (up) {
            try { t.opsForValue().set(k, v, Duration.ofSeconds(ttlSec)); return; } catch (Exception e) { up = false; }
        }
        MEM.put(k, v);
        EXP.put(k, ttlSec <= 0 ? 0L : System.currentTimeMillis() + ttlSec * 1000);
        gc();
    }

    /** SETNX：key 不存在时写入并返回 true */
    public static boolean setNx(String k, String v, long ttlSec) {
        StringRedisTemplate t = tpl;
        if (up) {
            try { return Boolean.TRUE.equals(t.opsForValue().setIfAbsent(k, v, Duration.ofSeconds(ttlSec))); }
            catch (Exception e) { up = false; }
        }
        gc();
        long now = System.currentTimeMillis();
        Long ex = EXP.get(k);
        if (ex != null && ex != 0 && ex < now) { MEM.remove(k); EXP.remove(k); }
        Object old = MEM.putIfAbsent(k, v);
        if (old == null) { EXP.put(k, ttlSec <= 0 ? 0L : now + ttlSec * 1000); return true; }
        return false;
    }

    public static String get(String k) {
        StringRedisTemplate t = tpl;
        if (up) {
            try { return t.opsForValue().get(k); } catch (Exception e) { up = false; }
        }
        Long ex = EXP.get(k);
        if (ex != null && ex != 0 && ex < System.currentTimeMillis()) { MEM.remove(k); EXP.remove(k); return null; }
        return MEM.get(k);
    }

    public static void del(String k) {
        StringRedisTemplate t = tpl;
        if (up) {
            try { t.delete(k); return; } catch (Exception e) { up = false; }
        }
        MEM.remove(k); EXP.remove(k);
    }

    public static void expire(String k, long ttlSec) {
        StringRedisTemplate t = tpl;
        if (up) {
            try { t.expire(k, Duration.ofSeconds(ttlSec)); return; } catch (Exception e) { up = false; }
        }
        Long ex = EXP.get(k);
        if (ex != null) EXP.put(k, ttlSec <= 0 ? 0L : System.currentTimeMillis() + ttlSec * 1000);
    }

    /** 自增并设置过期（用于限流计数），返回自增后的值 */
    public static long incr(String k, long ttlSec) {
        StringRedisTemplate t = tpl;
        if (up) {
            try {
                Long v = t.opsForValue().increment(k);
                if (v != null && v == 1) t.expire(k, Duration.ofSeconds(ttlSec));
                return v == null ? 1 : v;
            } catch (Exception e) { up = false; }
        }
        long v;
        try { v = Long.parseLong(MEM.getOrDefault(k, "0")) + 1; } catch (Exception e) { v = 1; }
        MEM.put(k, String.valueOf(v));
        Long ex = EXP.get(k);
        if (ex == null || ex == 0) EXP.put(k, System.currentTimeMillis() + ttlSec * 1000);
        return v;
    }
}
