// 对应 Swift：ProvidersView.swift —— 模型配置（供应商 CRUD + 505 模型选择器）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/chat_engine.dart';
import '../core/model_fetch.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../state/app_state.dart';

class ProvidersPage extends StatefulWidget {
  const ProvidersPage({super.key});

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  String _activeId = '';

  @override
  void initState() {
    super.initState();
    _activeId = AmoreStore.activeProviderId();
  }

  void _refresh() {
    context.read<AppState>().refreshProviders();
    setState(() => _activeId = AmoreStore.activeProviderId());
  }

  void _activate(AIProvider p) {
    AmoreStore.setActiveProvider(p.id);
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已激活「${p.label}」')));
  }

  void _openEditor([AIProvider? existing, String presetKind = 'main']) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProviderEditSheet(
        existing: existing,
        initialKind: existing == null ? presetKind : 'main',
        onSaved: _refresh,
      ),
    );
  }

  // 新建菜单：文字 / 照片 / 语音 三个配置快捷入口
  void _newSheet() {
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded,
                  color: Color(0xFF007AFF)),
              title: const Text('文字模型配置'),
              subtitle: const Text('聊天对话使用'),
              onTap: () => Navigator.pop(ctx, 'main'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined, color: Color(0xFF34C759)),
              title: const Text('照片模型配置'),
              subtitle: const Text('AI 生成图片使用'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.record_voice_over_rounded,
                  color: Color(0xFFAF52DE)),
              title: const Text('语音模型配置'),
              subtitle: const Text('语音朗读使用'),
              onTap: () => Navigator.pop(ctx, 'tts'),
            ),
          ],
        ),
      ),
    ).then((kind) {
      if (kind != null) _openEditor(null, kind);
    });
  }

  @override
  Widget build(BuildContext context) {
    final providers = context.watch<AppState>().providers;
    final vendors = AmoreStore.vendors();

    return Scaffold(
      appBar: AppBar(title: const Text('模型配置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              // 本机直连说明
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AmoreTheme.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AmoreTheme.accent.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.home_work_rounded, color: AmoreTheme.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Base 填 127.0.0.1 / localhost 的 OpenAI 兼容服务（Locally AI / Ollama / LM Studio）将本机直连，不经服务器。',
                        style: TextStyle(fontSize: 11.8, color: AmoreTheme.textSecondary, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (providers.isEmpty)
                _emptyCard()
              else
                ...providers.map((p) {
                  final vendor = vendors.where((v) => v.key == p.vendor).firstOrNull;
                  final active = p.id == _activeId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openEditor(p),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: AmoreTheme.cardBox(
                            border: active ? AmoreTheme.accent.withOpacity(0.6) : null,
                          ),
                          child: Row(
                            children: [
                              Radio<String>(
                                value: p.id,
                                groupValue: _activeId,
                                onChanged: (_) => _activate(p),
                                activeColor: AmoreTheme.accent,
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(p.label,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 15, fontWeight: FontWeight.w600)),
                                        ),
                                        const SizedBox(width: 6),
                                        _kindBadge(p.kind),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${vendor?.name ?? p.vendor} · ${p.model.isEmpty ? "未选模型" : p.model} · ${p.maskedKey()}',
                                      style: const TextStyle(
                                          fontSize: 11.8, color: AmoreTheme.textSecondary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () => _activate(p),
                                child: Text(active ? '已激活' : '激活',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: active ? AmoreTheme.success : AmoreTheme.accent)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AmoreTheme.accent,
        onPressed: _newSheet,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('新建', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _kindBadge(String kind) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AmoreTheme.accent2.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          switch (kind) {
            'main' => '文字',
            'image' => '照片',
            'tts' => '语音',
            _ => '副模型'
          },
          style: const TextStyle(fontSize: 10, color: AmoreTheme.accent2),
        ),
      );

  Widget _emptyCard() => Container(
        padding: const EdgeInsets.all(28),
        decoration: AmoreTheme.cardBox(),
        child: Column(
          children: [
            const Icon(Icons.dns_rounded, size: 48, color: AmoreTheme.textFaint),
            const SizedBox(height: 12),
            const Text('还没有模型配置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('添加一个 OpenAI 兼容供应商并激活，聊天即生效',
                style: TextStyle(fontSize: 12, color: AmoreTheme.textSecondary)),
          ],
        ),
      );
}

/// 供应商编辑表单
class ProviderEditSheet extends StatefulWidget {
  final AIProvider? existing;
  final String initialKind; // 新建时预设类型（main / image / tts）
  final VoidCallback onSaved;

  const ProviderEditSheet(
      {super.key, this.existing, this.initialKind = 'main', required this.onSaved});

  @override
  State<ProviderEditSheet> createState() => _ProviderEditSheetState();
}

class _ProviderEditSheetState extends State<ProviderEditSheet> {
  late final AIProvider _p;
  final _modelCtl = TextEditingController(); // 聊天模型
  final _imageCtl = TextEditingController(); // 图片模型
  final _ttsCtl = TextEditingController(); // 语音模型
  final _searchCtl = TextEditingController();
  List<String> _modelCandidates = [];
  String _modelQuery = '';
  String _typeFilter = 'all'; // all / text / tts / image
  String _target = 'chat'; // 候选列表点选写入目标：chat / image / tts
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _p = widget.existing ??
        AIProvider(label: '新配置', kind: widget.initialKind);
    // 兼容旧配置：kind=tts 时 model 里存的是语音模型名
    _modelCtl.text = _p.kind == 'tts' ? '' : _p.model;
    _imageCtl.text = _p.imageModel;
    _ttsCtl.text = _p.kind == 'tts' ? _p.model : _p.ttsModel;
    // 预填：内置目录 + 上次从接口读取的缓存
    _modelCandidates = _mergedCandidates();
  }

  // 模型槽位行：标签 + 输入框 + 选模型按钮
  Widget _slotField({
    required String label,
    required TextEditingController ctl,
    required String hint,
    required ValueChanged<String> onChanged,
    required VoidCallback onPick,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AmoreTheme.textSecondary)),
          ),
          Expanded(
            child: TextField(
              controller: ctl,
              onChanged: onChanged,
              decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact),
            child: const Text('选'),
          ),
        ],
      ),
    );
  }

  /// 候选列表写入目标（按配置类型只显示对应一项）
  List<(String, String)> get _targetChips => switch (_p.kind) {
        'image' => const [('image', '照片')],
        'tts' => const [('tts', '语音')],
        _ => const [('chat', '文字')],
      };

  /// 打开候选列表并设定写入目标
  void _openCandidates(String target) {
    setState(() {
      _target = target;
      _modelCandidates = _mergedCandidates();
      if (_modelCandidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '目录没有 ${_p.vendor} 的预置模型，可点下方「从 API 接口读取模型」')));
      }
    });
  }

  /// 上次从接口读取并缓存的模型（换厂商自动失效）
  List<String> _cachedModels() {
    final raw = AmoreStore.getConfig('models_cache_${_p.vendor}') ?? '';
    return raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _mergedCandidates() {
    final set = <String>{
      ...AmoreStore.modelsOf(_p.vendor),
      ..._cachedModels(),
    };
    return set.toList()..sort();
  }

  // 模型类型徽标（自动分类结果：文字/语音/图片）
  Widget _typeBadge(String cls) {
    final (label, color) = switch (cls) {
      'tts' => ('语音', const Color(0xFFAF52DE)),
      'image' => ('图片', const Color(0xFF34C759)),
      _ => ('文字', const Color(0xFF007AFF)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9.5,
              color: color,
              fontWeight: FontWeight.w700)),
    );
  }

  bool _testing = false;

  /// 发送一条最小请求验证配置是否可用（错误原因直接显示）
  Future<void> _testModel() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      final p = _p;
      if (_modelCtl.text.trim().isNotEmpty) {
        p.model = _modelCtl.text.trim();
      }
      final reply = await ChatEngine.request(
        p,
        [
          {'role': 'user', 'content': 'ping'}
        ],
        '你是连通性测试助手，只回复 OK 两个字母。',
      );
      if (!mounted) return;
      final preview = reply.length > 60 ? reply.substring(0, 60) : reply;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF34C759),
          duration: const Duration(seconds: 4),
          content: Text('✓ 连接成功：$preview')));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFFFF3B30),
          duration: const Duration(seconds: 7),
          content: Text('✗ 测试失败：$msg')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// 从配置的 API 接口读取模型列表（OpenAI /v1/models 等）
  Future<void> _fetchApi() async {
    if (_fetching) return;
    setState(() => _fetching = true);
    try {
      final list = await ModelFetch.fetch(_p);
      if (!mounted) return;
      AmoreStore.setConfig(
          'models_cache_${_p.vendor}', list.take(800).join('\n'));
      setState(() {
        _modelCandidates = list;
        _modelQuery = '';
        _searchCtl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已从接口读取 ${list.length} 个模型')));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('读取失败：$msg\n请检查 Base URL 与 API Key'),
          duration: const Duration(seconds: 4)));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  void dispose() {
    _modelCtl.dispose();
    _imageCtl.dispose();
    _ttsCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  void _pickVendor(String key) {
    setState(() {
      _p.vendor = key;
      final v = AmoreStore.vendors().where((x) => x.key == key).firstOrNull;
      if (v != null) {
        _p.baseURL = v.base == '' ? _p.baseURL : '';
        _p.apiFormat = v.format;
        if (v.model.isNotEmpty) {
          _p.model = v.model;
          _modelCtl.text = v.model;
        }
        _modelCandidates = _mergedCandidates();
      }
    });
  }

  void _save() {
    _p.model = _modelCtl.text.trim();
    _p.imageModel = _imageCtl.text.trim();
    _p.ttsModel = _ttsCtl.text.trim();
    AmoreStore.saveProvider(_p);
    // 首个配置自动激活
    if (AmoreStore.activeProviderId().isEmpty) {
      AmoreStore.setActiveProvider(_p.id);
    }
    widget.onSaved();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
  }

  @override
  Widget build(BuildContext context) {
    final vendors = AmoreStore.vendors();
    // 厂商分组
    final groups = <String, List<AIVendor>>{};
    for (final v in vendors) {
      groups.putIfAbsent(v.group, () => []).add(v);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? '新建配置' : '编辑「${_p.label}」',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            // 名称
            TextField(
              onChanged: (v) => _p.label = v,
              controller: TextEditingController(text: _p.label),
              decoration: const InputDecoration(hintText: '配置名称'),
            ),
            const SizedBox(height: 12),
            // 配置类型（文字 / 照片 / 语音——决定用途与列表徽标；槽位仍可全填）
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'main', label: Text('文字')),
                ButtonSegment(value: 'image', label: Text('照片')),
                ButtonSegment(value: 'tts', label: Text('语音')),
              ],
              selected: {_p.kind},
              onSelectionChanged: (sel) => setState(() {
                _p.kind = sel.first;
                // 同步候选列表写入目标（文字→chat / 照片→image / 语音→tts）
                _target = sel.first == 'image'
                    ? 'image'
                    : sel.first == 'tts'
                        ? 'tts'
                        : 'chat';
              }),
            ),
            const SizedBox(height: 12),
            // 厂商选择
            DropdownButtonFormField<String>(
              initialValue: _p.vendor,
              decoration: const InputDecoration(labelText: '厂商'),
              isExpanded: true,
              items: groups.entries
                  .expand((g) => [
                        DropdownMenuItem<String>(
                          enabled: false,
                          value: null,
                          child: Text('── ${g.key} ──',
                              style: const TextStyle(fontSize: 11, color: AmoreTheme.textFaint)),
                        ),
                        ...g.value.map((v) => DropdownMenuItem(
                              value: v.key,
                              child: Text(v.name, style: const TextStyle(fontSize: 13.5)),
                            )),
                      ])
                  .toList(),
              onChanged: (k) => _pickVendor(k ?? 'openai_generic'),
            ),
            const SizedBox(height: 12),
            // 格式（仅主模型）
            if (_p.kind == 'main') ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'chat', label: Text('Chat Completions')),
                  ButtonSegment(value: 'responses', label: Text('Responses')),
                ],
                selected: {_p.apiFormat},
                onSelectionChanged: (s) =>
                    setState(() => _p.apiFormat = s.first),
              ),
              const SizedBox(height: 12),
            ],
            // Key
            TextField(
              onChanged: (v) => _p.apiKey = v,
              controller: TextEditingController(text: _p.apiKey),
              obscureText: true,
              decoration: const InputDecoration(hintText: 'API Key（可留空）'),
            ),
            const SizedBox(height: 12),
            // Base URL
            TextField(
              onChanged: (v) => _p.baseURL = v,
              controller: TextEditingController(text: _p.baseURL),
              decoration: const InputDecoration(hintText: 'Base URL（留空=官方默认；本机直连填 127.0.0.1:端口/v1）'),
            ),
            const SizedBox(height: 12),
            // ---- 模型槽位：按配置类型只显示对应一个（文字/照片/语音）----
            if (_p.kind == 'main')
              _slotField(
                label: '聊天模型',
                ctl: _modelCtl,
                hint: '如 gpt-4o / deepseek-chat',
                onChanged: (v) => _p.model = v,
                onPick: () => _openCandidates('chat'),
              ),
            if (_p.kind == 'image')
              _slotField(
                label: '图片模型',
                ctl: _imageCtl,
                hint: '如 gpt-image-1 / FLUX.1',
                onChanged: (v) => _p.imageModel = v,
                onPick: () => _openCandidates('image'),
              ),
            if (_p.kind == 'tts') ...[
              _slotField(
                label: '语音模型',
                ctl: _ttsCtl,
                hint: '如 tts-1 / gpt-4o-mini-tts',
                onChanged: (v) => _p.ttsModel = v,
                onPick: () => _openCandidates('tts'),
              ),
              const SizedBox(height: 4),
              TextField(
                onChanged: (v) => _p.ttsVoice = v,
                controller: TextEditingController(text: _p.ttsVoice),
                decoration: const InputDecoration(
                    labelText: '语音音色',
                    hintText: '如 alloy / coral（仅语音朗读用）'),
              ),
            ],
            const SizedBox(height: 8),
            // 从接口读取 + 测试聊天模型
            Row(
              children: [
                TextButton.icon(
                  onPressed: _fetching ? null : _fetchApi,
                  icon: _fetching
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_download_outlined, size: 17),
                  label: Text(_fetching ? '正在读取…' : '从 API 接口读取模型'),
                ),
                TextButton.icon(
                  onPressed: _testing ? null : _testModel,
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering_rounded, size: 17),
                  label: Text(_testing ? '测试中…' : '测试模型'),
                ),
                const Spacer(),
                if (_modelCandidates.isNotEmpty)
                  Text('${_modelCandidates.length} 个可选',
                      style: const TextStyle(
                          fontSize: 11.5, color: AmoreTheme.textFaint)),
              ],
            ),
            // 模型选择列表
            if (_modelCandidates.isNotEmpty) ...[
              const SizedBox(height: 8),
              // 写入目标：点列表里的模型填到哪个槽位
              Row(
                children: [
                  const Text('点选填入',
                      style: TextStyle(
                          fontSize: 11.5, color: AmoreTheme.textSecondary)),
                  const SizedBox(width: 8),
                  for (final (val, label) in _targetChips)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(label,
                            style: const TextStyle(fontSize: 11.5)),
                        selected: _target == val,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _target = val),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // 自动分类筛选：全部 / 文字 / 语音 / 图片
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (val, label) in const [
                      ('all', '全部'),
                      ('text', '文字'),
                      ('tts', '语音'),
                      ('image', '图片'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(label,
                              style: const TextStyle(fontSize: 11.5)),
                          selected: _typeFilter == val,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => _typeFilter = val),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtl,
                onChanged: (v) => setState(() => _modelQuery = v.toLowerCase()),
                decoration: InputDecoration(
                  hintText: '搜索 ${_modelCandidates.length} 个模型',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AmoreTheme.cardBorder),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _modelCandidates.length,
                  itemBuilder: (_, i) {
                    final m = _modelCandidates[i];
                    if (_modelQuery.isNotEmpty && !m.toLowerCase().contains(_modelQuery)) {
                      return const SizedBox.shrink();
                    }
                    final cls = ModelClassifier.classify(m);
                    if (_typeFilter != 'all' && cls != _typeFilter) {
                      return const SizedBox.shrink();
                    }
                    return ListTile(
                      dense: true,
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(m,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                          const SizedBox(width: 6),
                          _typeBadge(cls),
                        ],
                      ),
                      onTap: () {
                        setState(() {
                          switch (_target) {
                            case 'image':
                              _imageCtl.text = m;
                              _p.imageModel = m;
                            case 'tts':
                              _ttsCtl.text = m;
                              _p.ttsModel = m;
                            default:
                              _modelCtl.text = m;
                              _p.model = m;
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.existing != null)
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AmoreTheme.danger,
                          side: const BorderSide(color: AmoreTheme.danger)),
                      onPressed: () {
                        AmoreStore.deleteProvider(_p.id);
                        widget.onSaved();
                        Navigator.pop(context);
                      },
                      child: const Text('删除'),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(onPressed: _save, child: const Text('保存')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension _First<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
