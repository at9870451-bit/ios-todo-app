-- Doll Studio 3D — MySQL 建表（utf8mb4，InnoDB）
-- 部署：mysql -u root -p < schema.sql

-- 用户（游客不出库；注册用户走账号登录）
CREATE TABLE IF NOT EXISTS users (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  username      VARCHAR(64)  NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,          -- password_hash()/password_verify()
  apple_sub     VARCHAR(128) NULL,              -- Sign in with Apple subject
  nickname      VARCHAR(64)  NOT NULL DEFAULT '',
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_users_apple (apple_sub)
) ENGINE=InnoDB;

-- 玩偶模型（USDZ 可空：空 = 客户端程序化模型）
CREATE TABLE IF NOT EXISTS dolls (
  id            VARCHAR(64) PRIMARY KEY,        -- doll_female_default
  name          VARCHAR(64)  NOT NULL,
  gender        ENUM('male','female','neutral') NOT NULL DEFAULT 'female',
  skin          CHAR(7)      NOT NULL DEFAULT '#F3C6A5',
  height_scale  DECIMAL(4,2) NOT NULL DEFAULT 1.00,
  usdz_url      VARCHAR(512) NULL,
  sort          INT NOT NULL DEFAULT 0,
  enabled       TINYINT(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB;

-- 服装分类
CREATE TABLE IF NOT EXISTS categories (
  `key`   VARCHAR(32) PRIMARY KEY,              -- top/bottom/scarf/hat/shoes/hair/accessory/other
  title   VARCHAR(32) NOT NULL,
  sort    INT NOT NULL DEFAULT 0,
  enabled TINYINT(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB;

-- 服装
CREATE TABLE IF NOT EXISTS clothes (
  id              VARCHAR(64) PRIMARY KEY,      -- top_tee_white
  name            VARCHAR(64) NOT NULL,
  category        VARCHAR(32) NOT NULL,
  kind            VARCHAR(32) NOT NULL,         -- 程序化 kind（tee/hoodie/cap/...）或 usdz
  color           CHAR(7)     NOT NULL DEFAULT '#888888',
  price           DECIMAL(8,2) NOT NULL DEFAULT 0,   -- 0=免费
  thumb_url       VARCHAR(512) NULL,
  model_url       VARCHAR(512) NULL,            -- kind=usdz 时必填
  exclusive_group VARCHAR(32) NULL,             -- 互斥组（hat）
  sort            INT NOT NULL DEFAULT 0,
  enabled         TINYINT(1) NOT NULL DEFAULT 1,
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_clothes_cat (category, enabled, sort),
  CONSTRAINT fk_clothes_cat FOREIGN KEY (category) REFERENCES categories(`key`)
) ENGINE=InnoDB;

-- 用户穿搭作品
CREATE TABLE IF NOT EXISTS outfits (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id     BIGINT UNSIGNED NOT NULL,
  name        VARCHAR(64) NOT NULL DEFAULT '我的穿搭',
  doll_id     VARCHAR(64) NOT NULL,
  gender      ENUM('male','female','neutral') NOT NULL,
  skin        CHAR(7) NOT NULL,
  slots       JSON NOT NULL,                  -- {"top":{"cloth_id":"...","color":"#..."}, ...}
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_outfits_user (user_id, created_at),
  CONSTRAINT fk_outfits_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB;

-- 用户收藏 / 已解锁（付费服装订单的本地镜像由客户端；服务端权威）
CREATE TABLE IF NOT EXISTS user_closet (
  user_id    BIGINT UNSIGNED NOT NULL,
  cloth_id   VARCHAR(64) NOT NULL,
  kind       ENUM('favorite','owned') NOT NULL DEFAULT 'favorite',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, cloth_id, kind),
  CONSTRAINT fk_closet_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_closet_cloth FOREIGN KEY (cloth_id) REFERENCES clothes(id)
) ENGINE=InnoDB;

-- AI 配置（API Key 只存服务端，绝不下发）
CREATE TABLE IF NOT EXISTS ai_config (
  id            INT PRIMARY KEY DEFAULT 1,
  api_base      VARCHAR(255) NOT NULL DEFAULT 'https://api.openai.com/v1',
  api_key       VARCHAR(255) NOT NULL DEFAULT '',
  model         VARCHAR(64)  NOT NULL DEFAULT 'gpt-4o-mini',
  timeout_sec   INT NOT NULL DEFAULT 20,
  max_retries   INT NOT NULL DEFAULT 2,
  daily_limit   INT NOT NULL DEFAULT 1000,    -- 全站每日调用上限
  enabled       TINYINT(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB;

-- AI 调用日志
CREATE TABLE IF NOT EXISTS ai_logs (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id     BIGINT UNSIGNED NULL,
  endpoint    VARCHAR(64) NOT NULL DEFAULT 'outfit',
  prompt      TEXT,
  model       VARCHAR(64),
  status      ENUM('ok','error') NOT NULL,
  latency_ms  INT NOT NULL DEFAULT 0,
  error_msg   VARCHAR(512) NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_ai_logs_time (created_at)
) ENGINE=InnoDB;

-- 系统设置（背景音乐默认音量等，客户端 GET /api/config）
CREATE TABLE IF NOT EXISTS settings (
  k VARCHAR(64) PRIMARY KEY,
  v VARCHAR(512) NOT NULL
) ENGINE=InnoDB;

-- 管理员
CREATE TABLE IF NOT EXISTS admins (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  username      VARCHAR(64) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role          ENUM('admin','operator') NOT NULL DEFAULT 'admin',
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 管理操作日志
CREATE TABLE IF NOT EXISTS admin_logs (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  admin_id   BIGINT UNSIGNED NOT NULL,
  action     VARCHAR(128) NOT NULL,
  detail     VARCHAR(1024) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_admin_logs_time (created_at)
) ENGINE=InnoDB;

-- ============ 种子数据 ============

INSERT IGNORE INTO categories (`key`, title, sort) VALUES
('top','上衣',1),('bottom','下装',2),('scarf','围巾',3),('hat','帽子',4),
('shoes','鞋子',5),('hair','发型',6),('accessory','配饰',7),('other','其他',8);

INSERT IGNORE INTO dolls (id, name, gender, skin, height_scale) VALUES
('doll_female_default','小雅','female','#F3C6A5',1.00),
('doll_male_default','小辰','male','#E8B48C',1.06),
('doll_neutral_default','小七','neutral','#F0C0A8',0.98);

INSERT IGNORE INTO clothes (id, name, category, kind, color, price, exclusive_group, sort) VALUES
('top_tee_white','白色 T 恤','top','tee','#F5F5F7',0,NULL,1),
('top_tee_black','黑色 T 恤','top','tee','#2B2B2E',0,NULL,2),
('top_shirt_blue','蓝色衬衫','top','shirt','#5B8DEF',0,NULL,3),
('top_hoodie_gray','灰色卫衣','top','hoodie','#8E8E93',0,NULL,4),
('top_hoodie_pink','粉色卫衣','top','hoodie','#F4A6C0',6,NULL,5),
('top_sweater_red','红色毛衣','top','sweater','#C4453C',0,NULL,6),
('top_jacket_denim','牛仔夹克','top','jacket','#4A6B8A',8,NULL,7),
('top_coat_beige','驼色大衣','top','coat','#C8A882',12,NULL,8),
('bot_jeans_blue','牛仔裤','bottom','pants','#4A6B9A',0,NULL,1),
('bot_cargo_gray','工装裤','bottom','pants','#7A7A6E',0,NULL,2),
('bot_shorts_beige','休闲短裤','bottom','shorts','#D8C8A8',0,NULL,3),
('bot_skirt_plaid','百褶裙','bottom','skirt','#9A4A5A',6,NULL,4),
('bot_longskirt_black','黑色长裙','bottom','longskirt','#2B2B2E',0,NULL,5),
('scarf_knit_gray','深灰针织围巾','scarf','scarf','#5A5A5E',0,NULL,1),
('scarf_long_red','红色长围巾','scarf','scarflong','#B4443C',4,NULL,2),
('scarf_neck_orange','活力橙围脖','scarf','scarfneck','#FF9500',0,NULL,3),
('hat_cap_black','黑色棒球帽','hat','cap','#2B2B2E',0,'hat',1),
('hat_beanie_knit','针织帽','hat','beanie','#7A5A8A',0,'hat',2),
('hat_beret_red','红色贝雷帽','hat','beret','#B4443C',5,'hat',3),
('hat_bucket_cream','渔夫帽','hat','bucket','#E8DCC8',0,'hat',4),
('shoe_sneakers_white','白色运动鞋','shoes','sneakers','#F0F0F2',0,NULL,1),
('shoe_leather_black','黑色皮鞋','shoes','leather','#2B2B2E',0,NULL,2),
('shoe_boots_brown','棕色短靴','shoes','boots','#6B4A32',7,NULL,3),
('hair_short_black','黑色短发','hair','hairShort','#2B2B2E',0,NULL,1),
('hair_long_brown','棕色长发','hair','hairLong','#5A3A28',0,NULL,2),
('hair_curly_gold','金色卷发','hair','hairCurly','#C8A050',5,NULL,3),
('hair_pony_pink','粉色马尾','hair','hairPony','#E88AA8',5,NULL,4),
('acc_glasses_black','黑框眼镜','accessory','glasses','#2B2B2E',0,NULL,1),
('acc_necklace_gold','金色项链','accessory','necklace','#D8B84A',4,NULL,2),
('acc_bag_brown','棕色挎包','accessory','bag','#6B4A32',5,NULL,3),
('acc_earring_pearl','珍珠耳饰','accessory','earring','#F0EAE0',3,NULL,4);

INSERT IGNORE INTO ai_config (id) VALUES (1);

INSERT IGNORE INTO settings (k, v) VALUES
('bgm_default_volume','0.4'),
('sfx_default_volume','0.8'),
('announcement','欢迎使用 Doll Studio 3D');

