# QuantOKX PHP 后端（iOS 版：纯 API）

完整后端源码 = 用户提供的 `quant-okx-v37-bottom-nav.zip`（ThinkPHP 8.1 + PHP 8.2 + MySQL 5.7.44）。
本目录存放为「iOS App 版」新增/修改的文件，部署时覆盖到完整源码对应路径即可。

## v2 变更：网页前端全部移除

- **route/app.php**：删除全部网页页面路由（登录/注册/控制台/OKX/策略/AI/风控/台账/会员/管理端页面），
  只保留 `/api/*` + `/install`（部署向导）+ `Route::miss` 兜底（返回 WEB_UI_REMOVED 提示）。
- **app/middleware/Auth.php**：兜底从「redirect /login」改为返回 JSON 提示。
- **app/middleware/InstallGuard.php**：已安装后访问 /install 返回 JSON 提示。

所有原网页功能（包括管理端）全部迁移至 iOS App 客户端。

## iOS 接口（v1 已有）

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/ios/ping` | 连通性自检（免登录），下发 CSRF token |
| POST | `/api/ios/login` | JSON 登录 |
| POST | `/api/ios/register` | JSON 注册 |
| GET | `/api/ios/me` | 当前用户+会员徽章+CSRF |
| POST | `/api/ios/logout` | 退出 |

写操作需带 `X-CSRF-TOKEN` 头；会话 Cookie 名 `QBSESSID`；统一响应 `{"code":0,"message":"...","data":{}}`。

## 管理端 API（iOS 内管理界面使用）

`/api/admin/{stats,users,user/update,orders,order/mark-paid,plans,plans/save,free-ai,free-ai/save,payment,payment/save,settings,settings/save}`
—— 需 role=admin 的账号会话（iOS App 里用管理员登录后自动可用）。
