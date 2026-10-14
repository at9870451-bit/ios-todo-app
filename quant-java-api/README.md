# quant-java-api — Amore iOS App 后端 + Web 管理后台

Java 21 + Spring Boot 3 + MyBatis-Plus + MySQL 8 + Redis 的一体化后端：
既为 Swift/SwiftUI 原生 App 提供 RESTful 接口，又内置一套 Vue 3 + Element Plus 可视化管理后台。

## 功能一览

| 模块 | 说明 |
| --- | --- |
| 用户管理 | 注册数据 / 昵称 / 邮箱 / 注册与登录时间 / 状态，搜索、筛选、分页、封禁、解封、重置密码 |
| 注册统计 | 总用户、今日注册、新增趋势、活跃用户、用户留存（按注册日 cohort） |
| 用户详情 | 资料、登录记录（IP/UA/设备/系统/App 版本）、设备信息、账号变更记录 |
| 后台权限 | 管理员登录（JWT）、角色与权限码、操作日志、管理员账号管理 |
| 系统配置 | App 注册开关、维护模式、版本信息、公告管理、支付/API 配置 |
| 数据安全 | JWT 鉴权、Redis 会话、权限码校验、登录限流、CSRF、操作审计、防越权 |

## 目录结构

```
quant-java-api/
├── pom.xml
├── db/schema.sql                 # MySQL 8 建库脚本（26 张表 + 种子数据）
├── docs/
│   ├── CONTRACT.md               # 前后端接口契约（冻结版）
│   ├── API接口文档.md
│   ├── iOS-API调用示例.md
│   └── 宝塔部署教程.md
└── src/main/java/com/quantokx/api/
    ├── QkApiApplication.java     # 入口 + 双认证拦截器（iOS Cookie/CSRF + Console JWT）
    ├── SchemaBoot.java           # 启动建表 + 补列 + 种子数据（幂等）
    ├── Db.java / Rds.java        # MySQL 访问层 / Redis（可降级内存）
    ├── JwtUtil.java / Sess.java  # JWT 与 iOS 会话（PBKDF2，兼容旧哈希）
    ├── ConsoleCtl.java           # 管理后台 API（/api/console/**）
    ├── IosCtl.java               # iOS App API（/api/ios/**）
    ├── AdminCtl.java             # App 内管理端（/api/admin/**）
    ├── AdminPageCtl.java         # /panel 静态资源（Vue 构建产物）
    ├── MigrateTool.java          # SQLite → MySQL 迁移工具
    └── ...（既有 AI / 策略 / 聊天 / 交易模块）
```

前端源码在同仓库 `../admin-web/`（Vue 3 + TypeScript + Element Plus + ECharts）。

## 快速开始（本地）

```bash
# 1. 建库（或由 SchemaBoot 启动时自动建表）
mysql -uroot -p < db/schema.sql

# 2. 构建前端（产物输出到 src/main/resources/static/panel）
cd ../admin-web && npm install && npm run build && cd ../quant-java-api

# 3. 编译运行
export DB_URL='jdbc:mysql://127.0.0.1:3306/quantokx?useUnicode=true&characterEncoding=UTF-8&serverTimezone=UTC&useSSL=false&allowPublicKeyRetrieval=true'
export DB_USER=quantokx DB_PASSWORD=你的密码 REDIS_HOST=127.0.0.1 ADMIN_JWT_SECRET=$(openssl rand -hex 32)
mvn spring-boot:run
```

访问管理后台：<http://localhost:8080/panel>（默认 `admin / Admin@2026`，首次登录后请修改）。

## 环境变量

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `DB_URL` | MySQL JDBC URL | `jdbc:mysql://127.0.0.1:3306/quantokx?...` |
| `DB_USER` / `DB_PASSWORD` | 数据库账号 | `quantokx` / 空 |
| `REDIS_HOST` / `REDIS_PORT` / `REDIS_PASSWORD` | Redis | `127.0.0.1` / `6379` / 空 |
| `ADMIN_JWT_SECRET` | 后台 JWT 密钥（≥16 位） | 首次启动自动生成并写入 `sys_config` |
| `ADMIN_INIT_PASSWORD` | 首次初始化管理员密码 | `Admin@2026` |

## 三套 API

- `/api/ios/**` — iOS App 使用，`QBSESSID` Cookie + `X-CSRF-TOKEN` 头。
- `/api/admin/**` — App 内管理员页，同 Cookie 会话，仅 `role=admin` 可访问。
- `/api/console/**` — Web 管理后台，`Authorization: Bearer <JWT>`。

统一响应包：`{"code":0,"message":"success","data":...}`。

## 从旧 SQLite 版本升级

```bash
systemctl stop quantokx-java
cp /opt/quantokx-java/data/qk.db /opt/quantokx-java/data/qk.db.bak
java -jar /opt/quantokx-java/app.jar --migrate --sqlite=/opt/quantokx-java/data/qk.db
systemctl start quantokx-java
```

迁移保留原主键与 `$qk$...` 密码哈希，老用户可直接登录。详见 `docs/宝塔部署教程.md`。

## 部署

服务器（Ubuntu 24.04 + 宝塔）部署、systemd 配置、ufw、备份与排错见 `docs/宝塔部署教程.md`。
