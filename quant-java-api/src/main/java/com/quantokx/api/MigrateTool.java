package com.quantokx.api;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.sql.*;
import java.util.*;

/**
 * SQLite(qk.db) -> MySQL 数据迁移工具。
 * 用法（在服务器上，与新 jar 同目录）：
 *   java -jar app.jar --migrate --sqlite=/opt/quantokx-java/data/qk.db
 * 行为：按表迁移，保留原主键；目标表已有数据时先清空（幂等，可重复执行）；
 *      users 表补齐 v2.0 新列（nickname/email/status/created_at 等）；
 *      密码哈希 $qk$12000$salt$hash 原样搬运，迁移后老用户可直接登录。
 * 迁移完成后进程自动退出（不启动 Web 服务）。
 */
@Component
@Order(1)
public class MigrateTool implements ApplicationRunner {

    /** 迁移顺序（被引用表在前） */
    private static final String[] TABLES = {
        "users", "sessions", "ai_configs", "ai_signals", "strategies", "strategy_runs",
        "orders", "positions", "trades", "trading_logs", "system_logs", "risk_configs",
        "member_orders", "chat_sessions", "chat_messages", "okx_accounts"
    };

    private final ApplicationArguments args;

    public MigrateTool(ApplicationArguments args) { this.args = args; }

    @Override
    public void run(ApplicationArguments a) {
        if (!args.containsOption("migrate")) return;   // 常规启动不做迁移
        String sqlitePath = opt("sqlite", "/opt/quantokx-java/data/qk.db");
        System.out.println("========== SQLite -> MySQL 数据迁移 ==========");
        System.out.println("源库: " + sqlitePath);
        int ok = 0, skip = 0;
        try (Connection src = DriverManager.getConnection("jdbc:sqlite:" + sqlitePath)) {
            for (String t : TABLES) {
                try {
                    long n = migrateTable(src, t);
                    if (n < 0) { skip++; System.out.printf("  [跳过] %-16s 源库无此表%n", t); }
                    else { ok++; System.out.printf("  [完成] %-16s 迁移 %d 行%n", t, n); }
                } catch (Exception e) {
                    System.out.printf("  [失败] %-16s %s%n", t, e.getMessage());
                }
            }
        } catch (Exception e) {
            System.err.println("无法打开 SQLite 源库: " + e.getMessage());
            System.exit(2);
        }
        System.out.printf("迁移结束：成功 %d 张表，跳过 %d 张%n", ok, skip);
        System.out.println("=============================================");
        System.exit(0);
    }

    private String opt(String name, String def) {
        List<String> v = args.getOptionValues(name);
        return (v == null || v.isEmpty()) ? def : v.get(0);
    }

    /** @return 迁移行数；源库无此表返回 -1 */
    private long migrateTable(Connection src, String table) throws Exception {
        if (!srcTableExists(src, table)) return -1;
        List<String> srcCols = columns(src, table);
        List<String> dstCols = columns(Db.cn(), table);
        if (dstCols.isEmpty()) throw new IllegalStateException("目标表不存在（请先启动一次新版本以建表）");

        List<String> cols = new ArrayList<>();
        for (String c : srcCols) if (dstCols.contains(c) && !"id".equals(c)) cols.add(c);
        // 迁移后老用户 created_at 兜底为当前时间（SQLite 库无该列）
        boolean usersTable = "users".equals(table);

        List<Map<String, Object>> rows = new ArrayList<>();
        try (Statement s = src.createStatement(); ResultSet r = s.executeQuery("SELECT * FROM " + table)) {
            while (r.next()) {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("id", r.getLong("id"));
                for (String c : cols) m.put(c, r.getObject(c));
                rows.add(m);
            }
        }
        if (rows.isEmpty()) return 0;

        try (Connection dst = Db.cn()) {
            dst.setAutoCommit(false);
            try (Statement s = dst.createStatement()) { s.executeUpdate("DELETE FROM " + table); }
            List<String> insCols = new ArrayList<>(cols);
            insCols.add("id");
            if (usersTable) { insCols.add("created_at"); insCols.add("status"); insCols.add("nickname"); }
            String sql = "INSERT INTO " + table + "(" + String.join(",", insCols) + ") VALUES(" +
                    String.join(",", Collections.nCopies(insCols.size(), "?")) + ")";
            try (PreparedStatement p = dst.prepareStatement(sql)) {
                int batch = 0;
                for (Map<String, Object> m : rows) {
                    int i = 1;
                    for (String c : cols) p.setObject(i++, m.get(c));
                    p.setObject(i++, m.get("id"));
                    if (usersTable) {
                        p.setObject(i++, new Timestamp(System.currentTimeMillis()));
                        p.setObject(i++, 1);
                        p.setObject(i, m.get("username"));
                    }
                    p.addBatch();
                    if (++batch % 500 == 0) p.executeBatch();
                }
                p.executeBatch();
            }
            dst.commit();
        }
        return rows.size();
    }

    private static boolean srcTableExists(Connection c, String t) throws Exception {
        try (ResultSet r = c.getMetaData().getTables(null, null, t, null)) { return r.next(); }
    }

    private static List<String> columns(Connection c, String t) throws Exception {
        List<String> out = new ArrayList<>();
        try (ResultSet r = c.getMetaData().getColumns(c.getCatalog(), null, t, null)) {
            while (r.next()) out.add(r.getString("COLUMN_NAME").toLowerCase());
        }
        return out;
    }
}
