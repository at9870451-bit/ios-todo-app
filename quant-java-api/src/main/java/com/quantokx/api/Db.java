package com.quantokx.api;
import java.sql.*;
import java.util.*;

public final class Db {
    public static void init() {
        try (Connection c = cn(); Statement s = c.createStatement()) {
            String[] ddl = {
                "CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY AUTOINCREMENT,username TEXT UNIQUE NOT NULL,pass_hash TEXT NOT NULL,role TEXT DEFAULT 'user',level TEXT DEFAULT 'free',live_trading INTEGER DEFAULT 0)",
                "CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY,user_id INTEGER NOT NULL,csrf TEXT NOT NULL)",
                "CREATE TABLE IF NOT EXISTS ai_configs(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL,name TEXT,provider_type TEXT DEFAULT 'openai',api_style TEXT DEFAULT 'chat_completions',api_url TEXT,model TEXT,api_key TEXT,temperature REAL DEFAULT 0.2,max_tokens INTEGER DEFAULT 4000,mode TEXT DEFAULT 'analysis',enabled INTEGER DEFAULT 0,running INTEGER DEFAULT 0,trade_mode TEXT DEFAULT 'demo',leverage INTEGER DEFAULT 5,auto_symbol TEXT,auto_symbols TEXT,auto_interval TEXT DEFAULT '15m',auto_period_seconds INTEGER DEFAULT 300,auto_quantity TEXT DEFAULT '0.001',auto_position_percent REAL DEFAULT 2,capital_usdt REAL DEFAULT 0,min_confidence REAL DEFAULT 0.6,td_mode TEXT DEFAULT 'cross',run_count INTEGER DEFAULT 0,trade_count INTEGER DEFAULT 0,last_run_at TEXT,last_signal TEXT,error_message TEXT,test_status TEXT,test_message TEXT,created_at TEXT DEFAULT (datetime('now','localtime')))",
                "CREATE TABLE IF NOT EXISTS ai_signals(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL,config_id INTEGER,symbol TEXT NOT NULL,market_type TEXT DEFAULT 'swap',signal TEXT NOT NULL,confidence REAL DEFAULT 0,entry REAL,stop_loss REAL,take_profit REAL,reason TEXT,executed INTEGER DEFAULT 0,created_at TEXT DEFAULT (datetime('now','localtime')))",
                "CREATE TABLE IF NOT EXISTS strategies(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL,name TEXT NOT NULL,class_name TEXT NOT NULL,market_type TEXT DEFAULT 'swap',direction_mode TEXT DEFAULT 'long_only',symbol TEXT,symbols TEXT,interval TEXT DEFAULT '15m',mode TEXT DEFAULT 'paper',enabled INTEGER DEFAULT 0,leverage INTEGER DEFAULT 3,position_percent REAL DEFAULT 5,min_confidence REAL DEFAULT 0.6,quantity TEXT DEFAULT '0.001',td_mode TEXT DEFAULT 'cross',parameters TEXT DEFAULT '{}',run_interval INTEGER DEFAULT 60,created_at TEXT DEFAULT (datetime('now','localtime')))",
                "CREATE TABLE IF NOT EXISTS strategy_runs(id INTEGER PRIMARY KEY AUTOINCREMENT,strategy_id INTEGER NOT NULL,status TEXT DEFAULT 'NEVER',last_signal TEXT,last_run_at TEXT,error_message TEXT)",
                "CREATE TABLE IF NOT EXISTS orders(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL,account_id INTEGER,symbol TEXT NOT NULL,market_type TEXT DEFAULT 'swap',mode TEXT DEFAULT 'paper',side TEXT NOT NULL,position_side TEXT,order_type TEXT DEFAULT 'MARKET',price TEXT DEFAULT '0',quantity TEXT DEFAULT '0',executed_quantity TEXT DEFAULT '0',status TEXT DEFAULT 'NEW',source TEXT DEFAULT 'MANUAL',stop_loss TEXT,take_profit TEXT,okx_order_id TEXT,client_order_id TEXT,created_at TEXT DEFAULT (datetime('now','localtime')))",
                "CREATE TABLE IF NOT EXISTS positions(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL,account_id INTEGER,symbol TEXT NOT NULL,market_type TEXT DEFAULT 'swap',position_side TEXT DEFAULT 'BOTH',quantity TEXT DEFAULT '0',entry_price TEXT DEFAULT '0',mark_price TEXT DEFAULT '0',unrealized_pnl TEXT DEFAULT '0',leverage INTEGER DEFAULT 1,status TEXT DEFAULT 'OPEN',created_at TEXT DEFAULT (datetime('now','localtime')))",
                "CREATE TABLE IF NOT EXISTS trades(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL,symbol TEXT NOT NULL,side TEXT NOT NULL,price TEXT DEFAULT '0',quantity TEXT DEFAULT '0',fee TEXT DEFAULT '0',trade_time TEXT,created_at TEXT DEFAULT (datetime('now','localtime')))",
                "CREATE TABLE IF NOT EXISTS trading_logs(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER,symbol TEXT,source TEXT,signal TEXT,price TEXT,result TEXT,pnl TEXT,created_at TEXT DEFAULT (datetime('now','localtime')))",
                "CREATE TABLE IF NOT EXISTS system_logs(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER,level TEXT DEFAULT 'info',channel TEXT DEFAULT 'system',message TEXT,created_at TEXT DEFAULT (datetime('now','localtime')))",
                "CREATE TABLE IF NOT EXISTS risk_configs(user_id INTEGER PRIMARY KEY,single_position_percent REAL DEFAULT 5,max_total_position_percent REAL DEFAULT 20,single_loss_percent REAL DEFAULT 2,daily_loss_percent REAL DEFAULT 5,daily_trade_limit INTEGER DEFAULT 20,consecutive_loss_limit INTEGER DEFAULT 3,max_leverage INTEGER DEFAULT 20,max_positions INTEGER DEFAULT 6,emergency_stop INTEGER DEFAULT 0)",
                "CREATE TABLE IF NOT EXISTS member_orders(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL,trade_no TEXT,level TEXT NOT NULL,months INTEGER DEFAULT 1,amount TEXT DEFAULT '0',status TEXT DEFAULT 'paid',created_at TEXT DEFAULT (datetime('now','localtime')))"
            };
            for (String q : ddl) s.executeUpdate(q);
        } catch (Exception e) { throw new RuntimeException(e); }
    }
    public static Connection cn() { try { return DriverManager.getConnection("jdbc:sqlite:data/qk.db"); } catch (Exception e) { throw new RuntimeException(e); } }
    public static List<Map<String, Object>> rows(String q, Object... a) {
        List<Map<String, Object>> o = new ArrayList<>();
        try (Connection c = cn(); PreparedStatement p = c.prepareStatement(q)) {
            for (int i = 0; i < a.length; i++) p.setObject(i+1, a[i]);
            ResultSet r = p.executeQuery(); var md = r.getMetaData(); int n = md.getColumnCount();
            while (r.next()) { Map<String, Object> m = new LinkedHashMap<>(); for (int i = 1; i <= n; i++) { String col = md.getColumnLabel(i).toLowerCase(); Object v = r.getObject(i); if (v != null) m.put(col, v); } o.add(m); }
        } catch (Exception e) { throw new RuntimeException(e); } return o;
    }
    public static long ins(String q, Object... a) { try (Connection c = cn(); PreparedStatement p = c.prepareStatement(q, Statement.RETURN_GENERATED_KEYS)) { for (int i = 0; i < a.length; i++) p.setObject(i+1, a[i]); p.executeUpdate(); try (ResultSet r = p.getGeneratedKeys()) { if (r.next()) return r.getLong(1); } return 0; } catch (Exception e) { throw new RuntimeException(e); } }
    public static long insert(String q, Object... a) { return ins(q, a); }
  public static int upd(String q, Object... a) { try (Connection c = cn(); PreparedStatement p = c.prepareStatement(q)) { for (int i = 0; i < a.length; i++) p.setObject(i+1, a[i]); return p.executeUpdate(); } catch (Exception e) { throw new RuntimeException(e); } }
    public static Map<String, Object> one(String q, Object... a) { List<Map<String, Object>> r = rows(q, a); return r.isEmpty() ? null : r.get(0); }
    public static Object scalar(String q, Object... a) { return sc(q, a); }
  public static Object sc(String q, Object... a) { List<Map<String, Object>> r = rows(q, a); return r.isEmpty() ? null : r.get(0).values().iterator().next(); }
}
