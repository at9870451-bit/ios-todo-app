# Amore 后端 API 接口文档

> 版本 v2.0 · Java 21 + Spring Boot 3.3.5 + MyBatis-Plus + MySQL 8 + Redis
> 部署地址示例：`http://154.12.16.204:8080`

---

## 1. 概述

后端同时对外提供三套 RESTful API，共享同一个数据源与统一响应包：

| 前缀 | 使用者 | 认证方式 | 说明 |
| --- | --- | --- | --- |
| `/api/ios/**` | iOS App（Swift/SwiftUI） | `QBSESSID` Cookie + `X-CSRF-TOKEN` 头 | 注册、登录、资料、公告、配置 |
| `/api/admin/**` | App 内管理员页 | 同上（需 `users.role='admin'`） | 统计、用户、订单、系统设置 |
| `/api/console/**` | Web 管理后台（Vue） | `Authorization: Bearer <JWT>` | 用户管理、统计、权限、配置、日志 |

静态面板：`GET /panel`（Vue 构建产物，同端口，无需认证，登录态由前端 JWT 控制）。

---

## 2. 统一响应包

```json
{ "code": 0, "message": "success", "data": { } }
```

- `code = 0` 成功；非 0 表示失败（如 401/403/422/429/500），同时设置对应 HTTP 状态码。
- 时间字段统一 `yyyy-MM-dd HH:mm:ss` 字符串（服务器 UTC 时区）。
- 分页统一：请求 `?page=1&size=20`，响应 `{ "total": N, "page": 1, "size": 20, "items": [] }`。

### 错误码

| code | HTTP | 含义 |
| --- | --- | --- |
| 0 | 200 | 成功 |
| 401 | 401 | 未登录 / 会话过期 / 密码错误 |
| 403 | 403 | 无权限 / 账号被封禁 / 管理员被禁用 |
| 419 | 419 | CSRF 校验失败（仅 iOS 侧写操作） |
| 422 | 422 | 参数校验失败 |
| 429 | 429 | 登录失败次数过多（10 次 / 10 分钟） |
| 500 | 500 | 服务端异常 |

---

## 3. 认证机制

### 3.1 Console JWT（Web 后台）

1. `POST /api/console/auth/login` 校验账号密码（bcrypt）。
2. 签发 HS256 JWT（默认 12 小时），同时把 `jti` 写入 Redis `qb:admintoken:{jti}`。
3. 后续请求带 `Authorization: Bearer <token>`；拦截器校验签名 + Redis 会话是否存在。
4. `POST /api/console/auth/logout` 删除 Redis 会话，token 立即失效。
5. 密钥来源：环境变量 `ADMIN_JWT_SECRET`，未设置则首次启动随机生成并持久化到 `sys_config`。

### 3.2 iOS 会话（Cookie + CSRF）

1. 调用 `GET /api/ios/ping` 获取 `QBSESSID` Cookie（HttpOnly）与 `csrf_token`。
2. 登录 / 注册成功后服务端更新会话并绑定用户 ID。
3. `POST/PUT/DELETE` 请求必须携带 `X-CSRF-TOKEN: <csrf_token>`，否则返回 419。
4. 会话存 Redis（7 天滑动续期），Redis 不可用时自动降级为进程内内存会话。

### 3.3 安全策略

- **封禁拦截**：用户 `status=0` 时，登录返回 `403 ACCOUNT_BANNED`，提示封禁原因。
- **权限码校验**：Console 每个接口映射一个权限码，`superadmin` 角色放行全部；无权限返回 403。
- **登录限流**：同一 IP 连续失败 10 次锁定 10 分钟。
- **操作审计**：所有 Console 写操作（含登录）写入 `sys_operation_log`。
- **防越权**：用户只能访问自身数据；管理员与普通用户分离。

---

## 4. Console 管理后台 API

### 4.1 认证

#### POST /api/console/auth/login
无需认证。body：`{ "username": "admin", "password": "Admin@2026" }`

```bash
curl -X POST http://127.0.0.1:8080/api/console/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"Admin@2026"}'
```

```json
{"code":0,"message":"登录成功","data":{
  "id":1,"username":"admin","nickname":"超级管理员","role_id":1,
  "role_code":"superadmin","role_name":"超级管理员","status":1,
  "perms":["users:read","users:ban","users:resetpw","stats:read","admins:manage","roles:manage","logs:read","config:manage","announcements:manage","versions:manage"],
  "token":"eyJhbGciOiJIUzUxMiJ9...","expires_in":43200
}}
```

#### GET /api/console/auth/me
需 Bearer。返回当前管理员信息（同 `data`，无 token）。

#### POST /api/console/auth/logout
需 Bearer。`data: null`。

#### POST /api/console/auth/password
需 Bearer。body `{ "old_password": "...", "new_password": "至少8位" }`。

### 4.2 用户管理

#### GET /api/console/users — 权限 `users:read`

| 参数 | 说明 |
| --- | --- |
| page / size | 分页，默认 1 / 20 |
| keyword | 用户名/昵称/邮箱/ID 模糊 |
| status | `1` 正常 / `0` 封禁 / 空 全部 |
| level | free / gold / diamond / ultimate |
| date_from / date_to | `yyyy-MM-dd`（按注册时间） |
| order / dir | id / created_at / last_login_at，asc / desc |

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:8080/api/console/users?page=1&size=20&status=1"
```

```json
{"code":0,"message":"success","data":{"total":9,"page":1,"size":20,"items":[
  {"id":1,"username":"demo01","nickname":"demo01","email":"demo01@amore.app",
   "role":"user","level":"free","status":1,"created_at":"2026-10-12 23:50:07",
   "last_login_at":"2026-10-13 23:50:07","last_login_ip":"127.0.0.1",
   "register_ip":"127.0.0.1","live_trading":0,"banned":false}
]}}
```

#### GET /api/console/users/{id} — `users:read`
`data: { user: {...全字段+ban_reason+ban_until}, stats: {sessions,messages,ai_configs,strategies,orders} }`

#### GET /api/console/users/{id}/logins — `users:read`
分页。`items:[{id,ip,ua,device_model,os_version,app_version,success,created_at}]`

#### GET /api/console/users/{id}/devices — `users:read`
`items:[{id,device_id,device_model,os_version,app_version,last_seen_at,created_at}]`

#### GET /api/console/users/{id}/changes — `users:read`
分页。`items:[{id,field,old_value,new_value,operator,source,created_at}]`

#### POST /api/console/users/{id}/ban — `users:ban`
body `{ "reason": "违规", "days": 7 }`（days=0 永久）。

#### POST /api/console/users/{id}/unban — `users:ban`

#### POST /api/console/users/{id}/reset-password — `users:resetpw`
body `{ "new_password": "至少8位" }`。

### 4.3 注册统计

#### GET /api/console/stats/overview — `stats:read`
```json
{"code":0,"data":{"user_total":9,"user_today":1,"user_yesterday":2,"user_week":8,
"user_month":9,"active_today":1,"active_week":9,"active_month":9,
"session_total":1,"message_total":6,"order_total":5,"order_paid":4,"income_total":6755.7}}
```

#### GET /api/console/stats/trend?days=30 — `stats:read`
`data: { days, items:[{date:"2026-10-14", registers:1, actives:1}] }`（按天补零）。

#### GET /api/console/stats/retention?days=7 — `stats:read`
`data: { days, cohorts:[{date, registered, retained:[{day:0,count,rate}]}] }`（rate 为 0~1 小数）。

### 4.4 管理员与角色

| 方法 | 路径 | 权限 | 说明 |
| --- | --- | --- | --- |
| GET | /api/console/admins | admins:manage | 管理员列表 |
| POST | /api/console/admins | admins:manage | body `{username,nickname,password,role_id}` |
| PUT | /api/console/admins/{id} | admins:manage | body `{nickname,role_id,status}` |
| POST | /api/console/admins/{id}/reset-password | admins:manage | body `{new_password}` |
| DELETE | /api/console/admins/{id} | admins:manage | 不能删自己与 id=1 |
| GET | /api/console/roles | roles:manage | 角色列表（含 perms 数组、admin_count） |
| POST | /api/console/roles | roles:manage | body `{name,code,perms:[],remark}` |
| PUT | /api/console/roles/{id} | roles:manage | 同上 |
| DELETE | /api/console/roles/{id} | roles:manage | 有管理员使用时 422 |

权限码全集：`users:read, users:ban, users:resetpw, stats:read, admins:manage, roles:manage, logs:read, config:manage, announcements:manage, versions:manage`。

### 4.5 操作日志

#### GET /api/console/logs — `logs:read`
参数：page / size / keyword / admin_id / date_from / date_to。
`items:[{id,admin_id,admin_name,action,method,path,params,ip,status,created_at}]`

### 4.6 系统配置

| 方法 | 路径 | 权限 | 说明 |
| --- | --- | --- | --- |
| GET | /api/console/config | config:manage | 返回扁平字符串 map |
| PUT | /api/console/config | config:manage | 白名单键，其余忽略 |
| GET/POST/PUT/DELETE | /api/console/announcements[/{id}] | announcements:manage | 公告 CRUD |
| GET/POST/PUT/DELETE | /api/console/versions[/{id}] | versions:manage | 版本 CRUD |

`config` 白名单键：`register_enabled, register_need_email, site_name, announcement, app_version, min_version, maintain_mode, pay_api_url, pay_pid, pay_key, pay_enabled`。

---

## 5. iOS App 接口（/api/ios/**）

| 方法 | 路径 | 认证 | 说明 |
| --- | --- | --- | --- |
| GET | /api/ios/ping | 无 | 下发 `QBSESSID` 与 `csrf_token` |
| POST | /api/ios/register | 无 | 注册（可带 `device`） |
| POST | /api/ios/login | 无 | 登录（可带 `device`） |
| GET | /api/ios/me | 需登录 | 当前用户简要信息 |
| GET | /api/ios/profile | 需登录 | **新增**：完整资料 |
| POST | /api/ios/profile | 需登录 | **新增**：更新昵称/邮箱 |
| GET | /api/ios/announcement | 无 | **新增**：当前生效公告 |
| GET | /api/ios/config | 无 | **新增**：客户端配置下发 |
| POST | /api/ios/logout | 需登录 | 登出 |

#### POST /api/ios/register
```json
{"username":"demo01","password":"Demo@12345","email":"demo01@amore.app",
 "device":{"device_id":"dev-1","device_model":"iPhone15,3","os_version":"iOS 18.1","app_version":"3.7"}}
```
响应（形状与旧版一致）：
```json
{"code":0,"message":"注册成功","data":{"user":{"id":1,"username":"demo01","nickname":"demo01",
"email":"demo01@amore.app","role":"user","membership_level":"free","live_trading_enabled":false},
"csrf_token":"...","badge":{"level":"free","name":"免费版","is_admin":false,"expire_at":null,"days_left":null,"auto_renew":false}}}
```
关闭注册时返回 422 `{"code":"REGISTER_FAILED","message":"注册已关闭，请联系管理员"}`。

#### POST /api/ios/login
body 同上（无 email）。封禁账号返回 403：
```json
{"code":"ACCOUNT_BANNED","message":"账号已被封禁：违规","data":null}
```

#### GET /api/ios/profile
```json
{"code":0,"message":"success","data":{"user":{"id":1,"username":"demo01","nickname":"小A",
"email":"new@test.com","role":"user","membership_level":"free","live_trading_enabled":false,
"created_at":"2026-10-13 23:44:02","last_login_at":"2026-10-13 23:44:02"}}}
```

#### POST /api/ios/profile
body `{ "nickname": "小A", "email": "new@test.com" }`（昵称 ≤20 字符，邮箱需合法）。返回同上 `user`。

#### GET /api/ios/announcement
`data: { id, title, content, type, updated_at }`，无生效公告时为 `null`。

#### GET /api/ios/config
```json
{"code":0,"data":{"register_enabled":"1","register_need_email":"0","maintain_mode":"0",
"site_name":"Amore","announcement":"欢迎使用 Amore","latest_version":"3.7",
"min_version":"3.0","force_update":false,"download_url":""}}
```

---

## 6. App 内管理端接口（/api/admin/**）

沿用 iOS 会话（Cookie + CSRF），仅 `role=admin` 用户可访问（否则 403）。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | /api/admin/stats | 用户/订单/收入统计 |
| GET | /api/admin/users | 用户列表（含 membership_level） |
| GET | /api/admin/orders | 会员订单 |
| GET | /api/admin/plans · POST /plans/save | 套餐 |
| GET | /api/admin/free-ai · POST /free-ai/save | 免费 AI 配置 |
| GET | /api/admin/payment · POST /payment/save | 支付配置 |
| GET | /api/admin/settings · POST /settings/save | 站点设置 |
| POST | /api/admin/user/update | 更新用户（status/level/role/nickname/email） |
| POST | /api/admin/order/mark-paid | 标记订单已支付 |

---

## 7. 数据库表清单（26 张）

**App 业务表（16）**：`users`、`sessions`、`ai_configs`、`ai_signals`、`ai_reviews`、`strategies`、`strategy_runs`、`orders`、`positions`、`trades`、`trading_logs`、`system_logs`、`risk_configs`、`member_orders`、`chat_sessions`、`chat_messages`、`okx_accounts`。

**管理后台表（10）**：`sys_admin`、`sys_role`、`sys_operation_log`、`sys_config`、`app_announcement`、`app_version`、`app_user_login_log`、`app_user_device`、`app_user_change_log`。

完整建表语句见 `db/schema.sql`。
