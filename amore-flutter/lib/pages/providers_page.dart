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

  void _openEditor([AIProvider? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProviderEditSheet(
        existing: existing,
        onSaved: _refresh,
      ),
    );
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
        onPressed: () => _openEditor(null),
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
          switch (kind) { 'main' => '主模型', 'secondary' => '副模型', 'tts' => '语音', _ => '图片' },
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
  final VoidCallback onSaved;

  const ProviderEditSheet({super.key, this.existing, required this.onSaved});

  @override
  State<ProviderEditSheet> createState() => _ProviderEditSheetState();
}

class _ProviderEditSheetState extends State<ProviderEditSheet> {
  late final AIProvider _p;
  final _modelCtl = TextEditingController();
  final _searchCtl = TextEditingController();
  List<String> _modelCandidates = [];
  String _modelQuery = '';
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _p = widget.existing ?? AIProvider(label: '新配置');
    _modelCtl.text = _p.model;
    // 预填：内置目录 + 上次从接口读取的缓存
    _modelCandidates = _mergedCandidates();
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
            // 格式
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'chat', label: Text('Chat Completions')),
                ButtonSegment(value: 'responses', label: Text('Responses')),
              ],
              selected: {_p.apiFormat},
              onSelectionChanged: (s) => setState(() => _p.apiFormat = s.first),
            ),
            const SizedBox(height: 12),
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
            // 模型
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _modelCtl,
                    onChanged: (v) => _p.model = v,
                    decoration: const InputDecoration(hintText: '模型名（可手输或从目录选）'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _modelCandidates = _mergedCandidates();
                      if (_modelCandidates.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                '目录没有 ${_p.vendor} 的预置模型，可点下方「从 API 接口读取模型」')));
                      }
                    });
                  },
                  child: const Text('选模型'),
                ),
              ],
            ),
            // 从接口读取（读取 Base URL 指向的实际模型列表）
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
                    return ListTile(
                      dense: true,
                      title: Text(m, style: const TextStyle(fontSize: 12.5)),
                      onTap: () {
                        setState(() {
                          _modelCtl.text = m;
                          _p.model = m;
                        });
                      },
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            // 音色
            TextField(
              onChanged: (v) => _p.ttsVoice = v,
              controller: TextEditingController(text: _p.ttsVoice),
              decoration: const InputDecoration(hintText: '语音音色（OpenAI 风格，如 alloy）'),
            ),
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
