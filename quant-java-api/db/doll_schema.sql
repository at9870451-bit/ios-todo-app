-- ============================================================
-- Doll Studio 3D 独立建表 SQL（MySQL 8）
-- 说明：quant-java-api 的 SchemaBoot 启动时会自动执行相同 DDL + 种子，
--       本文件用于手动初始化 / 文档参考 / 独立环境部署。
-- ============================================================

CREATE TABLE IF NOT EXISTS doll_categories(
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  code VARCHAR(32) NOT NULL UNIQUE,
  name VARCHAR(64) NOT NULL,
  sort INT DEFAULT 0,
  enabled TINYINT DEFAULT 1,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS doll_items(
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  category VARCHAR(32) NOT NULL,
  name VARCHAR(64) NOT NULL,
  style VARCHAR(64) NOT NULL,
  color VARCHAR(16) DEFAULT '#FFFFFF',
  premium TINYINT DEFAULT 0,
  sort INT DEFAULT 0,
  enabled TINYINT DEFAULT 1,
  model_url VARCHAR(255) DEFAULT NULL,
  model_scale DOUBLE DEFAULT 1,
  model_offset_y DOUBLE DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  KEY idx_dollitem_cat(category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS doll_outfits(
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  name VARCHAR(64) DEFAULT '未命名搭配',
  gender VARCHAR(16) DEFAULT 'neutral',
  skin VARCHAR(16) DEFAULT '#F6D7BE',
  state MEDIUMTEXT,
  favorite TINYINT DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_dollout_user(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS doll_ai_logs(
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT,
  prompt VARCHAR(500),
  result MEDIUMTEXT,
  status VARCHAR(16) DEFAULT 'ok',
  message VARCHAR(500),
  duration_ms INT DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  KEY idx_dollai_user(user_id),
  KEY idx_dollai_created(created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- 种子：分类 ----------
INSERT INTO doll_categories(code,name,sort,enabled) VALUES
  ('hair','发型',1,1),('top','上衣',2,1),('bottom','下装',3,1),
  ('scarf','围巾',4,1),('hat','帽子',5,1),('shoes','鞋子',6,1),('accessory','配饰',7,1);

-- ---------- 种子：款式（style 与 iOS 3D 构建器一一对应） ----------
INSERT INTO doll_items(category,style,name,color,premium,sort,enabled) VALUES
  ('hair','short','清爽短发','#3B2B20',0,1,1),
  ('hair','bob','波波头','#4A3226',0,2,1),
  ('hair','long','柔顺长发','#5A3A22',0,3,1),
  ('hair','twintails','双马尾','#6B4423',0,4,1),
  ('hair','bun','丸子头','#2C2C2E',0,5,1),
  ('hair','spiky','刺猬头','#1F1F22',0,6,1),
  ('top','tee','经典T恤','#FFFFFF',0,1,1),
  ('top','hoodie','连帽卫衣','#5B7FD4',0,2,1),
  ('top','shirt','衬衫','#DDE5F0',0,3,1),
  ('top','vest','针织背心','#E8C468',0,4,1),
  ('top','sweater','高领毛衣','#C96F5E',0,5,1),
  ('top','jacket','牛仔夹克','#3E5C8A',0,6,1),
  ('bottom','shorts','休闲短裤','#3E5C8A',0,1,1),
  ('bottom','pants','直筒长裤','#2C2C2E',0,2,1),
  ('bottom','skirt','百褶短裙','#D96A7B',0,3,1),
  ('bottom','wide_leg','阔腿裤','#8A7F6A',0,4,1),
  ('scarf','scarf','经典围巾','#D9433B',0,1,1),
  ('scarf','bandana','三角巾','#E8C468',0,2,1),
  ('hat','beanie','毛线帽','#D9433B',0,1,1),
  ('hat','cap','棒球帽','#2C2C2E',0,2,1),
  ('hat','bucket','渔夫帽','#E8E2D4',0,3,1),
  ('hat','beret','贝雷帽','#B0565B',0,4,1),
  ('shoes','sneakers','小白鞋','#FFFFFF',0,1,1),
  ('shoes','boots','马丁靴','#3A2A20',0,2,1),
  ('shoes','loafers','乐福鞋','#5A3A22',0,3,1),
  ('shoes','sandals','凉鞋','#C9A06B',0,4,1),
  ('accessory','glasses','圆框眼镜','#2C2C2E',0,1,1),
  ('accessory','necklace','小金链','#E8C468',0,2,1),
  ('accessory','backpack','双肩包','#D96A7B',0,3,1),
  ('accessory','earrings','星星耳钉','#E8C468',0,4,1),
  ('accessory','flower','头花','#FF8FA3',0,5,1),
  ('accessory','watch','运动手表','#2C2C2E',0,6,1);

-- ---------- 角色权限补充（幂等） ----------
UPDATE sys_role SET perms = CONCAT(SUBSTRING(perms,1,LENGTH(perms)-1), ',"doll:manage"]')
WHERE perms LIKE '[%]' AND perms NOT LIKE '%doll:manage%' AND perms <> '[]';
