# MyApp — 手机端开发的 iOS 待办应用

在 **iPhone 上写代码**，用 **GitHub Actions 的云端 Mac** 编译出 ipa。
全程不需要本地电脑装 Xcode。

## 为什么是这个方案

iPhone 上装不了 Xcode，也装不了能做 App 的 Swift Playgrounds（iPad 专属）。
但 iOS App 本质是「Swift 源码 + Apple 工具链 → 可执行包」，
把工具链放到云端的 macOS runner 上跑，手机只负责写和推 —— 路就通了。

```
iPhone（写代码 / git push）
        ↓
GitHub Actions（macos-15 runner）
        ↓
XcodeGen 生成工程 → xcodebuild 编译 → 打包 ipa
        ↓
GitHub Release（直接在手机上点下载）
        ↓
签名安装（TestFlight / 重签名工具）
```

## 项目结构

```
.
├── project.yml                 # XcodeGen 工程描述（唯一需要维护的「工程文件」）
├── MyApp/
│   └── Sources/
│       ├── MyApp.swift         # App 入口
│       ├── ContentView.swift   # 界面
│       ├── TodoStore.swift     # 数据 + UserDefaults 持久化
│       └── Assets.xcassets/    # 图标与强调色
└── .github/workflows/
    ├── build.yml               # 未签名 ipa 构建
    └── testflight.yml          # 已签名 + TestFlight 上传（需付费账号）
```

**为什么用 XcodeGen 而不是直接提交 `.xcodeproj`？**
`.xcodeproj` 是机器生成的 XML，几百行，冲突地狱，手机上根本没法改。
XcodeGen 用一份几十行的 YAML 描述工程，可读、可 diff、CI 里现场生成。

## 手机上怎么跑

1. App Store 装 **GitHub** 官方 App，登录
2. 进入本仓库 → **Actions** → `Build iOS App` → **Run workflow**
3. 等约 3–5 分钟（Mac runner 启动 + 编译）
4. 构建完成 → **Releases** 里下载 `MyApp.ipa`

改代码也在手机上：用 GitHub App 直接改文件，或者用本机的 iSH 环境
（`git add/commit/push`）—— 后者能本地跑脚本、批量改，更适合正经开发。

## 安装到手机的两条路

### 路线一：TestFlight（推荐，全无线，需付费账号）

需要 **Apple Developer Program（$99/年）**。

1. 在 [App Store Connect](https://appstoreconnect.apple.com) 创建 App，记下 **Bundle ID** 和 **App 的 Apple ID**（一串数字）
2. 生成 **App Store Connect API Key**（Users and Access → Integrations → App Store Connect API）
3. 到仓库 Settings → Secrets 添加：

   | Secret | 说明 |
   |---|---|
   | `ASC_KEY_ID` | API Key 的 Key ID |
   | `ASC_ISSUER_ID` | Issuer ID |
   | `ASC_KEY_P8` | 下载的 `.p8` 文件全文 |
   | `APPLE_TEAM_ID` | 开发者账号 Team ID |

4. 改 `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER` 为你的真实 Bundle ID
5. Actions 里跑 `Build & Upload to TestFlight`
6. 手机上装 **TestFlight** App，构建处理完（约 10 分钟）就会收到邀请，直接装

**优点**：完全无线、不用电脑、不用连数据线、能装给朋友测。
**注意**：每个构建只有 90 天有效期，到期重新发一版即可。

### 路线二：未签名 ipa + 重签名工具（不花钱）

免费 Apple ID 也能装，但需要**先在一台电脑上**用工具装一次（之后可以无线刷新）：

| 工具 | 说明 |
|---|---|
| **Sideloadly** | Windows/Mac，免费 Apple ID 签名，7 天有效期 |
| **AltStore / SideStore** | 侧载市场，SideStore 可纯手机运行（需配对文件） |
| **ESign / Scarlet** | 第三方签名，需要证书，稳定性看服务商 |

注意：免费账号签名的 App **7 天过期**，需要重新签。想要 1 年有效期就得付费账号。

## 本地（iSH）能做什么

```bash
cd /var/minis/workspace/ios-app-demo

# 改代码
vim MyApp/Sources/ContentView.swift

# 校验（本地没有 Swift 编译器，只能查语法结构和 YAML）
python3 -c "import yaml; yaml.safe_load(open('project.yml'))"

# 提交推送
git add -A && git commit -m "改动说明" && git push
```

本地 **不能** 编译 iOS —— 缺 Xcode 和 Apple SDK，这是设计使然，绕不过去。
但写代码、管版本、跑脚本、处理资源（图片压缩、图标生成）全都能在手机上完成。

## 已验证的东西

- Swift 源码括号配平、无未定义符号引用
- `project.yml` 与 `build.yml` YAML 语法合法
- 工作流会校验产物存在性，编译失败会明确报错并上传完整日志

## 下一步可以做的

- [ ] 接入真实 Bundle ID + 开发者账号 → 走 TestFlight
- [ ] 加单元测试 target，CI 里跑 `xcodebuild test`
- [ ] 加 App 图标（1024×1024 png 丢进 `AppIcon.appiconset/`）
- [ ] 数据层从 UserDefaults 换成 SwiftData
- [ ] 加通知提醒、小组件、iCloud 同步
