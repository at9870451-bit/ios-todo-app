# Doll Studio 3D — 部署教程

> 本功能已集成于 Amore 后端（quant-java-api v2.1.0），无需独立部署服务。
> 以下为完整部署/更新流程（已在 154.12.16.204 实测）。

---

## 1. 前置条件

| 组件 | 要求 | 本项目实测 |
|---|---|---|
| Java | JDK 21 | `/www/server/java/jdk-21.0.2`（宝塔自带） |
| Maven | 3.9.x | `/opt/maven` |
| Node | ≥18（仅构建管理台需要） | `/opt/node`（v20.18.0） |
| MySQL | 8.x | 库 `quantokx`（表由 SchemaBoot 启动自动创建） |
| 服务 | systemd `quantokx-java` | jar 位于 `/opt/quantokx-java/app.jar` |

## 2. 构建步骤（服务器上执行）

```bash
# 0) 上传源码包（本地打包：tar czf doll-deploy.tgz --exclude='.git' --exclude='node_modules' \
#      --exclude='target' quant-java-api admin-web）
mkdir -p /opt/doll-src && tar xzf /tmp/doll-deploy.tgz -C /opt/doll-src

# 1) 构建管理台（产物自动输出到 quant-java-api/src/main/resources/static/panel）
export PATH=/opt/node/bin:/opt/maven/bin:/www/server/java/jdk-21.0.2/bin:$PATH
cd /opt/doll-src/admin-web
npm install --no-audit --no-fund --legacy-peer-deps
npm run build

# 2) 打包后端
cd /opt/doll-src/quant-java-api
mvn -B package -DskipTests
ls -la target/*.jar
```

> 也可走 GitHub CI：推送 tag `quant-java-v*` → Actions 自动构建 jar 并发 Release。

## 3. 部署与重启

```bash
cd /opt/quantokx-java
cp app.jar app-backup-$(date +%m%d).jar          # 备份
cp /opt/doll-src/quant-java-api/target/quant-java-api-2.1.0.jar app.jar
systemctl restart quantokx-java
sleep 15
systemctl is-active quantokx-java

# 启动即自动执行 SchemaBoot：建 doll_* 四张表 + 写入 7 分类/32 款式种子
curl -s http://127.0.0.1:8080/api/ios/ping
```

## 4. 验证清单（curl 实测命令）

```bash
# 4.1 未登录访问应返回 401（ doll 接口全部在会话保护内）
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/api/doll/catalog

# 4.2 注册测试账号并登录（拿会话 Cookie + CSRF）
curl -s -c /tmp/ck -X POST http://127.0.0.1:8080/api/ios/register \
  -H 'Content-Type: application/json' \
  -d '{"username":"dolltest1","password":"Doll@2026test","password_confirmation":"Doll@2026test"}'
CSRF=$(curl -s -b /tmp/ck -c /tmp/ck http://127.0.0.1:8080/api/ios/me | grep -o '"csrf_token":"[^"]*"' | cut -d'"' -f4)

# 4.3 目录（应返回 7 分类 + 32 款式）
curl -s -b /tmp/ck http://127.0.0.1:8080/api/doll/catalog | head -c 400

# 4.4 保存穿搭 → 列表 → 收藏 → 删除
curl -s -b /tmp/ck -X POST http://127.0.0.1:8080/api/doll/outfits \
  -H "Content-Type: application/json" -H "X-CSRF-TOKEN: $CSRF" \
  -d '{"name":"测试搭配","gender":"female","skin":"#F6D7BE","state":"{\"gender\":\"female\"}"}'

# 4.5 AI 推荐（需要该用户有可用 AI 配置；无配置返回 AI_NO_CONFIG 为正常路径）
curl -s -b /tmp/ck -X POST http://127.0.0.1:8080/api/doll/ai/recommend \
  -H "Content-Type: application/json" -H "X-CSRF-TOKEN: $CSRF" \
  -d '{"gender":"female","prompt":"夏天海边度假"}'
```

## 5. 管理台使用

1. 访问 `http://<服务器>:8080/panel/`（管理员登录）
2. 侧边栏新增 **Doll Studio** 菜单（权限码 `doll:manage`，启动时自动补进所有角色）
3. 五个面板：
   - **服饰款式**：增删改查、启停、默认色、上传自定义 3D 模型（.usdz/.glb，≤30MB）、模型缩放/Y偏移
   - **服装分类**：改名/排序/启停（code 与 App 3D 构建器绑定）
   - **穿搭记录**：全用户穿搭查看/删除
   - **AI 调用日志**：每次推荐的请求/结果/耗时/错误
   - **AI 配置**：查看用户 AI 配置（密钥掩码，真实密钥仅在服务端使用）

## 6. 文件与目录

| 路径 | 说明 |
|---|---|
| `/opt/quantokx-java/app.jar` | 运行 jar |
| `/opt/quantokx-java/data/doll-models/` | 上传的 3D 模型（自动创建，经 `/doll-assets/**` 下发） |
| `/opt/quantokx-java/app.env` | 服务环境变量（DB_URL/DB_USER/DB_PASSWORD 等） |

## 7. 回滚

```bash
cd /opt/quantokx-java && cp app-backup-MMDD.jar app.jar && systemctl restart quantokx-java
```

## 8. iOS 发版

- 源码：仓库 `quant-php-ios/`（玩偶模块：`Sources/Core/DollModels.swift`、`Sources/Core/DollScene.swift`、`Sources/Views/DollStudioView.swift`）
- 发版：打 tag `quant-php-v3.9`（v3.9 build 30）→ GitHub Actions 构建 Amore.ipa → Release 下载
- 底部导航 5 Tab：聊天 / 对话 / **玩偶（Doll Studio 3D）** / 设置 / 我的
