// Amore — 群游戏（塔罗占卜 / 狼人杀）移植自 SwiftUI build 89 GroupChat 游戏逻辑
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/chat_engine.dart';
import '../core/group_games.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'game_card.dart';

/// 群游戏运行器：把卡牌消息写进群聊历史，成员 AI 依次回应
class GroupGamesRunner {
  final String groupId;
  final String groupName;
  final List<ChatFriend> members; // 全体成员
  final List<ChatMessage> Function() loadMessages;
  final void Function(String role, String content, {String? senderId}) append;
  final void Function(String name) typing;

  GroupGamesRunner({
    required this.groupId,
    required this.groupName,
    required this.members,
    required this.loadMessages,
    required this.append,
    required this.typing,
  });

  String get _key => 'group.$groupId';

  // MARK: - 塔罗占卜

  /// 抽牌 + 随机成员 AI 解读；返回牌信息供 UI 展示
  Future<(TarotCard, bool)> sendTarot() async {
    final (card, upright) = TarotCard.draw();
    final orientation = upright ? '正位' : '逆位';
    final meaning = upright ? card.upright : card.reversed;
    final msg = CardMark.message('塔罗', card.name, '$orientation · $meaning',
        _symbolName(card.symbol), upright ? 'gold' : 'purple');

    append('user', msg);
    HapticFeedback.mediumImpact();

    final responder = _pickResponder();
    if (responder == null) return (card, upright);

    typing(responder.name);
    try {
      final history = loadMessages()
          .take(19)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
      final system = _tarotPrompt(responder, card, upright);
      final reply = await ChatEngine.request(
          ChatEngine.providerFor(responder) ??
              ChatEngine.providerForGlobalOrThrow(),
          history.cast<Map<String, String>>(),
          system);
      append('assistant', reply, senderId: responder.id);
    } catch (_) {
      // 静默（对齐 SwiftUI 版）
    }
    return (card, upright);
  }

  String _symbolName(IconData icon) => 'tarot_${icon.codePoint}';

  ChatFriend? _pickResponder() {
    if (members.isEmpty) return null;
    return members[Random().nextInt(members.length)];
  }

  String _tarotPrompt(ChatFriend r, TarotCard card, bool upright) {
    final orientation = upright ? '正位' : '逆位';
    final meaning = upright ? card.upright : card.reversed;
    final persona = r.persona.trim();
    final p = <String>[];
    if (persona.isNotEmpty) {
      p.add('【人设·最高优先级】你是 ${r.name}：\n$persona');
    } else {
      p.add('【身份】你是 ${r.name}，群聊里的一员。');
    }
    p.add('''
【塔罗解读】用户抽到了「${card.name}」（$orientation），牌义：$meaning。
用你自己的口吻解读这张牌（结合用户最近聊过的事），2-4 句，口语化，别端着，别用「亲爱的」这类客服腔。
先给一句结论，再说一句提醒。可以用一个 emoji。不要提牌阵、不要列条目、不要重复用户原话。
语音消息一律用中文。''');
    p.add(AmoreStore.toolsGuide());
    return p.join('\n\n');
  }

  // MARK: - 狼人杀（单轮体验）

  WerewolfGame? startWerewolf() {
    if (members.length < 2) return null;
    final pool = members.take(4).toList();
    final roles = <String, WerewolfRole>{};
    final shuffled = pool.toList()..shuffle();
    roles[shuffled.removeFirst().id] = WerewolfRole.wolf;
    if (pool.length >= 3) {
      roles[shuffled.first.id] = WerewolfRole.seer;
    }
    for (final m in pool) {
      roles.putIfAbsent(m.id, () => WerewolfRole.villager);
    }
    final game = WerewolfGame(
        players: pool.map((m) => WerewolfPlayer(m.name, m.id)).toList(),
        roles: roles);

    final playersText = pool.map((m) => m.name).join('、');
    append(
        'user',
        CardMark.message('角色', '狼人杀', '玩家：$playersText · 天黑请闭眼',
            'moon.stars.fill', 'purple'));
    HapticFeedback.mediumImpact();
    return game;
  }

  /// 天亮结算 → 成员发言 → 终局；逐步回调供 UI 展示
  Future<void> runWerewolf(WerewolfGame game) async {
    final wolves = game.roles.entries.where((e) => e.value == WerewolfRole.wolf).map((e) => e.key).toList();
    final victims = game.players.where((p) => !wolves.contains(p.memberId)).toList();
    final victim = victims.isNotEmpty
        ? victims[Random().nextInt(victims.length)]
        : game.players.first;
    game.victim = victim.name;
    game.phase = 1;

    append('assistant',
        CardMark.message('结算', '天亮了', '${game.victim} 昨夜被袭击', 'sunrise', 'red'),
        senderId: '');

    // 前 3 名成员白天发言
    final speakers = members.take(3);
    for (final m in speakers) {
      final role = game.roles[m.id];
      if (role == null) continue;
      typing(m.name);
      try {
        final system = _werewolfPrompt(m, role, game);
        final history = loadMessages()
            .take(19)
            .map((msg) => {'role': msg.role, 'content': msg.content})
            .toList();
        history.add({
          'role': 'user',
          'content': '（白天讨论）昨晚 ${game.victim} 出局了，来说说你的看法。'
        });
        final reply = await ChatEngine.request(
            ChatEngine.providerFor(m) ?? ChatEngine.providerForGlobalOrThrow(),
            history.cast<Map<String, String>>(),
            system);
        append('assistant', reply, senderId: m.id);
      } catch (_) {
        // 单成员失败不中断
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }

    // 结算
    final wolfCount = game.roles.values.where((r) => r == WerewolfRole.wolf).length;
    final others = game.players.length - wolfCount;
    game.winner = wolfCount >= others ? '狼人胜利' : '好人阵营胜利';
    game.phase = 3;
    final rolesText = game.players
        .map((p) => '${p.name}：${game.roles[p.memberId]?.title ?? '村民'}')
        .join(' / ');
    append('assistant',
        CardMark.message('结算', game.winner, rolesText, 'flag', 'gold'),
        senderId: '');
  }

  String _werewolfPrompt(ChatFriend m, WerewolfRole role, WerewolfGame game) {
    final persona = m.persona.trim();
    final p = <String>[];
    if (persona.isNotEmpty) {
      p.add('【人设·最高优先级】你是 ${m.name}：\n$persona');
    } else {
      p.add('【身份】你是 ${m.name}。');
    }
    final others =
        game.players.where((x) => x.memberId != m.id).map((x) => x.name).join('、');
    p.add('''
【狼人杀·白天发言】你的隐藏身份是「${role.title}」——${role.blurb}。
场上玩家：$others；昨晚 ${game.victim} 出局。
${role == WerewolfRole.wolf ? '你是狼人：要伪装成好人，带节奏把嫌疑推给别人，绝不能承认身份。' : '你是好人：基于现有信息分析，可以怀疑别人，但别报假身份。'}
要求：只以自己的身份发言，1-2 句，口语化，像群聊插话（不超过 30 字）。
不要写「作为预言家」这类格式，不要报自己的真实身份标签（除非你是预言家且决定跳身份）。
语音一律中文。''');
    return p.join('\n\n');
  }
}

AIProvider providerForGlobalOrThrow() {
  final p = ChatEngine.providerForGlobal();
  if (p == null) {
    throw Exception('尚未配置 AI 模型：请到「我的 → 模型配置」添加并激活一个供应商。');
  }
  return p;
}
