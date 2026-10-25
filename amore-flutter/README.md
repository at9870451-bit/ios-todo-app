# iMessage 风格即时通讯 App（Flutter + Rust）

基于 **Flutter UI + Rust Core（C FFI JSON 总线）** 的 iOS 即时通讯 App。
界面高度参考 Apple iMessage：蓝/灰气泡、联系人列表、头像、时间戳、**已读状态**、
输入框与附件菜单、毛玻璃底部导航、统一圆角与细腻阴影；**严格无渐变**，支持深色模式。

## 一、项目目录

```
amore-flutter/
├── pubspec.yaml            # 依赖：provider / dio / image_picker / file_picker / crypto / flutter_tts …
├── lib/
│   ├── main.dart           # 入口：App 主题（苹果白 #FFFFFF/#F5F5F7/#1D1D1F/#86868B/#007AFF）
│   │                       #      + 底部 Liquid Glass 毛玻璃导航（聊天/对话/我的/设置）
│   ├── core/
│   │   ├── bridge.dart     # ★ Flutter ↔ Rust 通信（FFI dlsym JSON 总线）
│   │   ├── store.dart      # AmoreStore：好友/群/历史/配置 全部存储 API
│   │   ├── models.dart     # ChatFriend / ChatGroup / ChatMessage(含 read 已读) / AIProvider
│   │   ├── chat_engine.dart# 对话编排：模型请求 + 工具循环 + AOJIT + 附件产物回发
│   │   ├── code_engine.dart# 本地代码引擎（表达式求值/哈希/压缩/编码，纯 Dart 沙盒）
│   │   ├── aojit_runtime.dart # AOJIT 组件镜像执行层（sha256/blake2s/zlib/struct/…）
│   │   ├── attachments.dart# [atts] 附件协议 + 沙盒持久化
│   │   ├── permissions.dart# 隐私权限（健康/日历/照片/位置/HomeKit/剪贴板）
│   │   └── mirrors.dart    # 镜像源（APK/pip/npm）
│   ├── pages/
│   │   ├── chat_list_page.dart   # 联系人/会话列表（好友+群，iMessage 样式行）
│   │   ├── chat_room_page.dart   # 好友聊天室（气泡+已读+附件+语音）
│   │   ├── group_chat_page.dart  # 群聊（全员回复+群游戏）
│   │   ├── chat_screen_page.dart # AI 对话页（工具循环）
│   │   └── settings_page.dart / permissions_page.dart / rootfs_page.dart / skills_page.dart …
│   └── widgets/
│       ├── bubble.dart     # 蓝/灰气泡、时间戳、已读状态、长按菜单（复制/记忆/删除单条）
│       ├── chat_background.dart # 聊天背景（图片+透明度+可选模糊，纯色 fallback）
│       ├── attachment_card.dart # 附件卡片（图片缩略/视频/文件，点击放大）
│       └── …
├── native/amore_core/      # Rust Core（crate）
│   ├── src/
│   │   ├── lib.rs          # FFI 导出 amore_call / amore_free；方法分发
│   │   ├── store.rs        # JSON 文件存储：friends/groups/history(config 亦可)
│   │   │                   # history：load/append/replace/remove(按 id 删单条)/clear
│   │   ├── tools.rs        # 聊天工具协议（XML 解析+本地工具执行）
│   │   ├── tts.rs          # 语音请求组装
│   │   └── reflect.rs      # 反射数学（fx.reflect）
│   └── Cargo.toml
└── ios/                    # iOS 壳（CI 生成：flutter create + xcconfig 补丁 + Info.plist 权限注入）
```

## 二、依赖配置

```yaml
# pubspec.yaml（节选）
dependencies:
  provider: ^6.1.1        # 状态管理
  dio: ^5.4.3              # HTTP（模型接口/MCP/图片下载）
  image_picker: ^1.1.2     # 相册/拍照
  file_picker: ^8.1.2      # 文件选择
  path_provider: ^2.1.3    # 沙盒路径
  flutter_tts: ^4.0.2      # 本地朗读
  audioplayers: ^6.1.0     # 语音播放
  crypto: ^3.0.3           # sha256/md5/sha1/hmac（AOJIT 哈希镜像）
```

## 三、Flutter ↔ Rust 通信（FFI JSON 总线）

采用 **C FFI + dlsym + JSON 字符串** 总线（轻量、无第三方绑定，iOS/Android 通用）。
核心见 `lib/core/bridge.dart` + `native/amore_core/src/lib.rs`：

```dart
// Dart 侧（bridge.dart 核心）
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:convert';
import 'package:flutter/services.dart' show MethodChannel;

typedef _AmoreCallNative = Pointer<Utf8> Function(Pointer<Utf8>);
final DynamicLibrary _lib = Platform.isIOS
    ? DynamicLibrary.process()        // iOS 通过 -force_load 链入静态库
    : DynamicLibrary.open('libamore_core.so');

/// 同步调用 Rust：入参 JSON 字符串 → 返回 JSON 信封字符串
static Map<String, dynamic> call(String method, Map<String, dynamic> params) {
  final fn = _lib.lookupFunction<_AmoreCallNative, _AmoreCallNative>('amore_call');
  final json = jsonEncode({'method': method, 'params': params});
  final out = fn(_toUtf8(json)).toDartString();
  return jsonDecode(out) as Map<String, dynamic>;
}
```

```rust
// Rust 侧（lib.rs 核心）
#[no_mangle]
pub extern "C" fn amore_call(payload: *const c_char) -> *mut c_char {
    let input = unsafe { CStr::from_ptr(payload) }.to_string_lossy().to_string();
    let (method, params) = parse(&input);
    let data = dispatch(&method, &params);        // 路由到 store/tools/tts/reflect
    to_c_string(&ok_envelope(data))              // {"ok":true,"data":{...}}
}
```

**调用示例**（Dart 使用层）：

```dart
// 存储
final friends = AmoreStore.listFriends();                 // → store.list_friends
AmoreStore.saveFriend(f);                                 // → store.save_friend
AmoreStore.appendHistory('friend.f_xiaoman', 'user', '你好'); // → history.append

// 历史 + 已读
final msgs = AmoreStore.loadHistory(key);
msgs.last.read = true;
AmoreStore.replaceHistory(key, msgs);                     // → history.replace

// 工具协议
final parsed = AmoreStore.parseAssistant(reply);          // → chat.parse_assistant
AmoreStore.execTool('calc', {'expression': '12*(3+4)'});  // → chat.exec_tool
```

## 四、模拟聊天数据（首次启动自动生成）

`AppState._seedDemoData()`：首次启动（`seed_done` 未设置）预置 4 个会话——

| 会话 | 内容 |
|---|---|
| 林小满 | 7 条：约饭/帮看方案，最后一条自己消息**已读** |
| 陈一诺 | 5 条：头像/看展，最后一条自己消息**未读（已送达）** |
| 李哲 | 4 条：接口文档/发版 |
| 周末爬山小分队 | 4 条群聊 |

数据经 Rust 存储（history.append + history.replace 写 read 标记），全部真实可读写、
可删除单条、可清空。重置方式：本地终端 `reset` 或删除沙盒后重装。

## 五、核心页面

- **会话列表**（chat_list_page）：好友/群行（头像、名称、最后消息、时间、未读红点逻辑），左滑/长按菜单
- **好友聊天室**（chat_room_page）：iMessage 蓝/灰气泡、时间戳、**已读/已送达**、长按（复制/记忆/删除单条）、附件（文件/照片/视频/拍照/AI 生图）、语音气泡
- **群聊**（group_chat_page）：全员回复、群游戏（塔罗/狼人杀）、消息钩子
- **输入面板**：加号附件菜单（文件/照片/视频/拍照/AI 生成图片）+ 待发送预览条 + 发送按钮
- **设置**：主题（浅/深/跟随系统）、自定义主色、聊天背景图（透明度/模糊）、气泡样式、头像形状、字体、字号
- **权限**：全部自动允许 + 隐私 7 项（健康/日历/提醒/照片/位置/HomeKit/剪贴板）
- **Rootfs**：沙盒存储总览/按类清理/镜像源（APK/pip/npm）/AOJIT 组件执行

## 六、iOS 编译部署

```bash
# 1) 环境：Xcode 15+ / Flutter stable（CI 用 master 亦可） / Rust stable + aarch64-apple-ios target

# 2) 编译 Rust 静态库
cargo build --release --target aarch64-apple-ios \
    --manifest-path native/amore_core/Cargo.toml
cp native/amore_core/target/aarch64-apple-ios/release/libamore_core.a native/libs/ios/

# 3) 生成 iOS 工程（首次）
flutter create --org com.quantokx --project-name amore .
#   （或直接用仓库 CI：GitHub Actions amore-flutter.yml 自动完成全部步骤）

# 4) 注入 FFI 符号（-force_load）与 Info.plist 权限（相册/相机/麦克风/文件）
ruby tools/fix_xcodeproj.rb
python3 tools/inject_plist_perms.py

# 5) 构建 IPA（免签名）
flutter build ios --config-only --release --no-codesign
cd ios && xcodebuild -workspace Runner.xcworkspace -scheme Runner \
    -configuration Release -sdk iphoneos -derivedDataPath ../build \
    CODE_SIGNING_ALLOWED=NO build

# 6) 打包
mkdir Payload && cp -R ../build/Build/Products/Release-iphoneos/Runner.app Payload/
zip -qry Amore.ipa Payload
# 安装：TrollStore / Sideloadly / Xcode（自行签名）均可
```

**CI 自动构建**（`.github/workflows/amore-flutter.yml`）：push 到 `flutter-core` 自动
构建 → 上传 artifact → 发 Release（flutter-build-N，可直接下载 ipa）。

## 七、已知能力一览（全部真实实现）

附件（文件/照片/视频）· AI 生成图片 · 语音朗读（本地/模型/硅基/豆包）· 技能中心
（Skill 函数调用/插件钩子/工作包 manifest/MCP 服务）· 本地编程（run_code/AOJIT 镜像
执行：sha256、md5、blake2s、zlib、base64、crc32、struct、正则、日期）· 单条删除 ·
已读状态 · 镜像源 · 权限管理 · 工具与权限（AI 能力模式/工具确认/MCP 超时）· 深色模式。
