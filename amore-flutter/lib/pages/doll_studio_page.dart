// Amore 玩偶 Tab — 角色与装扮配置（无 3D；目录见 doll/catalog.dart）
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/store.dart';
import '../state/app_state.dart';
import '../core/theme.dart';
import 'doll/catalog.dart';

class DollStudioPage extends StatefulWidget {
  const DollStudioPage({super.key});

  @override
  State<DollStudioPage> createState() => _DollStudioPageState();
}

class _DollStudioPageState extends State<DollStudioPage> {
  int _tab = 0;
  String _gender = 'female';
  String _skin = '#F3C6A5';
  String _dollName = '小雅';
  Map<String, String> _slots = {}; // category → clothId

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
    _slots = {
      'top': 'top_tee_white',
      'bottom': 'bot_jeans_blue',
      'shoes': 'shoe_sneakers_white',
    };
  }

  Future<void> _restore() async {
    final saved = AmoreStore.getConfig('doll_slots');
    if (saved == null || saved.isEmpty) return;
    try {
      final decoded = jsonDecode(saved) as Map<String, dynamic>;
      setState(() {
        _gender = (decoded['gender'] ?? 'female') as String;
        _skin = (decoded['skin'] ?? '#F3C6A5') as String;
        _dollName = (decoded['name'] ?? '小雅') as String;
        _slots = ((decoded['clothIds'] ?? {}) as Map)
            .map((k, v) => MapEntry(k as String, v as String));
      });
    } catch (_) {}
  }

  Future<void> _persist() async {
    AmoreStore.setConfig('doll_slots',
        '{"gender":"$_gender","skin":"$_skin","name":"$_dollName","clothIds":${jsonEncode(_slots)}}');
    context.read<AppState>().refreshAll();
  }

  void _wear(DollCloth item) {
    setState(() => _slots[item.category] = item.id);
    HapticFeedback.selectionClick();
    _persist();
  }

  void _removeSlot(String category) {
    setState(() => _slots.remove(category));
    _persist();
  }

  String get _tabCategory =>
      DollCatalog.categories[_tab.clamp(0, DollCatalog.categories.length - 1)].key;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), duration: const Duration(milliseconds: 1400)));
  }

  @override
  Widget build(BuildContext context) {
    final items = DollCatalog.clothes
        .where((c) => c.category == _tabCategory)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(
        title: const Text('玩偶工作室',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // 角色卡
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AmoreTheme.cardBox(),
                child: Row(
                  children: [
                    AmoreTheme.avatar(_dollName, size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_dollName,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('$_genderLabel · ${_slots.length} 件单品',
                              style: const TextStyle(
                                  fontSize: 12.5, color: Color(0xFF86868B))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 性别
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final g in const [
                      ('female', '女性玩偶'),
                      ('male', '男性玩偶'),
                      ('neutral', '中性玩偶'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(g.$2),
                          selected: _gender == g.$1,
                          onSelected: (_) {
                            setState(() {
                              _gender = g.$1;
                              _dollName = DollCatalog.genderDefaultName(g.$1);
                            });
                            _persist();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 肤色
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final hex in const [
                      '#F3C6A5', '#E8B48C', '#D69A72', '#B87A50', '#8A5A38', '#F0C0A8',
                    ])
                      GestureDetector(
                        onTap: () {
                          setState(() => _skin = hex);
                          _persist();
                        },
                        child: Container(
                          width: 34,
                          height: 34,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                            border: Border.all(
                              color: _skin == hex
                                  ? AmoreBrand.orange
                                  : const Color(0xFFE3E3E8),
                              width: _skin == hex ? 2.4 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 服装分类
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < DollCatalog.categories.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(DollCatalog.categories[i].title),
                          selected: _tab == i,
                          onSelected: (_) => setState(() => _tab = i),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 服装列表
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AmoreTheme.tile(
                    context: context,
                    icon: _iconFor(item),
                    title: item.name,
                    subtitle: item.price > 0
                        ? '¥${item.price.toInt()} · 单击选择'
                        : '免费 · 单击选择',
                    trailing: _slots[_tabCategory] == item.id
                        ? const Icon(Icons.check_circle_rounded,
                            color: AmoreBrand.orange)
                        : (_slots[_tabCategory] != null &&
                                DollCatalog.byId(_slots[_tabCategory]!)?.category ==
                                    item.category
                            ? null
                            : null),
                    onTap: () => _wear(item),
                  ),
                ),

              if (_slots[_tabCategory] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton.icon(
                    onPressed: () => _removeSlot(_tabCategory),
                    icon: const Icon(Icons.remove_circle_outline_rounded,
                        size: 17, color: Color(0xFFFF3B30)),
                    label: const Text('脱下当前分类服装',
                        style: TextStyle(fontSize: 13, color: Color(0xFFFF3B30))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _genderLabel => _gender == 'male'
      ? '男性玩偶'
      : _gender == 'female'
          ? '女性玩偶'
          : '中性玩偶';

  IconData _iconFor(DollCloth item) {
    switch (item.kind) {
      case 'tee':
        return Icons.checkroom_rounded;
      case 'shirt':
        return Icons.workspaces_rounded;
      case 'hoodie':
      case 'sweater':
        return Icons.dry_cleaning_rounded;
      case 'jacket':
      case 'coat':
        return Icons.storm_rounded;
      case 'pants':
      case 'shorts':
        return Icons.airline_seat_legroom_normal_rounded;
      case 'skirt':
      case 'longskirt':
        return Icons.change_history_rounded;
      case 'scarf':
      case 'scarflong':
      case 'scarfneck':
        return Icons.join_full_rounded;
      case 'cap':
      case 'beanie':
      case 'beret':
      case 'bucket':
        return Icons.ac_unit_rounded;
      case 'sneakers':
      case 'leather':
      case 'boots':
        return Icons.hiking_rounded;
      case 'hairShort':
      case 'hairLong':
      case 'hairCurly':
      case 'hairPony':
        return Icons.face_retouching_natural_rounded;
      case 'glasses':
        return Icons.remove_red_eye_rounded;
      case 'necklace':
        return Icons.auto_awesome_rounded;
      case 'bag':
        return Icons.shopping_bag_rounded;
      case 'earring':
        return Icons.blur_circular_rounded;
      default:
        return Icons.grid_view_rounded;
    }
  }
}
