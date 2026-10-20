# Amore Flutter 开发契约（并行开发规格）

## 架构
- Flutter UI（Dart）+ Rust Core（FFI JSON 总线）
- Rust 负责：存储（JSON 文件落沙盒）、厂商目录 505 模型、提示词组装、工具调用协议、本地工具执行
- Dart 负责：全部 UI、HTTP（dio）、音频播放、编排循环（chat_engine.dart）

## 已就绪的基础设施（直接 import 使用，不要重复实现）
```dart
import '../core/models.dart';   // ChatFriend(15字段) ChatGroup ChatMessage AIProvider AgentTemplate AIVendor
import '../core/store.dart';    // AmoreStore.* 全部存储 API + parseAssistant/execTool/buildSystemPrompt/ttsRequest
import '../core/theme.dart';    // AmoreTheme.* 颜色/cardBox()/tile()/avatar()/pageGradient()/dark()
import '../core/chat_engine.dart'; // ChatEngine.send(friend:, userText:, onToolCall:) / providerFor / request
import '../state/app_state.dart';  // AppState（Provider<AppState>）：friends/groups/agents/providers/config/toast/refresh*
```

AmoreStore API 速查：
- 好友：listFriends()→List<ChatFriend> / saveFriend(f) / deleteFriend(id)
- 群组：listGroups() / saveGroup(g) / deleteGroup(id)
- 智能体：listAgents() / saveAgent(a) / deleteAgent(id)
- 供应商：listProviders() / saveProvider(p) / deleteProvider(id) / activeProviderId() / setActiveProvider(id)
- 配置 KV：allConfig() / setConfig(k,v) / getConfig(k)
- 目录：vendors()→List<AIVendor> / modelsOf(vendorKey)→List<String> / searchModels(q)
- 历史：loadHistory('friend.{id}'或'group.{id}') / appendHistory(key, role, content) / clearHistory(key) / countHistory(key)
- 聊天协议：parseAssistant(text)→ChatAssistantReply{clean,feedback,called} / execTool(name,params)→ToolResult
- 提示词：buildSystemPrompt(friend) / extractMemory(text)→List<String> / stripMemory(text)
- TTS：ttsRequest(engine:,voiceId:,apiKey:,text:)→{url, headers, body}

ChatEngine API：
- providerFor(friend)→AIProvider?（好友专属>全局激活）
- isDirect(p)（127.0.0.1/localhost 本机直连）
- completionsUrl(p)（/chat/completions 自动补全）
- request(p, messages, systemPrompt)→String（单次，支持 responses 格式）
- send(friend:, userText:, onToolCall:, extraSystem:)→ChatTurnResult{text?,error?,tools}——已含：写历史、工具循环≤3轮、记忆抽取、touchFriend

主题速查：AmoreTheme.bg/card/accent(蓝紫#6C8CFF)/bubbleMe/bubbleOther/textPrimary/textSecondary/danger/success/warn；AmoreTheme.dark() 已挂 MaterialApp；组件：AmoreTheme.tile(...)/avatar(name)/cardBox()/pageGradient()/accentGradient()/sectionLabel()/title()

AppState（context.read<AppState>()）：
- friends/groups/agents/providers/config 字段 + refreshAll()/refreshSocial()/refreshProviders()/refreshAgents()
- activeFriend（ValueNotifier<ChatFriend?>）/ setActiveFriend(f) / activeGroup / setActiveGroup(g)
- showToast(msg) / serverUrl() / dndEnabled()/setDnd(v) / dailyBudget()/setDailyBudget(v) / globalVoiceEngine()/setGlobalVoiceEngine(v)

## 通用规范
1. 全部深色，Material 3，无 Swift 概念残留；页面 Scaffold body 套 `Container(decoration: AmoreTheme.pageGradient(), child: SafeArea(child: ...))`
2. 不用 build_runner/codegen；不引入新依赖（dio/provider/audioplayers/path_provider/intl/ffi 已有）
3. 空状态都要有优雅占位（图标+文案+可选按钮）
4. 中文文案，与 SwiftUI 版一致
5. 异步用 async/await；FFI 调用是同步的（很快，直接调）
6. 常用组合：标题行 `Text('页面名', style: AmoreTheme.title())`

## 页面清单与文件路径（pages/）
| 文件 | 对齐 Swift | 说明 |
|---|---|---|
| chat_list_page.dart | ChatListView.swift | Tab0：好友+群组会话列表（右上添加好友/建群），点进「对话」Tab |
| chat_screen_page.dart | ChatScreen.swift | Tab1：当前好友聊天（气泡/输入栏/工具显示/语音条/红包/链接卡片/加号菜单：定时消息/红包/语音通话） |
| doll_studio_page.dart | DollStudioView.swift | Tab2：玩偶工作室（3D 区域 M5 占位，换装选项/形象选择 UI 齐全） |
| profile_page.dart | ProfileView.swift | Tab3：我的（入口列表：模型配置/外观/智能体/本地终端/历史会话/设置/会员中心） |
| group_chat_page.dart | GroupChat.swift | 群聊页（从会话列表进入；成员头像/全员回复/气泡内语音条 plain 模式） |
| agent_list_page.dart | AgentListView.swift | 智能体模板列表+编辑器（从模板导入到好友） |
| providers_page.dart | ProvidersView.swift | 模型配置：供应商列表/编辑（厂商选择→模型选择器 505/手输/Key/Base/格式）+ 激活 |
| appearance_page.dart | AppearanceView.swift | 外观设置 |
| membership_page.dart | MembershipView.swift | 会员中心（等级卡片/权益列表/对接服务端 API 占位） |
| settings_page.dart | SettingsView.swift | 设置（服务端地址/夜间免打扰/每日预算/全局语音引擎/数据导出/清空） |
| console_page.dart | LocalConsoleView.swift | 本地终端（黑底绿字命令台，命令在 Dart 层解释：info/ls friends|groups|models|history/cat friend N/clear chat/wipe memory/reset models/export/date/whoami/help） |
| conversations_page.dart | ConversationListView.swift | 历史会话（服务端会话列表，AuthGate 未登录提示） |

## widgets/（公共组件）
| 文件 | 内容 |
|---|---|
| bubble.dart | MessageBubble（我方 accentGradient/对方 bubbleOther；时间戳；长按菜单：复制/删除/置顶记忆） |
| voice_bubble.dart | VoiceBubble（[语音:Ns] 标记→可播放条，plain 模式参数——群聊嵌套时不画自身卡片背景） |
| red_packet.dart | RedPacketParser（[红包:金额|祝福] 解析）+ RedPacketCard + 领取弹窗 + 发红包弹窗 |
| link_card.dart | 链接检测（URL 正则）→ 链接卡片（域名+打开按钮） |
| call_view.dart | 语音通话全屏（头像/波形动画/挂断），接 audioplayers 播 TTS |

## 聊天消息格式（文本协议，与 SwiftUI 版一致）
- 语音：`[语音:内容]` 或 `[语音：内容]`（AI 生成；用户录音为 `[语音:Ns]转写文字`）
- 红包：`[红包:金额|祝福语]`
- 记忆：`[记忆:一句话]`（Rust parse 后剥离；FriendEdit 编辑 friend.memory）
- 工具：`<tool name="xx"><param name="k">v</param></tool>`（Rust 解析回注）

## 聊天循环（页面调用 ChatEngine.send 即可，已实现；群聊参考：）
群聊全员回复 = 对每个 member（好友）依次 await ChatEngine.send(friend: member, userText: msg, extraSystem: 群聊上下文提示)，并把回复 append 到 'group.{groupId}' 历史 + UI 逐条出现。系统提示词由 Rust buildSystemPrompt 生成，群聊时 extraSystem 传：'当前是群聊「{groupName}」，群里还有：{成员名单}。以 {好友名} 的身份自然回应，不要重复他人刚说过的话。'
