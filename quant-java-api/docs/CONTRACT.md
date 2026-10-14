# Amore 管理后台 v2.0 — API 契约（冻结版）

后端：Java 21 + Spring Boot 3.3.5 + MyBatis-Plus + MySQL 8 + Redis，单 jar（8080 端口）。
三套 API 共存：`/api/ios/*`（iOS App，QBSESSID Cookie+CSRF，保持 v3.7 兼容）、`/api/admin/*`（iOS App 内管理员页，同上认证）、`/api/console/*`（本 Web 管理后台，JWT）。

## 统一响应包
```json
{"code": 0, "message": "success", "data": ...}
```
- `code=0` 成功；非 0 失败（如 401 未登录、403 无权限、422 参数错误、500 服务错误）。
- HTTP 状态码：业务成功 200；认证失败 401；权限不足 403；参数错误 422；封禁账号 403。
- 时间字符串格式统一 `yyyy-MM-dd HH:mm:ss`（服务端时区）。
- 分页统一：请求 `?page=1&size=20`（page 从 1 开始），响应 `{"total":123,"page":1,"size":20,"items":[...]}`。

## 一、Console 管理后台 API（JWT，前缀 /api/console）
认证方式：`Authorization: Bearer <token>`。除 `/auth/login` 外全部需要。
角色权限码（数组存储，superadmin 角色放行一切）：
`users:read, users:ban, users:resetpw, stats:read, admins:manage, roles:manage, logs:read, config:manage, announcements:manage, versions:manage`

### 1. 认证
- `POST /api/console/auth/login` body `{username, password}` → `data:{token, expires_in:43200, admin:{id, username, nickname, role_id, role_code, role_name, perms:["users:read",...]}}`
  失败 401 `{code:401, message:"用户名或密码错误", data:null}`；连续错 10 次锁定该 IP 10 分钟（429）。
- `GET  /api/console/auth/me` → `data:{admin:{...同上}}`
- `POST /api/console/auth/logout` → `data:null`（服务端删除 token 会话）
- `POST /api/console/auth/password` body `{old_password, new_password}`（新密码 ≥8 位）→ `data:null`

### 2. 用户管理
- `GET /api/console/users?page&size&keyword&status&level&date_from&date_to&order&dir`
  keyword 匹配 username/email/nickname/id；status：空=全部 / `1`=正常 / `0`=封禁；level：free/gold/diamond/ultimate；
  date_from/date_to：`yyyy-MM-dd`（按 created_at 过滤）；order：id|created_at|last_login_at（默认 created_at），dir：asc|desc。
  → `data:{total,page,size,items:[{id,username,nickname,email,role,level,status,created_at,last_login_at,last_login_ip,register_ip,live_trading}]}`
- `GET /api/console/users/{id}` → `data:{user:{...全字段+ban_reason+ban_until}, stats:{sessions,messages,ai_configs,strategies,orders}}`
- `GET /api/console/users/{id}/logins?page&size` → `{total,page,size,items:[{id,ip,ua,device_model,os_version,app_version,success,created_at}]}`
- `GET /api/console/users/{id}/devices` → `items:[{id,device_id,device_model,os_version,app_version,last_seen_at,created_at}]`
- `GET /api/console/users/{id}/changes?page&size` → `items:[{id,field,old_value,new_value,operator,source,created_at}]`
- `POST /api/console/users/{id}/ban` body `{reason, days}`（days=0 永久）→ `data:null`（权限 users:ban）
- `POST /api/console/users/{id}/unban` → `data:null`（权限 users:ban）
- `POST /api/console/users/{id}/reset-password` body `{new_password}` → `data:null`（权限 users:resetpw）

### 3. 注册统计
- `GET /api/console/stats/overview` → `data:{user_total,user_today,user_yesterday,user_week,user_month,active_today,active_week,active_month,session_total,message_total,order_total,order_paid,income_total}`
- `GET /api/console/stats/trend?days=30` → `data:{items:[{date:"2026-10-14",registers:3,actives:2}]}`（按天补零，含今天）
- `GET /api/console/stats/retention?days=7` → `data:{days:7,cohorts:[{date:"2026-10-07",registered:5,retained:[{day:0,count:5,rate:1.0},{day:1,count:2,rate:0.4}]}]}`
  （retained day 从 0 到 days-1；rate 保留 4 位小数；cohort 按注册日期升序）

### 4. 管理员与角色
- `GET /api/console/admins` → `items:[{id,username,nickname,role_id,role_name,status,last_login_at,last_login_ip,created_at}]`
- `POST /api/console/admins` body `{username,nickname,password,role_id}` → `data:{id}`
- `PUT /api/console/admins/{id}` body `{nickname,role_id,status}` → `data:null`
- `POST /api/console/admins/{id}/reset-password` body `{new_password}` → `data:null`
- `DELETE /api/console/admins/{id}` → `data:null`（不能删自己、不能删 id=1）
- `GET /api/console/roles` → `items:[{id,name,code,perms:[...],remark,admin_count}]`
- `POST /api/console/roles` body `{name,code,perms,remark}` → `data:{id}`
- `PUT /api/console/roles/{id}` 同上 → `data:null`
- `DELETE /api/console/roles/{id}` → `data:null`（有管理员使用时 422）

### 5. 操作日志
- `GET /api/console/logs?page&size&keyword&admin_id&date_from&date_to` → `{total,page,size,items:[{id,admin_id,admin_name,action,method,path,params,ip,status,created_at}]}`
  （自动记录所有非 GET 的 console 请求；status 为 HTTP 状态码）

### 6. 系统配置
- `GET /api/console/config` → `data:{register_enabled:"1",register_need_email:"0",site_name:"Amore",announcement:"",app_version:"3.7",min_version:"3.0",maintain_mode:"0",pay_api_url:"",pay_pid:"",pay_key:"",pay_enabled:"0",...}`（值为字符串的扁平 map）
- `PUT /api/console/config` body 同结构（仅允许白名单 key，忽略未知 key）→ `data:null`
- `GET /api/console/announcements` → `items:[{id,title,content,type,enabled,start_at,end_at,created_at}]`
- `POST /api/console/announcements` body `{title,content,type,enabled,start_at,end_at}` → `data:{id}`
- `PUT /api/console/announcements/{id}` / `DELETE /api/console/announcements/{id}` → `data:null`
- `GET /api/console/versions` → `items:[{id,platform,version,build,force_update,download_url,notes,enabled,created_at}]`
- `POST /api/console/versions` body 同上 → `data:{id}`；`PUT /api/console/versions/{id}` / `DELETE /api/console/versions/{id}`

## 二、iOS App 接口（现有 + 新增；响应包 `{code:0,message,data}`）
### 保持不变（v3.7 兼容，勿动契约）
- `GET /api/ios/ping`、`POST /api/ios/login`、`POST /api/ios/register`、`GET /api/ios/me`、`POST /api/ios/logout`（形状见现有代码 IosCtl）

### 行为增强（响应形状不变）
- register：存 email、nickname=用户名、status=1、created_at、register_ip；系统配置关闭注册时 422 REGISTER_FAILED「注册已关闭」。
- login：封禁账号返回 403 `{code:"ACCOUNT_BANNED",message:"账号已被封禁：原因",data:null}`；成功写登录日志（ip/ua/device）+ 更新 last_login_at/last_login_ip。
- login/register 请求体新增可选字段（老 App 不传也不报错）：`device:{device_id,device_model,os_version,app_version}`。

### 新增（v2.0，additive）
- `GET /api/ios/profile`（需登录）→ `data:{user:{id,username,nickname,email,role,membership_level,live_trading_enabled,created_at,last_login_at}}`
- `POST /api/ios/profile`（需登录）body `{nickname?, email?}` → `data:{user:{...同上}}`；昵称 1~20 字符；email 合法性校验；写变更记录。
- `GET /api/ios/announcement`（白名单）→ `data:{id,title,content,type,updated_at}` 或 `data:null`
- `GET /api/ios/config`（白名单）→ `data:{register_enabled,maintain_mode,site_name,announcement,latest_version,min_version,force_update,download_url}`

### iOS App 内管理员页（现有路径，接真实数据，形状不变）
- `GET /api/admin/stats` → 真实统计（user_total/user_today/order_total/order_paid/order_pending/income_total/income_today）
- `GET /api/admin/users` → 真实用户（items 内含 id,username,role,membership_level [+status,nickname,created_at]）
- `GET /api/admin/orders` → 真实 member_orders 行
- `GET/POST /api/admin/settings(/save)` → sys_config 真实读写
- `GET/POST /api/admin/payment(/save)`、`GET/POST /api/admin/free-ai(/save)` → sys_config 真实读写
- `POST /api/admin/user/update` → 真实更新（status/level/nickname/email）
- `POST /api/admin/order/mark-paid` → 真实更新订单状态
- `GET /api/admin/plans` / `POST /api/admin/plans/save` → 代码默认价 + sys_config 覆盖

## 三、Web 面板静态资源
- `/panel` → Vue SPA（hash 路由，`/panel/index.html`），构建产物打进 jar `static/panel/`。
- 登录页 `/panel/#/login`；默认账号 `admin / Admin@2026`（首次登录强制改密可选）。

## 四、数据表（MySQL 8，库 quantokx）
- App 既有 16 表：users(+nickname,email,status,created_at,last_login_at,last_login_ip,register_ip,ban_reason,ban_until), sessions(弃用，会话入 Redis), ai_configs, ai_signals, strategies, strategy_runs, orders, positions, trades, trading_logs, system_logs, risk_configs, member_orders, chat_sessions, chat_messages。
- 新增管理侧 9 表：sys_admin, sys_role, sys_operation_log, sys_config, app_announcement, app_version, app_user_login_log, app_user_device, app_user_change_log。
- 迁移：SQLite qk.db → MySQL（python3 + sqlite3 标准库脚本，保留主键与 $qk$ 密码哈希，老用户 created_at=迁移时间）。
