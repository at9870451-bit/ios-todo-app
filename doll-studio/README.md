# Doll Studio 3D — 完整项目

iPhone 3D 虚拟玩偶换装 App：**SwiftUI + SceneKit（程序化 3D 玩偶，USDZ 通道预留）** + **Spring Boot 3 Java 后端** + **MySQL** + **单文件 Web 管理后台** + **AI 穿搭助手（服务端代理）** + **音频/音量模块**。

```
doll-studio/
├── ios/                     # SwiftUI + SceneKit 完整源码（XcodeGen 工程）
│   ├── project.yml
│   └── DollStudio/
│       ├── App/DollStudioApp.swift        # 入口
│       ├── Models/Models.swift            # 数据模型 + 内置示例目录（31 件服装/3 玩偶）
│       ├── Services/
│       │   ├── OutfitStore.swift          # 状态中枢：穿搭/撤销重做/收藏/作品/持久化
│       │   ├── APIClient.swift            # RESTful 客户端（重试/错误分类）
│       │   ├── AIAssistant.swift          # AI 搭配（服务端 AI 优先 → 本地规则降级）
│       │   └── AudioService.swift         # 音效/BGM/AI 语音，三路音量
│       └── Views/
│           ├── DollSceneView.swift        # ★ SceneKit：程序化玩偶+参数化服装+手势
│           ├── RootView.swift             # 主页（顶栏/3D/视角/姿势/分享/AI Sheet）
│           ├── WardrobePanel.swift        # 衣橱面板（分类/缩略图/颜色/撤销）
│           └── OtherViews.swift           # 作品列表/收藏/性别选择/设置/登录
├── api-java/                # Spring Boot 3 后端（端口 8090，context-path=/api）
│   ├── pom.xml
│   ├── schema.sql                         # MySQL 建表 + 种子数据（启动时也会自动执行）
│   └── src/main/java/com/quantokx/dollstudio/
│       ├── DollStudioApiApplication.java
│       ├── WebConfig.java                 # CORS + 认证拦截器注册
│       ├── auth/TokenUtil.java            # HMAC token（30 天）
│       ├── auth/AuthInterceptor.java      # Bearer 校验（用户/管理员负数 uid）
│       ├── db/SchemaInit.java             # 启动建表 + 自动创建 admin
│       └── web/DollStudioController.java  # 全部端点（用户+AI+管理）
├── admin/index.html         # Web 管理后台（单文件，零依赖）
└── README.md
```

## 一、iOS 本地运行

```bash
brew install xcodegen
cd doll-studio/ios
xcodegen generate
open DollStudio3D.xcodeproj      # Xcode 直接 Cmd+Run
```

- 无任何第三方依赖（纯 SwiftUI + SceneKit），Xcode 15+ / iOS 16+
- **游客模式开箱即用**：内置 31 件程序化服装、3 个玩偶、AI 本地规则引擎、撤销/重做/收藏/作品全离线可用
- 登录/远程服装/AI 服务端模式：在「设置 → 服务端」填 API 地址后自动启用

## 二、后端部署（Java）

```bash
# 1. 建库（或直接启动——应用自动建表）
mysql -u root -p < doll-studio/api-java/schema.sql
# 2. 构建与运行
cd doll-studio/api-java
mvn -q package -DskipTests
DB_HOST=127.0.0.1 DB_NAME=doll_studio DB_USER=doll DB_PASS='强密码' \
TOKEN_SECRET='随机长字符串' \
java -jar target/doll-studio-api-1.0.0.jar
# 3. 验证
curl http://127.0.0.1:8090/api/health
# 4. Nginx 反代（HTTPS 必需）
# location /api/ { proxy_pass http://127.0.0.1:8090/api/; }
```

- 管理后台：把 `admin/index.html` 放到任意静态托管（或 Nginx root），访问后登录
  - 初始管理员 `admin / Admin@2026`（应用启动日志会提示；**首次登录后立即在数据库改密码**：`UPDATE admins SET password_hash='<新 bcrypt>' WHERE username='admin';`）
- AI 配置：管理后台「AI 配置」→ 填 OpenAI 兼容 base/key/model。**API Key 只存服务端数据库，客户端永远不接触**

## 三、API 文档（全部 JSON；context-path=/api）

| 方法 | 路径 | 认证 | 说明 |
|---|---|---|---|
| POST | /api/auth/login | - | `{username,password}` → `{token,nickname}` |
| GET | /api/dolls | - | 玩偶模型列表（usdz_url 为空 = 程序化模型） |
| GET | /api/clothes/categories | - | 服装分类 |
| GET | /api/clothes | - | `?category=top` 按分类；否则全量 |
| GET | /api/clothes?id=xxx | - | 服装详情 |
| GET | /api/config | - | 公开配置（默认音量等） |
| GET | /api/assets | - | uploads 目录资源清单 |
| POST | /api/outfits | Bearer | 保存作品 `{name,doll_id,gender,skin,slots}` |
| GET | /api/outfits | Bearer | 我的作品列表 |
| GET | /api/outfits/detail?id= | Bearer | 作品详情 |
| DELETE | /api/outfits?id= | Bearer | 删除作品（仅本人） |
| POST | /api/ai/outfits | Bearer | `{gender,prompt,catalog}` → `{items:[{category,cloth_id}],reason,source}`（服务端校验服装真实存在 + 限流 + 日志 + 每日额度） |
| POST | /api/admin/login | - | 管理员登录 |
| CRUD | /api/admin/clothes、/dolls、/categories | Admin | 服装/玩偶/分类管理（POST upsert / DELETE） |
| GET/POST | /api/admin/ai-config | Admin | AI 配置（Key 脱敏回显） |
| GET | /api/admin/ai-logs、/admin/stats | Admin | 调用日志 / 统计 |

错误统一：`{"ok":false,"error":"..."}` + HTTP 状态码；限流 429；未登录 401；权限 403。

## 四、3D 资源导入规范（从程序化 → 正式 USDZ）

当前 App 使用 **SceneKit 程序化模型**（无外部资源即可完整体验换装）。切换正式资源：

1. **服装**：后台服装的 `kind` 填 `usdz`、`model_url` 填 USDZ 地址（https 直链或 /api/assets 上传的文件路径）。客户端 `SCNReferenceNode` 加载。建议：单件 ≤ 2MB、Draco/usdz 压缩、原点在挂载点、Y 轴向上、单位米
2. **挂载约定**：模型需按服装分类对齐内置骨架（躯干中心 y≈1.28、头 y≈1.46、脚 y≈0.05，身高 1.0 基准）。不同体型适配：客户端按 heightScale/肩宽自动缩放整件
3. **玩偶**：`dolls.usdz_url` 非空即替换程序化身体（需含 pivot.armL/pivot.armR 节点以支持姿势与袖子挂载）
4. **AI 生成图片 ≠ 3D 模型**：文生图仅用于概念图/灵感（预留 /api/assets 存储与缩略图字段）；可穿 3D 资源必须经建模+绑定流程

## 五、音频与隐私

- 三路独立音量：音效 / 背景音乐 / AI 语音（设置页滑块，本地持久化）
- 音效=系统短音（跟随系统音量与静音键）；BGM=沙盒 Documents 放入 `bgm.mp3` 即启用
- AI 语音：后端 TTS 返回音频 data → AudioService.playVoice(data)（占位接好）
- **不录音、不采集麦克风**；麦克风权限仅在未来语音对话功能启用时声明（Info.plist 已预置描述）

## 六、安全清单

- ✅ 全站 HTTPS（部署层强制）
- ✅ AI API Key 仅存服务端 `ai_config` 表；管理后台回显脱敏
- ✅ 密码 bcrypt；token HMAC+过期；SQL 全预编译；输出 JSON
- ✅ 接口限流（每 IP 每分钟可配）；AI 每日总额度
- ✅ 作品访问权限校验（所有 outfits 查询强制 user_id）
- ⚠️ 上传接口（管理端扩展项）需校验类型/大小——当前版本仅列出 uploads 清单，上传走运维通道

## 七、测试用例与异常处理

| 场景 | 预期 |
|---|---|
| 无网络启动 App | 内置目录可用，AI 走本地规则并标注「本地演示模式」 |
| 后端 500 | App SnackBar/文本显示「服务错误 500」，重试按钮（AI Sheet 重新生成） |
| token 过期（30 天） | 401 → 提示重新登录，本地数据不受影响 |
| 服装互斥（戴两顶帽） | 后选择顶替换先选择顶（exclusive_group=hat） |
| 付费服装未解锁 | 缩略图置灰+锁 → 点击本地模拟解锁（正式版接服务端订单） |
| 撤销/重做 | 穿、脱、改色均可撤销（上限 50 步）；重做栈在新操作时清空 |
| AI 返回不存在的 cloth_id | 服务端二次校验剔除，只下发真实存在的 ID |
| AI 每日额度耗尽 | 429「今日 AI 调用已达上限」 |
| 双指缩放越界 | 距离钳制 2.6–7.0 |
| 删除他人作品 | DELETE 强制 user_id 匹配，返回 deleted:0 |

## 八、后续路线

- macOS 端（SwiftUI 多平台）、AR 快速查看（QuickLook USDZ）、服装商店与订单、AI 文生图概念图接入
