// 技能中心数据层：Skill 技能 / Plugin 插件 / Workflow 工作包
// 配置存 Rust config（skills.packs / skills.enabled / skills.mcp）
import 'dart:convert';

import 'store.dart';

class SkillPack {
  String id;
  String name;
  String desc;
  String category; // skill / plugin / workflow
  String prompt; // 注入系统提示词的指令文本
  String toolHint; // 工具使用说明（可选，追加到工具指南）
  List<String> steps; // 工作包步骤模板
  bool builtin;

  SkillPack({
    this.id = '',
    this.name = '',
    this.desc = '',
    this.category = 'skill',
    this.prompt = '',
    this.toolHint = '',
    List<String>? steps,
    this.builtin = false,
  }) : steps = steps ?? const [];

  factory SkillPack.fromJson(Map<String, dynamic> j) => SkillPack(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        desc: j['desc']?.toString() ?? '',
        category: j['category']?.toString() ?? 'skill',
        prompt: j['prompt']?.toString() ?? '',
        toolHint: j['tool_hint']?.toString() ?? '',
        steps: (j['steps'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        builtin: j['builtin'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'desc': desc,
        'category': category,
        'prompt': prompt,
        'tool_hint': toolHint,
        'steps': steps,
        'builtin': builtin,
      };
}

/// 内置技能/插件/工作包目录
class SkillCatalog {
  static final List<SkillPack> builtins = [
    // ---- Skill 技能（对话注入）----
    SkillPack(
      id: 'skill_writer',
      name: '写作助手',
      desc: '润色、改写、扩写中文文案，保持语气自然',
      category: 'skill',
      builtin: true,
      prompt:
          '【写作助手技能】当用户要求写作/润色/改写时：先确认文体与语气，输出结构清晰；中文优先，避免翻译腔；提供 2 个可选版本（正式/口语）。',
    ),
    SkillPack(
      id: 'skill_coder',
      name: '编程助手',
      desc: '写代码、解释代码、查错误',
      category: 'skill',
      builtin: true,
      prompt:
          '【编程助手技能】需要代码时给出可直接运行的代码块（标注语言）并附简短说明；先分析需求再动手；可调用 calc 工具验证数值逻辑。',
    ),
    SkillPack(
      id: 'skill_translator',
      name: '翻译专家',
      desc: '中英互译，保留语境与语气',
      category: 'skill',
      builtin: true,
      prompt:
          '【翻译专家技能】用户要求翻译时：输出「原文 → 译文 → 备注（如有歧义）」三段；保持专有名词与语气一致；中译英用自然英语，英译中用流畅中文。',
    ),
    SkillPack(
      id: 'skill_summarizer',
      name: '总结提炼',
      desc: '长文摘要、要点提取、会议纪要',
      category: 'skill',
      builtin: true,
      prompt:
          '【总结提炼技能】总结时输出：核心结论（1-2 句）→ 要点列表（≤5 条）→ 行动项（如有）；忠实原文，不添油加醋。',
    ),
    // ---- Plugin 插件（能力扩展）----
    SkillPack(
      id: 'plugin_tools',
      name: '效率工具包',
      desc: '启用后 AI 更主动使用本机工具（时间/计算/设备信息）',
      category: 'plugin',
      builtin: true,
      prompt:
          '【效率工具包插件】用户询问时间/日期、简单计算、设备信息、好友列表时，优先主动调用对应本机工具，不要凭记忆回答。',
      toolHint:
          '额外提醒：涉及日期时间/四则运算/本机信息时请务必调用工具获取真实值。',
    ),
    SkillPack(
      id: 'plugin_attachments',
      name: '附件理解',
      desc: '用户发送附件时主动说明能做什么',
      category: 'plugin',
      builtin: true,
      prompt:
          '【附件理解插件】收到用户附件（文件/图片/视频）时，先确认收到并简短说明你看到的内容或可以协助的方向；不要假装看到了图片内容。',
    ),
    // ---- Workflow 工作包（预设流程）----
    SkillPack(
      id: 'wf_report',
      name: '周报生成',
      desc: '按「做了什么→成果→下周计划」三步生成周报',
      category: 'workflow',
      builtin: true,
      steps: [
        '请用户列出本周完成的主要工作（可用列表形式输入）',
        '将工作归纳为 3-5 条成果，标注影响/数据',
        '生成下周计划 3 条，并输出完整周报（本周总结+数据+下周计划）',
      ],
    ),
    SkillPack(
      id: 'wf_plan',
      name: '学习计划',
      desc: '按目标拆解 4 周学习计划',
      category: 'workflow',
      builtin: true,
      steps: [
        '确认学习目标、当前水平、每周可投入时间',
        '拆解为 4 周阶段目标（每阶段一个主题）',
        '每周给出具体练习/资料建议，输出完整计划表',
      ],
    ),
  ];

  static List<SkillPack> load() {
    final raw = AmoreStore.getConfig('skills.packs') ?? '';
    final custom = <SkillPack>[];
    if (raw.trim().isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List?) ?? const [];
        custom = list
            .whereType<Map>()
            .map((e) => SkillPack.fromJson(Map<String, dynamic>.from(e)))
            .where((p) => !p.builtin)
            .toList();
      } catch (_) {}
    }
    return [...builtins, ...custom];
  }

  static void saveCustom(List<SkillPack> all) {
    final custom = all.where((p) => !p.builtin).toList();
    AmoreStore.setConfig('skills.packs', jsonEncode(custom.map((e) => e.toJson()).toList()));
  }

  /// 启用的包 id 集合
  static Set<String> enabledIds() {
    final raw = AmoreStore.getConfig('skills.enabled') ?? '';
    if (raw.trim().isEmpty) return {};
    return raw.split(',').where((e) => e.isNotEmpty).toSet();
  }

  static void setEnabled(String id, bool on) {
    final set = enabledIds();
    if (on) {
      set.add(id);
    } else {
      set.remove(id);
    }
    AmoreStore.setConfig('skills.enabled', set.join(','));
  }

  /// 启用的包（注入用）
  static List<SkillPack> enabledPacks() {
    final ids = enabledIds();
    return load().where((p) => ids.contains(p.id)).toList();
  }

  static SkillPack? byId(String id) {
    for (final p in load()) {
      if (p.id == id) return p;
    }
    return null;
  }
}