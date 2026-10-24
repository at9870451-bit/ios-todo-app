// 技能中心数据层：Skill 技能 / Plugin 插件 / Workflow 工作包
// 配置存 Rust config（skills.packs / skills.enabled / skills.mcp）
import 'dart:convert';

import 'store.dart';

class SkillPack {
  String id;
  String name;
  String desc;
  String category; // skill / plugin / workflow

  // Skill：模型调用单元 —— 功能描述 + 参数规范 + 执行
  String parameters; // JSON Schema（模型据此生成参数）
  String handler; // 执行器：tool:<本地工具名> 或 script 占位/prompt 提示词型
  String prompt; // 提示词型技能（无执行器时注入）

  // Plugin：系统级扩展 —— 消息钩子（send/recv）
  String hook; // send / recv / ''（空 = 不挂钩子）

  // Workflow(Toolpkg)：打包分发 —— manifest + 步骤
  String manifest; // 清单 JSON（version/author/entry）
  List<String> steps; // 步骤模板

  bool builtin;

  SkillPack({
    this.id = '',
    this.name = '',
    this.desc = '',
    this.category = 'skill',
    this.parameters = '',
    this.handler = '',
    this.prompt = '',
    this.hook = '',
    this.manifest = '',
    List<String>? steps,
    this.builtin = false,
  }) : steps = steps ?? const [];

  factory SkillPack.fromJson(Map<String, dynamic> j) => SkillPack(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        desc: j['desc']?.toString() ?? '',
        category: j['category']?.toString() ?? 'skill',
        parameters: j['parameters']?.toString() ?? '',
        handler: j['handler']?.toString() ?? '',
        prompt: j['prompt']?.toString() ?? '',
        hook: j['hook']?.toString() ?? '',
        manifest: j['manifest']?.toString() ?? '',
        steps: (j['steps'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        builtin: j['builtin'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'desc': desc,
        'category': category,
        'parameters': parameters,
        'handler': handler,
        'prompt': prompt,
        'hook': hook,
        'manifest': manifest,
        'steps': steps,
        'builtin': builtin,
      };

  /// 该技能是否可被模型调用（有执行器或参数规范）
  bool get callable => (handler.isNotEmpty || parameters.isNotEmpty) && category == 'skill';
}


/// 内置技能/插件/工作包目录
class SkillCatalog {
  static final List<SkillPack> builtins = [
    // ---- Skill 技能（模型调用单元：描述 + JSON Schema + 执行器）----
    SkillPack(
      id: 'skill_textstats',
      name: '文本统计',
      desc: '统计文本的字数、字符数、段落数、行数',
      category: 'skill',
      builtin: true,
      parameters:
          '{"type":"object","properties":{"text":{"type":"string","description":"要统计的文本"}},"required":["text"]}',
      handler: 'script:textstats',
      prompt:
          '【文本统计技能】用户需要字数/字符数/段落数/行数统计时，调用 skill:textstats 技能，不要自己数。',
    ),
    SkillPack(
      id: 'skill_clock',
      name: '时间查询',
      desc: '获取当前日期时间（精确到秒）',
      category: 'skill',
      builtin: true,
      parameters:
          '{"type":"object","properties":{},"required":[]}',
      handler: 'tool:get_time',
      prompt:
          '【时间查询技能】用户询问当前时间/日期时，调用 skill:clock 技能获取真实时间。',
    ),
    SkillPack(
      id: 'skill_calc',
      name: '数学计算',
      desc: '精确计算四则运算表达式',
      category: 'skill',
      builtin: true,
      parameters:
          '{"type":"object","properties":{"expression":{"type":"string","description":"四则运算表达式，如 12*(3+4)"}},"required":["expression"]}',
      handler: 'tool:calc',
      prompt:
          '【数学计算技能】需要精确计算时调用 skill:calc 技能，不要心算。',
    ),
    SkillPack(
      id: 'skill_run_code',
      name: '编程执行',
      desc: '本地计算与数据处理（表达式/base64/URL/JSON/正则/文本统计）',
      category: 'skill',
      builtin: true,
      parameters:
          '{"type":"object","properties":{"op":{"type":"string","description":"eval/base64/url/json/regex/stats"},"input":{"type":"string","description":"输入内容"},"arg":{"type":"string","description":"可选参数"}},"required":["op","input"]}',
      handler: 'script:code',
      prompt:
          '【编程执行技能】需要精确计算、数据转换、正则处理时调用 skill:run_code 技能（或 run_code 工具），不要心算或猜测。',
    ),
    SkillPack(
      id: 'skill_rand',
      name: '随机数',
      desc: '生成指定范围的随机整数',
      category: 'skill',
      builtin: true,
      parameters:
          '{"type":"object","properties":{"min":{"type":"number"},"max":{"type":"number"}},"required":["min","max"]}',
      handler: 'tool:random',
      prompt:
          '【随机数技能】用户需要随机数/抽签/掷骰子时调用 skill:rand 技能。',
    ),
    // ---- Plugin 插件（宿主级扩展：消息钩子 / 行为注入）----
    SkillPack(
      id: 'plugin_tools',
      name: '效率工具包',
      desc: '宿主工具增强：AI 更主动调用本机工具（时间/计算/设备信息）',
      category: 'plugin',
      builtin: true,
      hook: 'recv',
      handler: 'prompt',
      prompt:
          '【效率工具包插件】用户询问时间/日期、简单计算、设备信息、好友列表时，优先主动调用对应本机工具，不要凭记忆回答。',
    ),
    SkillPack(
      id: 'plugin_attachments',
      name: '附件理解',
      desc: 'recv 钩子：收到附件消息时系统注入附件说明，AI 明确能做什么',
      category: 'plugin',
      builtin: true,
      hook: 'recv',
      handler: 'prompt',
      prompt:
          '【附件理解插件】收到用户附件（文件/图片/视频）时，先确认收到并简短说明你看到的内容或可以协助的方向；不要假装看到了图片内容。',
    ),
    // ---- Workflow 工作包（Toolpkg：manifest 打包分发）----
    SkillPack(
      id: 'wf_report',
      name: '周报生成',
      desc: '按「做了什么→成果→下周计划」三步生成周报',
      category: 'workflow',
      builtin: true,
      manifest:
          '{"name":"周报生成","version":"1.0.0","author":"Amore","entry":"steps","kind":"workflow"}',
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
      manifest:
          '{"name":"学习计划","version":"1.0.0","author":"Amore","entry":"steps","kind":"workflow"}',
      steps: [
        '确认学习目标、当前水平、每周可投入时间',
        '拆解为 4 周阶段目标（每阶段一个主题）',
        '每周给出具体练习/资料建议，输出完整计划表',
      ],
    ),
  ];

  static List<SkillPack> load() {
    final raw = AmoreStore.getConfig('skills.packs') ?? '';
    var custom = <SkillPack>[];
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