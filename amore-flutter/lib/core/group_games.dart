// Amore — 群游戏数据与逻辑（移植自 SwiftUI GroupGames.swift：塔罗 22 大阿卡纳 + 狼人杀单轮体验）
import 'dart:math';

import 'package:flutter/material.dart';

// MARK: - 塔罗牌（22 张大阿卡纳）

class TarotCard {
  final int id;
  final String name;
  final IconData symbol;
  final String upright;
  final String reversed;

  const TarotCard(this.id, this.name, this.symbol, this.upright, this.reversed);

  static const deck = <TarotCard>[
    TarotCard(0, '愚者', Icons.hiking_rounded, '新的开始、自由、冒险', '鲁莽、逃避、错失机会'),
    TarotCard(1, '魔术师', Icons.auto_fix_high_rounded, '创造力、行动力、掌控', '操控、拖延、自信不足'),
    TarotCard(2, '女祭司', Icons.nightlight_round, '直觉、神秘、内在智慧', '忽视直觉、隐瞒、表层化'),
    TarotCard(3, '皇后', Icons.local_florist_rounded, '丰盛、滋养、爱与美', '过度依赖、自我忽略、停滞'),
    TarotCard(4, '皇帝', Icons.workspace_premium_rounded, '权威、秩序、稳固', '固执、控制欲、僵化'),
    TarotCard(5, '教皇', Icons.menu_book_rounded, '传统、指导、信念', '教条、叛逆、被束缚'),
    TarotCard(6, '恋人', Icons.favorite_rounded, '结合、选择、真心', '犹豫、错配、诱惑'),
    TarotCard(7, '战车', Icons.directions_car_rounded, '前进、意志、胜利', '失控、方向混乱、蛮干'),
    TarotCard(8, '力量', Icons.local_fire_department_rounded, '勇气、耐心、温柔的力量', '自我怀疑、急躁、软弱'),
    TarotCard(9, '隐者', Icons.lightbulb_rounded, '内省、独处、寻找答案', '孤立、逃避、迷失'),
    TarotCard(10, '命运之轮', Icons.casino_rounded, '转机、循环、机缘', '低谷、拖延、逆势'),
    TarotCard(11, '正义', Icons.balance_rounded, '公平、因果、决断', '偏颇、推诿、失衡'),
    TarotCard(12, '倒吊人', Icons.arrow_downward_rounded, '暂停、换位思考、牺牲', '无谓牺牲、拖延、固执'),
    TarotCard(13, '死神', Icons.dark_mode_rounded, '结束、蜕变、新生', '抗拒改变、纠缠、停滞'),
    TarotCard(14, '节制', Icons.water_drop_rounded, '平衡、调和、耐心', '失衡、过度、急躁'),
    TarotCard(15, '恶魔', Icons.bolt_rounded, '欲望、束缚、执念', '挣脱、觉醒、放下'),
    TarotCard(16, '高塔', Icons.home_work_rounded, '突变、崩塌、真相', '缓冲、勉强维持、迟到的变化'),
    TarotCard(17, '星星', Icons.star_rounded, '希望、疗愈、灵感', '失望、迷茫、信心不足'),
    TarotCard(18, '月亮', Icons.cloud_rounded, '潜意识、不安、幻象', '真相浮现、焦虑消退'),
    TarotCard(19, '太阳', Icons.wb_sunny_rounded, '成功、喜悦、生命力', '短暂低落、过度乐观'),
    TarotCard(20, '审判', Icons.notifications_active_rounded, '觉醒、召唤、重生', '犹豫、后悔、逃避责任'),
    TarotCard(21, '世界', Icons.public_rounded, '圆满、完成、旅程终点', '未竟、差一步、循环未结'),
  ];

  /// 随机抽一张（返回牌 + 是否正位）
  static (TarotCard, bool) draw() {
    final c = deck[Random().nextInt(deck.length)];
    return (c, Random().nextBool());
  }
}

// MARK: - 狼人杀角色

enum WerewolfRole {
  villager('村民'),
  wolf('狼人'),
  seer('预言家'),
  witch('女巫');

  final String title;
  const WerewolfRole(this.title);

  IconData get symbol => switch (this) {
        WerewolfRole.villager => Icons.person_rounded,
        WerewolfRole.wolf => Icons.pets_rounded,
        WerewolfRole.seer => Icons.visibility_rounded,
        WerewolfRole.witch => Icons.auto_awesome_rounded,
      };

  Color get tint => switch (this) {
        WerewolfRole.villager => const Color(0xFF34C759),
        WerewolfRole.wolf => const Color(0xFFFF3B30),
        WerewolfRole.seer => const Color(0xFF3478F6),
        WerewolfRole.witch => const Color(0xFFFF9500),
      };

  String get blurb => switch (this) {
        WerewolfRole.villager => '没有特殊能力，靠推理找出狼人',
        WerewolfRole.wolf => '夜里可以袭击一名玩家，白天伪装成好人',
        WerewolfRole.seer => '每晚可以查验一名玩家的身份',
        WerewolfRole.witch => '有一瓶解药和一瓶毒药',
      };
}

// MARK: - 卡牌消息标记（群聊与单聊共用文本协议）

class CardMark {
  final String kind; // 塔罗 / 角色 / 结算
  final String title;
  final String sub;
  final String symbol; // 语义符号名（渲染时映射图标）
  final String tone; // red/gold/blue/purple

  const CardMark({
    required this.kind,
    required this.title,
    required this.sub,
    required this.symbol,
    required this.tone,
  });

  /// 解析 `[卡牌]kind|title|sub|symbol|tone`
  static CardMark? parse(String text) {
    if (!text.startsWith('[卡牌]')) return null;
    final parts = text.substring(4).split('|');
    if (parts.length < 5) return null;
    return CardMark(
        kind: parts[0],
        title: parts[1],
        sub: parts[2],
        symbol: parts[3],
        tone: parts[4]);
  }

  Color get color => switch (tone) {
        'red' => const Color(0xFFFF3B30),
        'green' => const Color(0xFF34C759),
        'gold' => const Color(0xFFC79A2E),
        'blue' => const Color(0xFF3478F6),
        _ => const Color(0xFF5C458C),
      };

  /// 语义符号名 → 图标（跨端文本协议，避免依赖 SF Symbol 名）
  static IconData symbolIcon(String name) => switch (name) {
        'figure.walk' || 'hiking' => Icons.hiking_rounded,
        'wand.and.stars' || 'sparkles' => Icons.auto_fix_high_rounded,
        'moon.stars.fill' || 'moon' => Icons.nightlight_round,
        'leaf.fill' || 'leaf' => Icons.local_florist_rounded,
        'crown.fill' || 'crown' => Icons.workspace_premium_rounded,
        'book.closed.fill' || 'book' => Icons.menu_book_rounded,
        'heart.fill' || 'heart' => Icons.favorite_rounded,
        'car.fill' || 'car' => Icons.directions_car_rounded,
        'flame.fill' || 'flame' => Icons.local_fire_department_rounded,
        'lightbulb.fill' || 'bulb' => Icons.lightbulb_rounded,
        'circle.grid.cross.fill' || 'dice' => Icons.casino_rounded,
        'scalemass.fill' || 'scale' => Icons.balance_rounded,
        'arrow.down.circle.fill' => Icons.arrow_downward_rounded,
        'sunrise.fill' || 'sunrise' => Icons.wb_twilight_rounded,
        'drop.fill' || 'drop' => Icons.water_drop_rounded,
        'bolt.heart.fill' || 'bolt' => Icons.bolt_rounded,
        'house.fill' || 'tower' => Icons.home_work_rounded,
        'star.fill' || 'star' => Icons.star_rounded,
        'cloud.moon.fill' || 'cloud' => Icons.cloud_rounded,
        'sun.max.fill' || 'sun' => Icons.wb_sunny_rounded,
        'bell.fill' || 'bell' => Icons.notifications_active_rounded,
        'globe.asia.australia.fill' || 'globe' => Icons.public_rounded,
        'person.fill' || 'person' => Icons.person_rounded,
        'pawprint.fill' || 'paw' => Icons.pets_rounded,
        'eye.fill' || 'eye' => Icons.visibility_rounded,
        'flag.checkered' || 'flag' => Icons.flag_rounded,
        _ => Icons.auto_awesome_rounded,
      };

  static String message(
          String kind, String title, String sub, String symbol, String tone) =>
      '[卡牌]$kind|$title|$sub|$symbol|$tone';
}

// MARK: - 狼人杀一局状态（单轮体验版）

class WerewolfPlayer {
  final String name;
  final String memberId;
  const WerewolfPlayer(this.name, this.memberId);
}

class WerewolfGame {
  final List<WerewolfPlayer> players;
  final Map<String, WerewolfRole> roles; // memberId → 角色
  String victim;
  int phase; // 0=已分配 1=天亮 2=发言完 3=结算
  String winner;

  WerewolfGame({
    required this.players,
    required this.roles,
    this.victim = '',
    this.phase = 0,
    this.winner = '',
  });
}
