package com.quantokx.api;

import javax.sql.DataSource;
import java.sql.*;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * 数据访问助手（v2.0 起后端为 MySQL）。
 * 保留原 SQLite 时代的静态 API（rows/one/ins/upd/scalar），
 * 由 Spring 容器启动时绑定 HikariDataSource，业务控制器零改动。
 * 读取结果统一归一化：LocalDateTime -> "yyyy-MM-dd HH:mm:ss" 字符串（兼容 App 端解码）。
 */
public final class Db {
    private static volatile DataSource ds;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public static void bind(DataSource d) { ds = d; }

    public static Connection cn() {
        try {
            DataSource d = ds;
            if (d == null) throw new IllegalStateException("DataSource 未绑定（应用启动未完成）");
            return d.getConnection();
        } catch (RuntimeException e) { throw e; }
        catch (Exception e) { throw new RuntimeException(e); }
    }

    static Object norm(Object v) {
        if (v == null) return null;
        if (v instanceof LocalDateTime t) return t.format(FMT);
        if (v instanceof LocalDate d) return d.toString();
        if (v instanceof Timestamp ts) return ts.toLocalDateTime().format(FMT);
        if (v instanceof java.time.LocalTime lt) return lt.toString();
        if (v instanceof java.math.BigInteger bi) return bi.longValue();
        if (v instanceof java.math.BigDecimal bd) {
            return bd.stripTrailingZeros().scale() <= 0 ? bd.longValue() : bd.doubleValue();
        }
        if (v instanceof byte[] b) return new String(b, java.nio.charset.StandardCharsets.UTF_8);
        return v;
    }

    public static List<Map<String, Object>> rows(String q, Object... a) {
        List<Map<String, Object>> o = new ArrayList<>();
        try (Connection c = cn(); PreparedStatement p = c.prepareStatement(q)) {
            for (int i = 0; i < a.length; i++) p.setObject(i+1, a[i]);
            try (ResultSet r = p.executeQuery()) {
                var md = r.getMetaData(); int n = md.getColumnCount();
                while (r.next()) {
                    Map<String, Object> m = new LinkedHashMap<>();
                    for (int i = 1; i <= n; i++) {
                        Object v = norm(r.getObject(i));
                        if (v != null) m.put(md.getColumnLabel(i).toLowerCase(), v);
                    }
                    o.add(m);
                }
            }
        } catch (Exception e) { throw new RuntimeException(e); }
        return o;
    }

    public static long ins(String q, Object... a) {
        try (Connection c = cn(); PreparedStatement p = c.prepareStatement(q, Statement.RETURN_GENERATED_KEYS)) {
            for (int i = 0; i < a.length; i++) p.setObject(i+1, a[i]);
            p.executeUpdate();
            try (ResultSet r = p.getGeneratedKeys()) { if (r.next()) return r.getLong(1); }
            return 0;
        } catch (Exception e) { throw new RuntimeException(e); }
    }

    public static long insert(String q, Object... a) { return ins(q, a); }

    public static int upd(String q, Object... a) {
        try (Connection c = cn(); PreparedStatement p = c.prepareStatement(q)) {
            for (int i = 0; i < a.length; i++) p.setObject(i+1, a[i]);
            return p.executeUpdate();
        } catch (Exception e) { throw new RuntimeException(e); }
    }

    public static Map<String, Object> one(String q, Object... a) {
        List<Map<String, Object>> r = rows(q, a);
        return r.isEmpty() ? null : r.get(0);
    }

    public static Object scalar(String q, Object... a) { return sc(q, a); }

    public static Object sc(String q, Object... a) {
        List<Map<String, Object>> r = rows(q, a);
        // 行不存在或整行值均为 NULL（rows 会跳过 null 列）=> 返回 null 而非抛异常
        if (r.isEmpty() || r.get(0).isEmpty()) return null;
        return r.get(0).values().iterator().next();
    }

    private Db() {}
}
