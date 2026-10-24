// 对应 Swift：LocalConsoleView.swift —— 本地终端（沙盒数据命令台，Dart 层解释）
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/code_engine.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';

class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  final _inputCtl = TextEditingController();
  final _scrollCtl = ScrollController();
  final List<_Line> _lines = [
    _Line('Amore Console v4.0 — 本机沙盒命令台（输入 help 查看命令）', kind: _LineKind.info),
  ];
  final Stopwatch _uptime = Stopwatch()..start();

  @override
  void dispose() {
    _inputCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  void _append(String text, {_LineKind kind = _LineKind.normal}) {
    setState(() => _lines.add(_Line(text, kind: kind)));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtl.hasClients) {
        _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
      }
    });
  }

  void _exec(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return;
    _append('\$ $input', kind: _LineKind.prompt);

    final parts = input.split(RegExp(r'\s+'));
    final cmd = parts[0];
    final args = parts.sublist(1);

    switch (cmd) {
      case 'help':
        _append('''命令列表：
  help                      本帮助
  info                      设备与 App 信息
  date                      当前时间
  whoami                    当前用户
  uptime                    App 已运行时长
  ls friends|groups|models|history   列出数据
  cat friend N              第 N 个好友完整档案
  cat config                全部配置
  clear chat all|名字        清空聊天记录
  wipe memory 名字           清空某好友的长期记忆
  reset models              重置模型配置
  export                    导出 JSON 到剪贴板
  eval <表达式>              数学计算：eval 12*(3+4)^2
  code <op> <内容>           本地代码：base64/url/json/regex/stats''');
      case 'info':
        final friends = AmoreStore.listFriends();
        final groups = AmoreStore.listGroups();
        final providers = AmoreStore.listProviders();
        _append('设备：iPhone · iOS 15+\n'
            'App：Amore 4.0 Flutter+Rust\n'
            '好友 ${friends.length} 位 · 群 ${groups.length} 个 · 模型配置 ${providers.length} 个');
      case 'date':
        _append(DateTime.now().toString());
      case 'whoami':
        _append('quantokx@amore');
      case 'uptime':
        final s = _uptime.elapsed;
        _append('${s.inMinutes}m ${s.inSeconds % 60}s');
      case 'ls':
        switch (args.firstOrNull) {
          case 'friends':
            final friends = AmoreStore.listFriends();
            if (friends.isEmpty) {
              _append('(空)', kind: _LineKind.info);
            } else {
              for (final (i, f) in friends.indexed) {
                _append('[$i] ${f.name}｜${f.genderText}${f.age.isEmpty ? "" : " ${f.age}岁"}'
                    '｜persona ${f.persona.length}字｜memory ${f.memory.length}条');
              }
            }
          case 'groups':
            final groups = AmoreStore.listGroups();
            for (final (i, g) in groups.indexed) {
              _append('[$i] ${g.name}｜${g.memberIds.length} 位成员');
            }
          case 'models':
            final ps = AmoreStore.listProviders();
            for (final (i, p) in ps.indexed) {
              _append('[$i] ${p.label}｜${p.vendor}｜${p.model}｜${p.maskedKey()}');
            }
          case 'history':
            var any = false;
            for (final f in AmoreStore.listFriends()) {
              final n = AmoreStore.countHistory('friend.${f.id}');
              if (n > 0) {
                any = true;
                _append('好友·${f.name}：$n 条');
              }
            }
            for (final g in AmoreStore.listGroups()) {
              final n = AmoreStore.countHistory('group.${g.id}');
              if (n > 0) {
                any = true;
                _append('群·${g.name}：$n 条');
              }
            }
            if (!any) _append('(无聊天记录)', kind: _LineKind.info);
          default:
            _append("ls: 用法 ls friends|groups|models|history", kind: _LineKind.error);
        }
      case 'cat':
        switch (args.firstOrNull) {
          case 'friend':
            final idx = int.tryParse(args.elementAtOrNull(1) ?? '');
            final friends = AmoreStore.listFriends();
            if (idx == null || idx < 0 || idx >= friends.length) {
              _append('cat friend: 索引无效（0-${friends.length - 1}）', kind: _LineKind.error);
            } else {
              final f = friends[idx];
              _append(f.toJson().toString());
            }
          case 'config':
            _append(AmoreStore.allConfig().toString());
          default:
            _append('cat: 用法 cat friend N | cat config', kind: _LineKind.error);
        }
      case 'clear':
        if (args.firstOrNull == 'chat') {
          final target = args.elementAtOrNull(1) ?? 'all';
          var n = 0;
          if (target == 'all') {
            for (final f in AmoreStore.listFriends()) {
              n += AmoreStore.clearHistory('friend.${f.id}');
            }
            for (final g in AmoreStore.listGroups()) {
              n += AmoreStore.clearHistory('group.${g.id}');
            }
          } else {
            final friends = AmoreStore.listFriends().where((f) => f.name == target).toList();
            if (friends.isNotEmpty) {
              n = AmoreStore.clearHistory('friend.${friends.first.id}');
            } else {
              _append('clear: 找不到好友「$target」', kind: _LineKind.error);
              return;
            }
          }
          _append('已清空 $n 条消息', kind: _LineKind.info);
        } else {
          _append('clear: 用法 clear chat all|名字', kind: _LineKind.error);
        }
      case 'wipe':
        if (args.firstOrNull == 'memory') {
          final target = args.elementAtOrNull(1) ?? '';
          final friends = AmoreStore.listFriends().where((f) => f.name == target).toList();
          if (friends.isEmpty) {
            _append('wipe memory: 找不到好友「$target」', kind: _LineKind.error);
          } else {
            final n = friends.first.memory.length;
            friends.first.memory = [];
            AmoreStore.saveFriend(friends.first);
            _append('已清空「$target」的 $n 条记忆', kind: _LineKind.info);
          }
        } else {
          _append('wipe: 用法 wipe memory 名字', kind: _LineKind.error);
        }
      case 'reset':
        if (args.firstOrNull == 'models') {
          for (final p in AmoreStore.listProviders()) {
            AmoreStore.deleteProvider(p.id);
          }
          AmoreStore.setActiveProvider('');
          _append('模型配置已重置', kind: _LineKind.info);
        } else {
          _append('reset: 用法 reset models', kind: _LineKind.error);
        }
      case 'export':
        final json = {
          'friends': AmoreStore.listFriends().map((f) => f.toJson()).toList(),
          'groups': AmoreStore.listGroups().map((g) => g.toJson()).toList(),
          'providers': AmoreStore.listProviders().map((p) => p.toJson()).toList(),
          'config': AmoreStore.allConfig(),
        };
        Clipboard.setData(ClipboardData(text: json.toString()));
        _append('JSON 已复制到剪贴板（${json.toString().length} 字符）', kind: _LineKind.info);
      case 'eval':
        final expr = raw.substring(4).trim();
        if (expr.isEmpty) {
          _append('用法：eval <表达式>，如 eval 12*(3+4)^2', kind: _LineKind.error);
        } else {
          _append('$expr = ${CodeEngine.evalFriendly(expr)}', kind: _LineKind.info);
        }
      case 'code':
        final rest = raw.substring(4).trim();
        final sp = rest.indexOf(' ');
        final op = sp < 0 ? rest : rest.substring(0, sp);
        final input = sp < 0 ? '' : rest.substring(sp + 1).trim();
        if (input.isEmpty) {
          _append('用法：code <op> <内容>，op ∈ eval/base64/url/json/regex/stats', kind: _LineKind.error);
        } else {
          try {
            _append(CodeEngine.run(op, input), kind: _LineKind.info);
          } catch (e) {
            _append(e.toString().replaceFirst('Exception: ', ''), kind: _LineKind.error);
          }
        }
      default:
        _append('command not found: $cmd（输入 help 查看可用命令）', kind: _LineKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地终端', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
      body: Container(
        color: const Color(0xFF1D1D1F),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _lines.length,
                  itemBuilder: (_, i) {
                    final l = _lines[i];
                    final color = switch (l.kind) {
                      _LineKind.info => const Color(0xFF7FB98A),
                      _LineKind.prompt => const Color(0xFFB8E986),
                      _LineKind.error => const Color(0xFFFF3B30),
                      _LineKind.normal => const Color(0xFF34C759),
                    };
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: SelectableText(
                        l.text,
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.45,
                            color: color),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: const BoxDecoration(
                  color: const Color(0xFFF2F2F7),
                  border: Border(top: BorderSide(color: Color(0xFF1E3325))),
                ),
                child: Row(
                  children: [
                    const Text('❯ ',
                        style: TextStyle(color: const Color(0xFF34C759), fontSize: 15, fontWeight: FontWeight.w700)),
                    Expanded(
                      child: TextField(
                        controller: _inputCtl,
                        onSubmitted: _exec,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13, color: Color(0xFFB8E986)),
                        cursorColor: const Color(0xFF34C759),
                        decoration: const InputDecoration.collapsed(
                            hintText: '输入命令…',
                            hintStyle: TextStyle(color: const Color(0xFF86868B))),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded, color: Color(0xFF34C759), size: 18),
                      onPressed: () => _exec(_inputCtl.text),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line {
  final String text;
  final _LineKind kind;
  _Line(this.text, {this.kind = _LineKind.normal});
}

enum _LineKind { normal, info, prompt, error }

extension _ListX<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? elementAtOrNull(int i) => i < length ? this[i] : null;
}
