# QuantOKX PHP 后端（iOS 适配增量）

完整后端源码 = 用户提供的 `quant-okx-v37-bottom-nav.zip`（ThinkPHP 8.1 + PHP 8.2 + MySQL 5.7.44）。
本目录仅存放为 iOS 客户端新增/修改的文件，部署时覆盖到完整源码对应路径即可。

## 增量文件

| 文件 | 说明 |
| --- | --- |
| `app/controller/api/Ios.php` | 新增：iOS JSON 接口（login/register/me/logout/ping） |
| `app/middleware/Auth.php` | 修改：iOS 登录前接口加入鉴权豁免 |
| `route/app.php` | 修改：注册 5 条 iOS 路由 |

## iOS 接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/ios/ping` | 连通性自检（免登录），下发 CSRF token |
| POST | `/api/ios/login` | JSON 登录 `{username,password}`，返回用户+CSRF |
| POST | `/api/ios/register` | JSON 注册 `{username,password,password_confirmation,email?}` |
| GET | `/api/ios/me` | 当前用户+会员徽章+CSRF（需登录） |
| POST | `/api/ios/logout` | 退出（需登录+CSRF） |

## 部署（已在 64.83.22.85 完成）

- 站点目录：`/www/wwwroot/quant-okx`（nginx root 指向 `public/`）
- 数据库：`quant` / 用户 `quant`（凭据在服务器 `/root/.mysql-app-pw`）
- 管理账号：`admin`（密码在服务器部署时设置）
- 写操作需带 `X-CSRF-TOKEN` 头（值来自 login/me/ping 响应）
- 会话 Cookie 名：`QBSESSID`
