// Amore 对话 Tab — AI 对话（1:1 对齐旧 SwiftUI ChatScreen.swift：问候 header/HeroBanner/
// 空状态建议/推理强度状态行/单行输入面板/朗读/新对话/本地会话恢复）
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import 'package:provider/provider.dart';

import '../core/attachments.dart';

import '../core/chat_engine.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/skill_pack.dart';
import '../core/theme.dart';
import '../widgets/attachment_card.dart';
import '../widgets/chat_background.dart';
import '../ui/effects.dart';
import '../state/app_state.dart';
import 'conversations_page.dart';
import '../ui/motion.dart';
import 'workflow_history_page.dart';
import 'workflow_page.dart';

class ChatScreenPage extends StatefulWidget {
  const ChatScreenPage({super.key});

  @override
  State<ChatScreenPage> createState() => _ChatScreenPageState();
}

class _ChatScreenPageState extends State<ChatScreenPage> {
  final _inputCtl = TextEditingController();
  final _scrollCtl = ScrollController();
  final _focus = FocusNode();
  List<ChatMessage> _messages = [];
  bool _sending = false;

  // 朗读（本地引擎，对齐 tts.engine = local）
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;

  // #2 FluidMorph：推理强度胶囊 → 展开内联面板
  bool _reasoningOpen = false;

  // 推理强度（off/low/medium/high，对齐 chat.reasoning）
  String _reasoning = 'medium';

  // 附件（图片/文件，气泡内渲染）
  List<_Attachment> _pendingAtts = [];
  bool _generatingImage = false;

  static const _suggestions = [
    '帮我写一封请假邮件',
    '用通俗语言解释量子纠缠',
    '制定一周健身计划',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
    _inputCtl.addListener(() => setState(() {}));
  }

  Future<void> _restore() async {
    final local = AmoreStore.loadHistory('single');
    if (!mounted) return;
    setState(() => _messages = local);
    _scrollBottom();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtl.hasClients) {
        _scrollCtl.animateTo(_scrollCtl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut);
      }
    });
    // 转场动画期间 maxScrollExtent 是中间态，转场完成后再校正到最新
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted && _scrollCtl.hasClients) {
        _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
      }
    });
  }

  String get _greetTitle {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 11) return '早上好';
    if (h >= 11 && h < 13) return '中午好';
    if (h >= 13 && h < 18) return '下午好';
    return '晚上好';
  }

  // MARK: 发送（对齐 send()：本地历史 + 直连模型 + 附件说明拼接）

  Future<void> _send() async {
    final text = _inputCtl.text.trim();
    if ((text.isEmpty && _pendingAtts.isEmpty) || _sending) return;
    HapticFeedback.selectionClick();
    _inputCtl.clear();
    _focus.unfocus();
    final atts = _pendingAtts;
    // 附件消息：content 前缀 [atts] 块（历史/渲染共用；Rust 零改动）
    final attMaps = atts
        .map((a) => {'name': a.name, 'path': a.path, 'kind': a.kind})
        .toList();
    final content = Attachments.encode(attMaps, text);
    setState(() {
      _pendingAtts = [];
      _messages.add(ChatMessage(content: content));
      _sending = true;
    });
    _scrollBottom();

    try {
      final provider = ChatEngine.providerForGlobal();
      if (provider == null) {
        throw Exception('AI 未配置 · 点击前往「我的」页设置');
      }
      final history = _messages
          .take(_messages.length - 1)
          .toList()
          .reversed
          .take(19)
          .toList()
          .reversed
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
      var last = text;
      if (atts.isNotEmpty) {
        last += '\n（我另外发了 ${atts.length} 个附件：${atts.map((a) => a.name).join('、')}）';
      }
      history.add({'role': 'user', 'content': last});
      final skillParts = SkillCatalog.enabledPacks()
          .where((x) => x.category != 'workflow' && x.prompt.isNotEmpty)
          .map((x) => x.prompt)
          .toList();
      final system = [
        AmoreStore.getConfig('persona.prompt') ?? '',
        ...skillParts,
      ].join('\n\n');
      final reply = await ChatEngine.request(
          provider, history.cast<Map<String, String>>().toList(), system,
          extraSystem: _reasoning != 'off'
              ? '回复推理强度：${_reasoningLabel(_reasoning)}。'
              : null);
      setState(() =>
          _messages.add(ChatMessage(content: reply, role: 'assistant')));
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() =>
          _messages.add(ChatMessage(content: '⚠️ $msg', role: 'assistant')));
    }
    AmoreStore.appendHistory('single', 'user', content);
    for (final m in _messages.skip(_messages.length - 2)) {
      AmoreStore.appendHistory('single', m.role, m.content);
    }
    setState(() => _sending = false);
    _scrollBottom();
  }

  String _reasoningLabel(String r) => switch (r) {
        'off' => '关闭',
        'low' => '低',
        'high' => '高',
        _ => '中',
      };

  // MARK: 朗读（本地引擎对应 flutter_tts）

  Future<void> _readAloud() async {
    if (_speaking) {
      await _tts.stop();
      setState(() => _speaking = false);
      return;
    }
    final last = _messages.lastWhere((m) => m.role == 'assistant',
        orElse: () => ChatMessage(content: ''));
    if (last.content.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂无可朗读的回复')));
      return;
    }
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5);
    await _tts.speak(
        last.content.substring(0, last.content.length.clamp(0, 600)));
    setState(() => _speaking = true);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
  }

  Future<void> _newChat() async {
    AmoreStore.clearHistory('single');
    setState(() => _messages = []);
  }

  // MARK: 菜单

  void _menu() {
    BounceSheet.show(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('新对话'),
              onTap: () {
                Navigator.pop(context);
                _newChat();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('历史会话'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ConversationsPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_rounded,
                  color: AmoreBrand.orange),
              title: const Text('工作流对话'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WorkflowPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('工作流历史'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const WorkflowHistoryPage()));
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(_speaking
                  ? Icons.stop_rounded
                  : Icons.volume_up_rounded),
              title: Text(_speaking ? '停止朗读' : '朗读回复'),
              onTap: () {
                Navigator.pop(context);
                _readAloud();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading:
                  const Icon(Icons.delete_rounded, color: Color(0xFFFF3B30)),
              title: const Text('清空对话',
                  style: TextStyle(color: Color(0xFFFF3B30))),
              onTap: () {
                Navigator.pop(context);
                _newChat();
              },
            ),
          ],
      ),
    );
  }

  // MARK: UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AmoreAppBar(
        title: 'AI 对话',
        actions: [
          GlassIconButton(
              icon: Icons.question_answer_rounded,
              iconColor: AmoreBrand.brandBlue,
              onTap: _menu),
          const SizedBox(width: 8),
        ],
      ),
      body: ChatBackground(
        bgKey: context.select<AppState, String>((s) => s.chatBgKey),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  controller: _scrollCtl,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  // 懒构建：仅渲染可见行，长会话滚动不掉帧（视觉等价）
                  itemCount: 1 +
                      (_messages.isEmpty ? 1 : 0) +
                      _messages.length +
                      (_sending ? 1 : 0) +
                      1,
                  itemBuilder: (_, i) {
                    if (i == 0) return _headerCard();
                    var k = i - 1;
                    if (_messages.isEmpty) {
                      if (k == 0) return _emptyState();
                      k--;
                      if (_sending) {
                        if (k == 0) return _typingRow();
                        k--;
                      }
                      return k == 0 ? const SizedBox(height: 80) : const SizedBox.shrink();
                    }
                    if (k < _messages.length) return _bubble(_messages[k]);
                    k -= _messages.length;
                    if (_sending) {
                      if (k == 0) return _typingRow();
                      k--;
                    }
                    return k == 0 ? const SizedBox(height: 80) : const SizedBox.shrink();
                  },
                ),
              ),
              _inputArea(),
            ],
          ),
        ),
      ),
    );
  }

  // 发送中的打字指示行（列表懒构建抽出的 helper）
  Widget _typingRow() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, top: 8),
        child: _typingIndicator(),
      ),
    );
  }

  // 顶部：问候 + HeroBanner + 摘要/模型（对齐 headerCard）

  Widget _headerCard() {
    final state = context.watch<AppState>();
    final providers = state.providers;
    final configured = providers.isNotEmpty;
    final model = configured
        ? (state.providers
                .where((p) => p.id == AmoreStore.activeProviderId())
                .firstOrNull ??
            providers.first)
        : null;
    final firstUser = _messages.firstWhere((m) => m.role == 'user',
        orElse: () => ChatMessage(content: ''));

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$_greetTitle，${state.config['username'] ?? '朋友'}',
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1D1D1F))),
          const Text('开启你的精彩对话',
              style: TextStyle(fontSize: 13, color: Color(0xFF86868B))),
          const SizedBox(height: 12),
          TiltReflectCard(
            onTap: configured ? _newChat : null,
            radius: const BorderRadius.all(Radius.circular(20)),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AmoreTheme.brandBox(),
              child: Row(
                children: [
                  Icon(configured ? Icons.add : Icons.chevron_right,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_messages.isEmpty ? '开始全新对话' : '继续当前对话',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        Text(
                            configured
                                ? '模型 · ${model!.model.isEmpty ? model.label : model.model}'
                                : 'AI 未配置 · 点击前往「我的」页设置',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withOpacity(0.35), width: 0.8),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (firstUser.content.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.format_quote_rounded,
                          size: 14, color: Color(0xFF86868B)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            firstUser.content.isEmpty
                                ? '[附件消息]'
                                : firstUser.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, color: Color(0xFF86868B))),
                      ),
                    ],
                  )
                else
                  const Row(children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 13, color: Color(0xFFAEAEB2)),
                    SizedBox(width: 6),
                    Text('发送第一条消息开始',
                        style: TextStyle(
                            fontSize: 12.5, color: Color(0xFFAEAEB2))),
                  ]),
                const Divider(height: 18),
                Row(
                  children: [
                    Icon(Icons.memory_rounded,
                        size: 14,
                        color:
                            configured ? AmoreBrand.orange : AmoreBrand.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          configured
                              ? '模型：${model!.model.isEmpty ? model.label : model.model}'
                              : 'AI 模型未添加',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFF1D1D1F))),
                    ),
                    Text(configured ? '已配置' : '去添加 ›',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: configured
                                ? const Color(0xFF34C759)
                                : AmoreBrand.orange)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 空状态 + 建议（对齐 emptyState）

  Widget _emptyState() {
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AmoreBrand.orangeBg,
            border: Border.all(
                color: AmoreBrand.orange.withOpacity(0.4), width: 1),
          ),
          child: const Icon(Icons.question_answer_rounded,
              size: 32, color: AmoreBrand.brandBlue),
        ),
        const SizedBox(height: 14),
        const Text('开始新对话',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('发送消息、图片或文件，AI 为你解答',
            style: TextStyle(fontSize: 12, color: Color(0xFFAEAEB2))),
        const SizedBox(height: 14),
        for (final s in _suggestions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
            child: GestureDetector(
              onTap: () {
                _inputCtl.text = s;
                _focus.requestFocus();
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: AmoreTheme.cardBox(radius: 16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: AmoreBrand.orangeBg,
                          borderRadius: BorderRadius.circular(11)),
                      child: const Icon(Icons.auto_fix_high_rounded,
                          size: 18, color: AmoreBrand.orange),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(s,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1D1D1F)))),
                    const Icon(Icons.chevron_right_rounded,
                        size: 15, color: Color(0xFFAEAEB2)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // 消息气泡（不对称圆角，对齐 MessageBubble）

  Widget _bubble(ChatMessage m) {
    final isUser = m.role == 'user';
    final r =
        context.select<AppState, double>((s) => s.bubbleRadius.clamp(8.0, 24.0));
    final fs =
        context.select<AppState, double>((s) => s.chatFontScale.clamp(13.0, 20.0));
    final tail = r * 0.3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AmoreBrand.brandBlue : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isUser ? r : tail),
                  bottomLeft: Radius.circular(isUser ? r : r),
                  bottomRight: Radius.circular(isUser ? r : r),
                  topRight: Radius.circular(isUser ? tail : r),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: const Color(0xFFE3E3E8).withOpacity(0.5),
                        width: 0.6),
                boxShadow: [
                  BoxShadow(
                      color:
                          Colors.black.withOpacity(isUser ? 0.12 : 0.05),
                      blurRadius: 7,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: _bubbleContent(m, isUser, fs, r),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingIndicator() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16)),
      child: const Text('•  •  •',
          style: TextStyle(fontSize: 14, color: Color(0xFF86868B))),
    );
  }

  // 状态行 + 输入面板（对齐 statusRow / inputPanel）

  Widget _inputArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _attachPreview(),
        ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.62),
            border: const Border(top: BorderSide(color: Color(0xFFE3E3E8))),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, -4)),
            ],
          ),
          child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              children: [
                FluidMorph(
                  expanded_: _reasoningOpen,
                  onCollapsedTap: () =>
                      setState(() => _reasoningOpen = true),
                  onExpandedTap: () =>
                      setState(() => _reasoningOpen = false),
                  collapsed: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: AmoreBrand.orange.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      children: [
                        const Icon(Icons.psychology_alt_rounded,
                            size: 12, color: Color(0xFF86868B)),
                        const SizedBox(width: 4),
                        Text('推理 · ${_reasoningLabel(_reasoning)}',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF86868B))),
                      ],
                    ),
                  ),
                  expanded: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                        color: AmoreBrand.orange.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final r in const [
                          ('off', '关闭'),
                          ('low', '低'),
                          ('medium', '中'),
                          ('high', '高'),
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _reasoning = r.$1;
                                _reasoningOpen = false;
                              }),
                              child: Text(
                                r.$2,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: _reasoning == r.$1
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: _reasoning == r.$1
                                      ? AmoreBrand.accent
                                      : const Color(0xFF86868B),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.72),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                    color: Colors.white.withOpacity(0.5), width: 0.8),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _generatingImage ? null : _attachMenu,
                    child: _generatingImage
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.2))
                        : const Icon(Icons.add_circle_outline_rounded,
                            size: 24, color: Color(0xFF86868B)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _inputCtl,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: const TextStyle(fontSize: 14),
                      decoration:
                          const InputDecoration.collapsed(hintText: '输入消息...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      size: 22,
                      color: (_inputCtl.text.trim().isEmpty &&
                                  _pendingAtts.isEmpty) ||
                              _sending
                          ? const Color(0xFFD1D1D6)
                          : AmoreBrand.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        ),
      ),
      ),
      ),
      ],
    );
  }

  Future<void> _pickReasoning() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in const [
              ('off', '关闭'),
              ('low', '低'),
              ('medium', '中'),
              ('high', '高'),
            ])
              ListTile(
                title: Text(r.$2),
                trailing:
                    _reasoning == r.$1 ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(ctx, r.$1),
              ),
          ],
        ),
      ),
    );
    if (v != null) setState(() => _reasoning = v);
  }

  // AI 生成图片（OpenAI /images/generations 兼容；存沙盒进附件预览）
  Future<void> _aiGenerateImage() async {
    final provider = ChatEngine.providerForImage();
    if (provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('未配置模型供应商：先到「我的 → 模型配置」添加配置')));
      return;
    }
    final ctl = TextEditingController();
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 生成图片'),
        content: TextField(
          controller: ctl,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '描述你想生成的画面（可英文更准）'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('生成')),
        ],
      ),
    );
    if (prompt == null || prompt.trim().isEmpty) return;
    setState(() => _generatingImage = true);
    try {
      final path = await ChatEngine.generateImage(provider, prompt.trim());
      if (!mounted) return;
      setState(() {
        _generatingImage = false;
        _pendingAtts = [
          ..._pendingAtts,
          _Attachment(name: 'AI 生成.png', path: path, kind: 'image'),
        ];
      });
      // 明确告知：图在输入框待发送区，由用户手动发送，不会自动发出
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('✓ 图片已生成，放在输入框上方待发送区，点发送发出（可点 ✕ 取消）')));
      _scrollBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _generatingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFFFF3B30).withOpacity(0.9),
          duration: const Duration(seconds: 6),
          content: Text(
              '图片生成失败：${e.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  // 气泡内容：附件卡片 + 文本（无附件时纯文本等价原实现）
  Widget _bubbleContent(ChatMessage m, bool isUser, double fs, double r) {
    final atts = m.attachments;
    if (atts.isEmpty) {
      final t = m.content;
      return (!isUser && m == _messages.last)
          ? InkRevealText(
              text: t,
              style: TextStyle(
                  fontSize: fs, height: 1.45, color: const Color(0xFF1D1D1F)))
          : SelectableText(t,
              style: TextStyle(
                  fontSize: fs,
                  height: 1.45,
                  color: isUser ? Colors.white : const Color(0xFF1D1D1F)));
    }
    final rest = m.textContent.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final a in atts) AttachmentCard(att: a, mine: isUser),
          ],
        ),
        if (rest.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SelectableText(rest,
                style: TextStyle(
                    fontSize: fs,
                    height: 1.45,
                    color: isUser ? Colors.white : const Color(0xFF1D1D1F))),
          ),
      ],
    );
  }

  // 输入面板上方的附件预览条（可删除）
  Widget _attachPreview() {
    if (_pendingAtts.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 0, 0),
            child: Text('待发送（${_pendingAtts.length}）',
                style: const TextStyle(
                    fontSize: 10.5,
                    color: AmoreTheme.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        SizedBox(
          height: 64,
          child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        itemCount: _pendingAtts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = _pendingAtts[i];
          return Stack(
            children: [
              if (a.kind == 'image' && a.path.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(a.path),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _previewFallback(a),
                  ),
                )
              else
                _previewFallback(a),
              Positioned(
                right: -4,
                top: -4,
                child: GestureDetector(
                  onTap: () => setState(() => _pendingAtts.removeAt(i)),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF3A3A3C),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
        ),
      ],
    );
  }

  Widget _previewFallback(_Attachment a) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        a.kind == 'video'
            ? Icons.play_circle_fill_rounded
            : a.kind == 'file'
                ? Icons.insert_drive_file_rounded
                : Icons.image_rounded,
        size: 24,
        color: const Color(0xFF86868B),
      ),
    );
  }

  Future<void> _attachMenu() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_rounded),
              title: const Text('添加文件'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('选择照片'),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_rounded),
              title: const Text('选择视频'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded,
                  color: AmoreBrand.accent),
              title: const Text('AI 生成图片'),
              subtitle: const Text('用「图片」类型配置画画'),
              onTap: () => Navigator.pop(ctx, 'aigen'),
            ),
          ],
        ),
      ),
    );
    if (v == null) return;
    if (v == 'aigen') {
      await _aiGenerateImage();
      return;
    }
    // 附件真实选取（image_picker / file_picker），复制进沙盒持久化
    if (v == 'photo') {
      final XFile? img =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (img != null) {
        final att = await Attachments.importFile(img.path, img.name, 'image');
        if (mounted) {
          setState(() => _pendingAtts = [
                ..._pendingAtts,
                _Attachment(
                    name: att['name'] ?? img.name,
                    path: att['path'] ?? '',
                    kind: 'image')
              ]);
        }
      }
    } else if (v == 'video') {
      final XFile? vid =
          await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (vid != null) {
        final att = await Attachments.importFile(vid.path, vid.name, 'video');
        if (mounted) {
          setState(() => _pendingAtts = [
                ..._pendingAtts,
                _Attachment(
                    name: att['name'] ?? vid.name,
                    path: att['path'] ?? '',
                    kind: 'video')
              ]);
        }
      }
    } else if (v == 'camera') {
      final XFile? img =
          await ImagePicker().pickImage(source: ImageSource.camera);
      if (img != null) {
        final att = await Attachments.importFile(img.path, img.name, 'image');
        if (mounted) {
          setState(() => _pendingAtts = [
                ..._pendingAtts,
                _Attachment(
                    name: att['name'] ?? img.name,
                    path: att['path'] ?? '',
                    kind: 'image')
              ]);
        }
      }
    } else {
      final res = await FilePicker.platform.pickFiles();
      if (res != null && res.files.single.name.isNotEmpty) {
        final f = res.files.single;
        final att = await Attachments.importFile(f.path ?? '', f.name, 'file');
        if (mounted) {
          setState(() => _pendingAtts = [
                ..._pendingAtts,
                _Attachment(
                    name: att['name'] ?? f.name,
                    path: att['path'] ?? '',
                    kind: 'file')
              ]);
        }
      }
    }
  }
}

class _Attachment {
  final String name;
  final String path; // 沙盒内路径（空=占位）
  final String kind; // image / video / file
  const _Attachment({required this.name, this.path = '', required this.kind});
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
