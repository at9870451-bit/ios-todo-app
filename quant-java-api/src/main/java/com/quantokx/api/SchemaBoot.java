package com.quantokx.api;

import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

/**
 * 数据库初始化：MySQL 8 全量建表 + 列自愈（旧库升级时补列）+ 种子数据。
 * 幂等：可反复执行；不会覆盖已有业务数据。
 */
@Component
public final class SchemaBoot {

    public SchemaBoot(DataSource ds) {
        Db.bind(ds);
        init();
    }

    public static void init() {
        try (Connection c = Db.cn(); Statement s = c.createStatement()) {
            for (String q : DDL) s.executeUpdate(q);
            heal(c);
            seed(c);
        } catch (Exception e) {
            throw new RuntimeException("数据库初始化失败: " + e.getMessage(), e);
        }
    }

    private static final String[] DDL = {
        // ---------- App 业务表（原 SQLite 16 张，迁移到 MySQL） ----------
        "CREATE TABLE IF NOT EXISTS users(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT," +
            "username VARCHAR(64) NOT NULL UNIQUE," +
            "pass_hash VARCHAR(255) NOT NULL," +
            "nickname VARCHAR(64) DEFAULT NULL," +
            "email VARCHAR(128) DEFAULT NULL," +
            "role VARCHAR(16) NOT NULL DEFAULT 'user'," +
            "level VARCHAR(16) NOT NULL DEFAULT 'free'," +
            "live_trading TINYINT NOT NULL DEFAULT 0," +
            "status TINYINT NOT NULL DEFAULT 1," +
            "created_at DATETIME DEFAULT CURRENT_TIMESTAMP," +
            "last_login_at DATETIME DEFAULT NULL," +
            "last_login_ip VARCHAR(64) DEFAULT NULL," +
            "register_ip VARCHAR(64) DEFAULT NULL," +
            "ban_reason VARCHAR(255) DEFAULT NULL," +
            "ban_until DATETIME DEFAULT NULL," +
            "membership_expire DATETIME DEFAULT NULL," +
            "KEY idx_users_created(created_at), KEY idx_users_status(status), KEY idx_users_email(email)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci",

        "CREATE TABLE IF NOT EXISTS sessions(token VARCHAR(64) PRIMARY KEY, user_id BIGINT NOT NULL, csrf VARCHAR(64) NOT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS ai_configs(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, name VARCHAR(128), provider_type VARCHAR(32) DEFAULT 'openai'," +
            "api_style VARCHAR(32) DEFAULT 'chat_completions', api_url VARCHAR(255), model VARCHAR(128), api_key VARCHAR(512)," +
            "temperature DOUBLE DEFAULT 0.2, max_tokens INT DEFAULT 4000, mode VARCHAR(16) DEFAULT 'analysis', enabled TINYINT DEFAULT 0," +
            "running TINYINT DEFAULT 0, trade_mode VARCHAR(16) DEFAULT 'demo', leverage INT DEFAULT 5, auto_symbol VARCHAR(64)," +
            "auto_symbols VARCHAR(512), auto_interval VARCHAR(16) DEFAULT '15m', auto_period_seconds INT DEFAULT 300," +
            "auto_quantity VARCHAR(32) DEFAULT '0.001', auto_position_percent DOUBLE DEFAULT 2, capital_usdt DOUBLE DEFAULT 0," +
            "min_confidence DOUBLE DEFAULT 0.6, td_mode VARCHAR(16) DEFAULT 'cross', run_count INT DEFAULT 0, trade_count INT DEFAULT 0," +
            "last_run_at DATETIME DEFAULT NULL, last_signal TEXT, error_message TEXT, test_status VARCHAR(16), test_message VARCHAR(255)," +
            "created_at DATETIME DEFAULT CURRENT_TIMESTAMP, KEY idx_ai_cfg_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS ai_signals(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, config_id BIGINT, symbol VARCHAR(64) NOT NULL," +
            "market_type VARCHAR(16) DEFAULT 'swap', `signal` VARCHAR(32) NOT NULL, confidence DOUBLE DEFAULT 0, entry DOUBLE," +
            "stop_loss DOUBLE, take_profit DOUBLE, reason TEXT, executed TINYINT DEFAULT 0, created_at DATETIME DEFAULT CURRENT_TIMESTAMP," +
            "KEY idx_sig_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS ai_reviews(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, config_id BIGINT, order_id BIGINT, symbol VARCHAR(64)," +
            "side VARCHAR(16), entry_price DOUBLE, exit_price DOUBLE, pnl DOUBLE DEFAULT 0, leverage INT DEFAULT 1," +
            "result VARCHAR(16), score INT DEFAULT 0, review TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, KEY idx_rev_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS strategies(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, name VARCHAR(128) NOT NULL, class_name VARCHAR(64) NOT NULL," +
            "market_type VARCHAR(16) DEFAULT 'swap', direction_mode VARCHAR(16) DEFAULT 'long_only', symbol VARCHAR(64), symbols VARCHAR(512)," +
            "`interval` VARCHAR(16) DEFAULT '15m', mode VARCHAR(16) DEFAULT 'paper', enabled TINYINT DEFAULT 0, leverage INT DEFAULT 3," +
            "position_percent DOUBLE DEFAULT 5, min_confidence DOUBLE DEFAULT 0.6, quantity VARCHAR(32) DEFAULT '0.001'," +
            "td_mode VARCHAR(16) DEFAULT 'cross', parameters TEXT, run_interval INT DEFAULT 60, created_at DATETIME DEFAULT CURRENT_TIMESTAMP," +
            "KEY idx_stg_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS strategy_runs(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, strategy_id BIGINT NOT NULL, status VARCHAR(16) DEFAULT 'NEVER'," +
            "last_signal VARCHAR(64), last_run_at DATETIME DEFAULT NULL, error_message TEXT, KEY idx_run_stg(strategy_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS orders(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, account_id BIGINT, symbol VARCHAR(64) NOT NULL," +
            "market_type VARCHAR(16) DEFAULT 'swap', mode VARCHAR(16) DEFAULT 'paper', side VARCHAR(16) NOT NULL, position_side VARCHAR(16)," +
            "order_type VARCHAR(16) DEFAULT 'MARKET', price VARCHAR(32) DEFAULT '0', quantity VARCHAR(32) DEFAULT '0'," +
            "executed_quantity VARCHAR(32) DEFAULT '0', status VARCHAR(24) DEFAULT 'NEW', source VARCHAR(24) DEFAULT 'MANUAL'," +
            "stop_loss VARCHAR(32), take_profit VARCHAR(32), okx_order_id VARCHAR(64), client_order_id VARCHAR(64)," +
            "created_at DATETIME DEFAULT CURRENT_TIMESTAMP, KEY idx_ord_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS positions(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, account_id BIGINT, symbol VARCHAR(64) NOT NULL," +
            "market_type VARCHAR(16) DEFAULT 'swap', position_side VARCHAR(16) DEFAULT 'BOTH', quantity VARCHAR(32) DEFAULT '0'," +
            "entry_price VARCHAR(32) DEFAULT '0', mark_price VARCHAR(32) DEFAULT '0', unrealized_pnl VARCHAR(32) DEFAULT '0'," +
            "leverage INT DEFAULT 1, status VARCHAR(16) DEFAULT 'OPEN', created_at DATETIME DEFAULT CURRENT_TIMESTAMP, KEY idx_pos_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS trades(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, symbol VARCHAR(64) NOT NULL, side VARCHAR(16) NOT NULL," +
            "price VARCHAR(32) DEFAULT '0', quantity VARCHAR(32) DEFAULT '0', fee VARCHAR(32) DEFAULT '0', trade_time DATETIME DEFAULT NULL," +
            "created_at DATETIME DEFAULT CURRENT_TIMESTAMP, KEY idx_trd_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS trading_logs(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT, symbol VARCHAR(64), source VARCHAR(32), `signal` VARCHAR(32)," +
            "price VARCHAR(32), result VARCHAR(32), pnl VARCHAR(32), created_at DATETIME DEFAULT CURRENT_TIMESTAMP, KEY idx_tlog_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS system_logs(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT, level VARCHAR(16) DEFAULT 'info', channel VARCHAR(32) DEFAULT 'system'," +
            "message TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, KEY idx_slog_created(created_at)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS risk_configs(" +
            "user_id BIGINT PRIMARY KEY, single_position_percent DOUBLE DEFAULT 5, max_total_position_percent DOUBLE DEFAULT 20," +
            "single_loss_percent DOUBLE DEFAULT 2, daily_loss_percent DOUBLE DEFAULT 5, daily_trade_limit INT DEFAULT 20," +
            "consecutive_loss_limit INT DEFAULT 3, max_leverage INT DEFAULT 20, max_positions INT DEFAULT 6, emergency_stop TINYINT DEFAULT 0" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS member_orders(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, trade_no VARCHAR(64), level VARCHAR(16) NOT NULL," +
            "months INT DEFAULT 1, amount VARCHAR(32) DEFAULT '0', status VARCHAR(16) DEFAULT 'paid', channel VARCHAR(16) DEFAULT 'alipay'," +
            "paid_at DATETIME DEFAULT NULL, created_at DATETIME DEFAULT CURRENT_TIMESTAMP," +
            "KEY idx_mo_user(user_id), KEY idx_mo_created(created_at)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS chat_sessions(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, title VARCHAR(255) DEFAULT '新对话'," +
            "updated_at DATETIME DEFAULT CURRENT_TIMESTAMP, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, KEY idx_cs_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS chat_messages(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, session_id BIGINT NOT NULL, role VARCHAR(16) NOT NULL, content MEDIUMTEXT NOT NULL," +
            "attachments TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, KEY idx_cm_sess(session_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS okx_accounts(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, name VARCHAR(64), api_key VARCHAR(255), secret_key VARCHAR(255)," +
            "passphrase VARCHAR(255), is_demo TINYINT DEFAULT 1, enabled TINYINT DEFAULT 1, created_at DATETIME DEFAULT CURRENT_TIMESTAMP," +
            "KEY idx_okxacc_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        // ---------- 管理后台表 ----------
        "CREATE TABLE IF NOT EXISTS sys_role(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(64) NOT NULL, code VARCHAR(64) NOT NULL UNIQUE, perms TEXT," +
            "remark VARCHAR(255), created_at DATETIME DEFAULT CURRENT_TIMESTAMP" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS sys_admin(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, username VARCHAR(64) NOT NULL UNIQUE, password_hash VARCHAR(128) NOT NULL," +
            "nickname VARCHAR(64), role_id BIGINT NOT NULL DEFAULT 2, status TINYINT NOT NULL DEFAULT 1," +
            "last_login_at DATETIME DEFAULT NULL, last_login_ip VARCHAR(64), created_at DATETIME DEFAULT CURRENT_TIMESTAMP," +
            "updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS sys_operation_log(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, admin_id BIGINT, admin_name VARCHAR(64), action VARCHAR(64)," +
            "method VARCHAR(8), path VARCHAR(255), params TEXT, ip VARCHAR(64), status INT DEFAULT 200," +
            "created_at DATETIME DEFAULT CURRENT_TIMESTAMP, KEY idx_oplog_created(created_at), KEY idx_oplog_admin(admin_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS sys_config(" +
            "k VARCHAR(64) PRIMARY KEY, v TEXT, remark VARCHAR(255), updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS app_announcement(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, title VARCHAR(128) NOT NULL, content TEXT, type VARCHAR(16) DEFAULT 'notice'," +
            "enabled TINYINT DEFAULT 1, start_at DATETIME DEFAULT NULL, end_at DATETIME DEFAULT NULL," +
            "created_at DATETIME DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS app_version(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, platform VARCHAR(16) DEFAULT 'iOS', version VARCHAR(32) NOT NULL, build INT DEFAULT 1," +
            "force_update TINYINT DEFAULT 0, download_url VARCHAR(255), notes TEXT, enabled TINYINT DEFAULT 1," +
            "created_at DATETIME DEFAULT CURRENT_TIMESTAMP" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS app_user_login_log(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, ip VARCHAR(64), ua VARCHAR(512), device_model VARCHAR(64)," +
            "os_version VARCHAR(32), app_version VARCHAR(32), success TINYINT DEFAULT 1, created_at DATETIME DEFAULT CURRENT_TIMESTAMP," +
            "KEY idx_loginlog_user(user_id), KEY idx_loginlog_created(created_at)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS app_user_device(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, device_id VARCHAR(128) NOT NULL, device_model VARCHAR(64)," +
            "os_version VARCHAR(32), app_version VARCHAR(32), last_seen_at DATETIME DEFAULT CURRENT_TIMESTAMP," +
            "created_at DATETIME DEFAULT CURRENT_TIMESTAMP, UNIQUE KEY uk_user_device(user_id, device_id), KEY idx_dev_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",

        "CREATE TABLE IF NOT EXISTS app_user_change_log(" +
            "id BIGINT PRIMARY KEY AUTO_INCREMENT, user_id BIGINT NOT NULL, field VARCHAR(32), old_value VARCHAR(255)," +
            "new_value VARCHAR(255), operator VARCHAR(64), source VARCHAR(32), created_at DATETIME DEFAULT CURRENT_TIMESTAMP," +
            "KEY idx_chg_user(user_id)" +
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    };

    /** 旧库升级补列（幂等，已存在则忽略） */
    private static void heal(Connection c) {
        List<String[]> cols = new ArrayList<>();
        cols.add(new String[]{"users", "nickname", "VARCHAR(64) DEFAULT NULL"});
        cols.add(new String[]{"users", "email", "VARCHAR(128) DEFAULT NULL"});
        cols.add(new String[]{"users", "status", "TINYINT NOT NULL DEFAULT 1"});
        cols.add(new String[]{"users", "created_at", "DATETIME DEFAULT CURRENT_TIMESTAMP"});
        cols.add(new String[]{"users", "last_login_at", "DATETIME DEFAULT NULL"});
        cols.add(new String[]{"users", "last_login_ip", "VARCHAR(64) DEFAULT NULL"});
        cols.add(new String[]{"users", "register_ip", "VARCHAR(64) DEFAULT NULL"});
        cols.add(new String[]{"users", "ban_reason", "VARCHAR(255) DEFAULT NULL"});
        cols.add(new String[]{"users", "ban_until", "DATETIME DEFAULT NULL"});
        cols.add(new String[]{"users", "membership_expire", "DATETIME DEFAULT NULL"});
        cols.add(new String[]{"ai_configs", "api_style", "VARCHAR(32) DEFAULT 'chat_completions'"});
        cols.add(new String[]{"ai_configs", "mode", "VARCHAR(16) DEFAULT 'analysis'"});
        cols.add(new String[]{"ai_configs", "enabled", "TINYINT DEFAULT 0"});
        cols.add(new String[]{"chat_messages", "attachments", "TEXT"});
        cols.add(new String[]{"member_orders", "trade_no", "VARCHAR(64)"});
        cols.add(new String[]{"member_orders", "channel", "VARCHAR(16) DEFAULT 'alipay'"});
        cols.add(new String[]{"member_orders", "paid_at", "DATETIME DEFAULT NULL"});
        for (String[] t : cols) addColumn(c, t[0], t[1], t[2]);
    }

    private static void addColumn(Connection c, String table, String column, String ddl) {
        try {
            if (exists(c, table, column)) return;
            try (Statement s = c.createStatement()) {
                s.executeUpdate("ALTER TABLE " + table + " ADD COLUMN " + column + " " + ddl);
            }
        } catch (Exception ignore) { /* 已存在或表不存在 */ }
    }

    private static boolean exists(Connection c, String table, String column) {
        try (ResultSet r = c.getMetaData().getColumns(c.getCatalog(), null, table, column)) {
            return r.next();
        } catch (Exception e) { return false; }
    }

    /** 种子数据：角色、默认管理员、系统配置、版本号 */
    private static void seed(Connection c) {
        try {
            Object roles = Db.scalar("SELECT COUNT(*) FROM sys_role");
            if (num(roles) == 0) {
                Db.upd("INSERT INTO sys_role(name,code,perms,remark) VALUES(?,?,?,?)", "超级管理员", "superadmin",
                        "[\"users:read\",\"users:ban\",\"users:resetpw\",\"stats:read\",\"admins:manage\",\"roles:manage\",\"logs:read\",\"config:manage\",\"announcements:manage\",\"versions:manage\"]",
                        "拥有全部权限");
                Db.upd("INSERT INTO sys_role(name,code,perms,remark) VALUES(?,?,?,?)", "运营管理员", "operator",
                        "[\"users:read\",\"users:ban\",\"users:resetpw\",\"stats:read\",\"logs:read\",\"config:manage\",\"announcements:manage\",\"versions:manage\"]",
                        "用户与内容运营，不含管理员/角色管理");
                Db.upd("INSERT INTO sys_role(name,code,perms,remark) VALUES(?,?,?,?)", "只读审计", "viewer",
                        "[\"users:read\",\"stats:read\",\"logs:read\"]", "仅查看，不能修改");
            }
            Object admins = Db.scalar("SELECT COUNT(*) FROM sys_admin");
            if (num(admins) == 0) {
                String pw = System.getenv("ADMIN_INIT_PASSWORD");
                if (pw == null || pw.isBlank()) pw = "Admin@2026";
                Db.upd("INSERT INTO sys_admin(username,password_hash,nickname,role_id,status) VALUES(?,?,?,?,1)",
                        "admin", org.mindrot.jbcrypt.BCrypt.hashpw(pw, org.mindrot.jbcrypt.BCrypt.gensalt(10)), "超级管理员", 1);
            }
            String[][] cfg = {
                {"register_enabled", "1", "App 注册开关"},
                {"register_need_email", "0", "注册是否必填邮箱"},
                {"site_name", "Amore", "站点/App 名称"},
                {"announcement", "", "全局公告文本"},
                {"app_version", "3.7", "App 当前版本"},
                {"min_version", "3.0", "App 最低可用版本"},
                {"maintain_mode", "0", "维护模式开关"},
                {"pay_api_url", "", "支付接口地址"},
                {"pay_pid", "", "支付商户号"},
                {"pay_key", "", "支付密钥"},
                {"pay_enabled", "0", "支付开关"}
            };
            for (String[] kv : cfg) {
                Object has = Db.scalar("SELECT k FROM sys_config WHERE k=?", kv[0]);
                if (has == null) Db.upd("INSERT INTO sys_config(k,v,remark) VALUES(?,?,?)", kv[0], kv[1], kv[2]);
            }
            Object ver = Db.scalar("SELECT COUNT(*) FROM app_version");
            if (num(ver) == 0) {
                Db.upd("INSERT INTO app_version(platform,version,build,force_update,download_url,notes,enabled) VALUES('iOS','3.7',28,0,'','Amore 3.7 正式版',1)");
            }
        } catch (Exception e) {
            throw new RuntimeException("种子数据写入失败: " + e.getMessage(), e);
        }
    }

    private static long num(Object o) {
        return o instanceof Number n ? n.longValue() : 0;
    }
}
