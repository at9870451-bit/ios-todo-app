-- ============================================================================
-- Amore iOS App 后端 + 管理后台  MySQL 8.0 数据库脚本
-- 项目：quant-java-api (Spring Boot 3 + MyBatis-Plus + Redis)
-- 字符集：utf8mb4 / utf8mb4_general_ci
-- 说明：
--   1. 本脚本由线上库结构导出，可重复执行（先 DROP 再 CREATE）。
--   2. 应用启动时 SchemaBoot 也会自动建表与补列（幂等），本脚本用于手工建库/审计/离线部署。
--   3. 共 26 张表：16 张 App 业务表 + 10 张管理后台表。
-- 执行：mysql -uroot -p < schema.sql
-- ============================================================================

CREATE DATABASE IF NOT EXISTS `quantokx` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE `quantokx`;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `ai_configs`;
DROP TABLE IF EXISTS `ai_reviews`;
DROP TABLE IF EXISTS `ai_signals`;
DROP TABLE IF EXISTS `app_announcement`;
DROP TABLE IF EXISTS `app_user_change_log`;
DROP TABLE IF EXISTS `app_user_device`;
DROP TABLE IF EXISTS `app_user_login_log`;
DROP TABLE IF EXISTS `app_version`;
DROP TABLE IF EXISTS `chat_messages`;
DROP TABLE IF EXISTS `chat_sessions`;
DROP TABLE IF EXISTS `member_orders`;
DROP TABLE IF EXISTS `okx_accounts`;
DROP TABLE IF EXISTS `orders`;
DROP TABLE IF EXISTS `positions`;
DROP TABLE IF EXISTS `risk_configs`;
DROP TABLE IF EXISTS `sessions`;
DROP TABLE IF EXISTS `strategies`;
DROP TABLE IF EXISTS `strategy_runs`;
DROP TABLE IF EXISTS `sys_admin`;
DROP TABLE IF EXISTS `sys_config`;
DROP TABLE IF EXISTS `sys_operation_log`;
DROP TABLE IF EXISTS `sys_role`;
DROP TABLE IF EXISTS `system_logs`;
DROP TABLE IF EXISTS `trades`;
DROP TABLE IF EXISTS `trading_logs`;
DROP TABLE IF EXISTS `users`;

CREATE TABLE `ai_configs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `name` varchar(128) DEFAULT NULL,
  `provider_type` varchar(32) DEFAULT 'openai',
  `api_style` varchar(32) DEFAULT 'chat_completions',
  `api_url` varchar(255) DEFAULT NULL,
  `model` varchar(128) DEFAULT NULL,
  `api_key` varchar(512) DEFAULT NULL,
  `temperature` double DEFAULT '0.2',
  `max_tokens` int DEFAULT '4000',
  `mode` varchar(16) DEFAULT 'analysis',
  `enabled` tinyint DEFAULT '0',
  `running` tinyint DEFAULT '0',
  `trade_mode` varchar(16) DEFAULT 'demo',
  `leverage` int DEFAULT '5',
  `auto_symbol` varchar(64) DEFAULT NULL,
  `auto_symbols` varchar(512) DEFAULT NULL,
  `auto_interval` varchar(16) DEFAULT '15m',
  `auto_period_seconds` int DEFAULT '300',
  `auto_quantity` varchar(32) DEFAULT '0.001',
  `auto_position_percent` double DEFAULT '2',
  `capital_usdt` double DEFAULT '0',
  `min_confidence` double DEFAULT '0.6',
  `td_mode` varchar(16) DEFAULT 'cross',
  `run_count` int DEFAULT '0',
  `trade_count` int DEFAULT '0',
  `last_run_at` datetime DEFAULT NULL,
  `last_signal` text,
  `error_message` text,
  `test_status` varchar(16) DEFAULT NULL,
  `test_message` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_ai_cfg_user` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `ai_reviews` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `config_id` bigint DEFAULT NULL,
  `order_id` bigint DEFAULT NULL,
  `symbol` varchar(64) DEFAULT NULL,
  `side` varchar(16) DEFAULT NULL,
  `entry_price` double DEFAULT NULL,
  `exit_price` double DEFAULT NULL,
  `pnl` double DEFAULT '0',
  `leverage` int DEFAULT '1',
  `result` varchar(16) DEFAULT NULL,
  `score` int DEFAULT '0',
  `review` text,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_rev_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `ai_signals` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `config_id` bigint DEFAULT NULL,
  `symbol` varchar(64) NOT NULL,
  `market_type` varchar(16) DEFAULT 'swap',
  `signal` varchar(32) NOT NULL,
  `confidence` double DEFAULT '0',
  `entry` double DEFAULT NULL,
  `stop_loss` double DEFAULT NULL,
  `take_profit` double DEFAULT NULL,
  `reason` text,
  `executed` tinyint DEFAULT '0',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_sig_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `app_announcement` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `title` varchar(128) NOT NULL,
  `content` text,
  `type` varchar(16) DEFAULT 'notice',
  `enabled` tinyint DEFAULT '1',
  `start_at` datetime DEFAULT NULL,
  `end_at` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `app_user_change_log` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `field` varchar(32) DEFAULT NULL,
  `old_value` varchar(255) DEFAULT NULL,
  `new_value` varchar(255) DEFAULT NULL,
  `operator` varchar(64) DEFAULT NULL,
  `source` varchar(32) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_chg_user` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `app_user_device` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `device_id` varchar(128) NOT NULL,
  `device_model` varchar(64) DEFAULT NULL,
  `os_version` varchar(32) DEFAULT NULL,
  `app_version` varchar(32) DEFAULT NULL,
  `last_seen_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_device` (`user_id`,`device_id`),
  KEY `idx_dev_user` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `app_user_login_log` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `ip` varchar(64) DEFAULT NULL,
  `ua` varchar(512) DEFAULT NULL,
  `device_model` varchar(64) DEFAULT NULL,
  `os_version` varchar(32) DEFAULT NULL,
  `app_version` varchar(32) DEFAULT NULL,
  `success` tinyint DEFAULT '1',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_loginlog_user` (`user_id`),
  KEY `idx_loginlog_created` (`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `app_version` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `platform` varchar(16) DEFAULT 'iOS',
  `version` varchar(32) NOT NULL,
  `build` int DEFAULT '1',
  `force_update` tinyint DEFAULT '0',
  `download_url` varchar(255) DEFAULT NULL,
  `notes` text,
  `enabled` tinyint DEFAULT '1',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_messages` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `session_id` bigint NOT NULL,
  `role` varchar(16) NOT NULL,
  `content` mediumtext NOT NULL,
  `attachments` text,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_cm_sess` (`session_id`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `chat_sessions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `title` varchar(255) DEFAULT '新对话',
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_cs_user` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `member_orders` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `trade_no` varchar(64) DEFAULT NULL,
  `level` varchar(16) NOT NULL,
  `months` int DEFAULT '1',
  `amount` varchar(32) DEFAULT '0',
  `status` varchar(16) DEFAULT 'paid',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_mo_user` (`user_id`),
  KEY `idx_mo_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `okx_accounts` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `name` varchar(64) DEFAULT NULL,
  `api_key` varchar(255) DEFAULT NULL,
  `secret_key` varchar(255) DEFAULT NULL,
  `passphrase` varchar(255) DEFAULT NULL,
  `is_demo` tinyint DEFAULT '1',
  `enabled` tinyint DEFAULT '1',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_okxacc_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `orders` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `account_id` bigint DEFAULT NULL,
  `symbol` varchar(64) NOT NULL,
  `market_type` varchar(16) DEFAULT 'swap',
  `mode` varchar(16) DEFAULT 'paper',
  `side` varchar(16) NOT NULL,
  `position_side` varchar(16) DEFAULT NULL,
  `order_type` varchar(16) DEFAULT 'MARKET',
  `price` varchar(32) DEFAULT '0',
  `quantity` varchar(32) DEFAULT '0',
  `executed_quantity` varchar(32) DEFAULT '0',
  `status` varchar(24) DEFAULT 'NEW',
  `source` varchar(24) DEFAULT 'MANUAL',
  `stop_loss` varchar(32) DEFAULT NULL,
  `take_profit` varchar(32) DEFAULT NULL,
  `okx_order_id` varchar(64) DEFAULT NULL,
  `client_order_id` varchar(64) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_ord_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `positions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `account_id` bigint DEFAULT NULL,
  `symbol` varchar(64) NOT NULL,
  `market_type` varchar(16) DEFAULT 'swap',
  `position_side` varchar(16) DEFAULT 'BOTH',
  `quantity` varchar(32) DEFAULT '0',
  `entry_price` varchar(32) DEFAULT '0',
  `mark_price` varchar(32) DEFAULT '0',
  `unrealized_pnl` varchar(32) DEFAULT '0',
  `leverage` int DEFAULT '1',
  `status` varchar(16) DEFAULT 'OPEN',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_pos_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `risk_configs` (
  `user_id` bigint NOT NULL,
  `single_position_percent` double DEFAULT '5',
  `max_total_position_percent` double DEFAULT '20',
  `single_loss_percent` double DEFAULT '2',
  `daily_loss_percent` double DEFAULT '5',
  `daily_trade_limit` int DEFAULT '20',
  `consecutive_loss_limit` int DEFAULT '3',
  `max_leverage` int DEFAULT '20',
  `max_positions` int DEFAULT '6',
  `emergency_stop` tinyint DEFAULT '0',
  PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `sessions` (
  `token` varchar(64) NOT NULL,
  `user_id` bigint NOT NULL,
  `csrf` varchar(64) NOT NULL,
  PRIMARY KEY (`token`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `strategies` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `name` varchar(128) NOT NULL,
  `class_name` varchar(64) NOT NULL,
  `market_type` varchar(16) DEFAULT 'swap',
  `direction_mode` varchar(16) DEFAULT 'long_only',
  `symbol` varchar(64) DEFAULT NULL,
  `symbols` varchar(512) DEFAULT NULL,
  `interval` varchar(16) DEFAULT '15m',
  `mode` varchar(16) DEFAULT 'paper',
  `enabled` tinyint DEFAULT '0',
  `leverage` int DEFAULT '3',
  `position_percent` double DEFAULT '5',
  `min_confidence` double DEFAULT '0.6',
  `quantity` varchar(32) DEFAULT '0.001',
  `td_mode` varchar(16) DEFAULT 'cross',
  `parameters` text,
  `run_interval` int DEFAULT '60',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_stg_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `strategy_runs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `strategy_id` bigint NOT NULL,
  `status` varchar(16) DEFAULT 'NEVER',
  `last_signal` varchar(64) DEFAULT NULL,
  `last_run_at` datetime DEFAULT NULL,
  `error_message` text,
  PRIMARY KEY (`id`),
  KEY `idx_run_stg` (`strategy_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `sys_admin` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL,
  `password_hash` varchar(128) NOT NULL,
  `nickname` varchar(64) DEFAULT NULL,
  `role_id` bigint NOT NULL DEFAULT '2',
  `status` tinyint NOT NULL DEFAULT '1',
  `last_login_at` datetime DEFAULT NULL,
  `last_login_ip` varchar(64) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `sys_config` (
  `k` varchar(64) NOT NULL,
  `v` text,
  `remark` varchar(255) DEFAULT NULL,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`k`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `sys_operation_log` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `admin_id` bigint DEFAULT NULL,
  `admin_name` varchar(64) DEFAULT NULL,
  `action` varchar(64) DEFAULT NULL,
  `method` varchar(8) DEFAULT NULL,
  `path` varchar(255) DEFAULT NULL,
  `params` text,
  `ip` varchar(64) DEFAULT NULL,
  `status` int DEFAULT '200',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_oplog_created` (`created_at`),
  KEY `idx_oplog_admin` (`admin_id`)
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `sys_role` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `code` varchar(64) NOT NULL,
  `perms` text,
  `remark` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `system_logs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint DEFAULT NULL,
  `level` varchar(16) DEFAULT 'info',
  `channel` varchar(32) DEFAULT 'system',
  `message` text,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_slog_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `trades` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `symbol` varchar(64) NOT NULL,
  `side` varchar(16) NOT NULL,
  `price` varchar(32) DEFAULT '0',
  `quantity` varchar(32) DEFAULT '0',
  `fee` varchar(32) DEFAULT '0',
  `trade_time` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_trd_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `trading_logs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint DEFAULT NULL,
  `symbol` varchar(64) DEFAULT NULL,
  `source` varchar(32) DEFAULT NULL,
  `signal` varchar(32) DEFAULT NULL,
  `price` varchar(32) DEFAULT NULL,
  `result` varchar(32) DEFAULT NULL,
  `pnl` varchar(32) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_tlog_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `users` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `username` varchar(64) COLLATE utf8mb4_general_ci NOT NULL,
  `pass_hash` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `nickname` varchar(64) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `email` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `role` varchar(16) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'user',
  `level` varchar(16) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'free',
  `live_trading` tinyint NOT NULL DEFAULT '0',
  `status` tinyint NOT NULL DEFAULT '1',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `last_login_at` datetime DEFAULT NULL,
  `last_login_ip` varchar(64) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `register_ip` varchar(64) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `ban_reason` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `ban_until` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  KEY `idx_users_created` (`created_at`),
  KEY `idx_users_status` (`status`),
  KEY `idx_users_email` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ============================================================================
-- 初始化数据（种子）
-- 默认管理员 admin / Admin@2026（bcrypt 哈希；首次登录后请立即修改密码）
-- 也可用环境变量 ADMIN_INIT_PASSWORD 覆盖初始密码（应用首次启动时读取）
-- ============================================================================

INSERT INTO `sys_role` (`id`,`name`,`code`,`perms`,`remark`) VALUES
 (1,'超级管理员','superadmin','["users:read","users:ban","users:resetpw","stats:read","admins:manage","roles:manage","logs:read","config:manage","announcements:manage","versions:manage"]','拥有全部权限'),
 (2,'运营管理员','operator','["users:read","users:ban","users:resetpw","stats:read","logs:read","config:manage","announcements:manage","versions:manage"]','用户与内容运营，不含管理员/角色管理'),
 (3,'只读审计','viewer','["users:read","stats:read","logs:read"]','仅查看，不能修改');

-- 默认管理员密码：Admin@2026
INSERT INTO `sys_admin` (`id`,`username`,`password_hash`,`nickname`,`role_id`,`status`) VALUES
 (1,'admin','$2a$10$IPTl8AhOY8srLZNHfArE9.w3vDXQp0tGpfEymt8bzFDZVM0bxjxpy','超级管理员',1,1);

INSERT INTO `sys_config` (`k`,`v`,`remark`) VALUES
 ('register_enabled','1','App 注册开关'),
 ('register_need_email','0','注册是否必填邮箱'),
 ('site_name','Amore','站点/App 名称'),
 ('announcement','','全局公告文本'),
 ('app_version','3.7','App 当前版本'),
 ('min_version','3.0','App 最低可用版本'),
 ('maintain_mode','0','维护模式开关'),
 ('pay_api_url','','支付接口地址'),
 ('pay_pid','','支付商户号'),
 ('pay_key','','支付密钥'),
 ('pay_enabled','0','支付开关');

INSERT INTO `app_version` (`platform`,`version`,`build`,`force_update`,`download_url`,`notes`,`enabled`) VALUES
 ('iOS','3.7',28,0,'','Amore 3.7 正式版',1);

SET FOREIGN_KEY_CHECKS = 1;

-- 完成
