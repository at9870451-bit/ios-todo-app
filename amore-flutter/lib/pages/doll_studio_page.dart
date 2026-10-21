// Amore 玩偶 Tab — 3D 换装工作室（SceneKit PlatformView + 衣橱面板）
// Apple 白×橙视觉；服装目录 lib/pages/doll/catalog.dart；3D 原生层 ios/Runner/DollScene*
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/store.dart';
import '../state/app_state.dart';
import '../core/theme.dart';
import 'doll/catalog.dart';
import 'doll/scene3d.dart';

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
  double _heightScale = 1.0;

  /// 当前穿搭：category → {kind, color}
  Map<String, Map<String, String>> _slots = {};

  final List<Map<String, Map<String, String>>> _undoStack = [];
  final List<Map<String, Map<String, String>>> _redoStack = [];
  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  final Set<String> _favorites = {};
  final List<String> _recent = [];
  final Set<String> _owned = {};
  bool _skinned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
    _slots = {
      'top': const {'kind': 'tee', 'color': '#F5F5F7'},
      'bottom': const {'kind': 'pants', 'color': '#4A6B9A'},
      'shoes': const {'kind': 'sneakers', 'color': '#F0F0F2'},
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
        _heightScale = (decoded['height'] as num?)?.toDouble() ?? 1.0;
        final restored = <String, Map<String, String>>{};
        ((decoded['slots'] ?? {}) as Map).forEach((k, v) {
          final inner = <String, String>{};
          (v as Map).forEach((kk, vv) {
            inner[kk.toString()] = vv.toString();
          });
          restored[k.toString()] = inner;
        });
        _slots = restored;
        final owned = AmoreStore.getConfig('doll_owned');
        if (owned != null && owned.isNotEmpty) _owned.addAll(owned.split(','));
      });
    } catch (_) {
      // 损坏数据忽略
    }
  }

  Future<void> _persist() async {
    AmoreStore.setConfig('doll_slots',
        '{"gender":"$_gender","skin":"$_skin","name":"$_dollName","height":$_heightScale,"slots":${jsonEncode(_slots)}}');
    AmoreStore.setConfig('doll_owned', _owned.join(','));
    context.read<AppState>().refreshAll();
  }

  void _pushUndo() {
    _undoStack.add(Map.of(_slots));
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
    _persist();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(Map.of(_slots));
    setState(() => _slots = _undoStack.removeLast());
    _persist();
    HapticFeedback.selectionClick();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(Map.of(_slots));
    setState(() => _slots = _redoStack.removeLast());
    _persist();
    HapticFeedback.selectionClick();
  }

  void _wear(DollCloth item) {
    if (item.price > 0 && !_owned.contains(item.id)) {
      setState(() => _owned.add(item.id)); // 本地模拟解锁；正式接服务端订单
      _persist();
      _toast('已解锁「${item.name}」（¥${item.price.toInt()}，本地模拟）');
      return;
    }
    _pushUndo();
    if (item.exclusiveGroup != null) {
      _slots.removeWhere((cat, slot) {
        final matches = DollCatalog.clothes.any((c) =>
            c.kind == slot['kind'] &&
            c.exclusiveGroup == item.exclusiveGroup &&
            cat != item.category);
        return matches;
      });
    }
    setState(() {
      _slots[item.category] = {'kind': item.kind, 'color': item.color};
      _recent
        ..remove(item.id)
        ..insert(0, item.id);
      if (_recent.length > 20) _recent.removeLast();
    });
    HapticFeedback.selectionClick();
  }

  void _removeSlot(String category) {
    if (_slots[category] == null) return;
    _pushUndo();
    setState(() => _slots.remove(category));
  }

  void _setColor(String hex) {
    if (_slots[_tabCategory] == null) return;
    _pushUndo();
    setState(() {
      _slots[_tabCategory] = {..._slots[_tabCategory]!, 'color': hex};
    });
  }

  void _reset() {
    _pushUndo();
    setState(() {
      _slots = {
        'top': const {'kind': 'tee', 'color': '#F5F5F7'},
        'bottom': const {'kind': 'pants', 'color': '#4A6B9A'},
        'shoes': const {'kind': 'sneakers', 'color': '#F0F0F2'},
      };
    });
  }

  String get _tabCategory =>
      DollCatalog.categories[_tab.clamp(0, DollCatalog.categories.length - 1)].key;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), duration: const Duration(milliseconds: 1400)));
  }

  // MARK: 截图分享（原生 snapshot → PNG bytes → 存剪贴板提示 + 预览）

  Future<void> _shareSnapshot() async {
    final data = await DollSceneChannel.snapshot();
    if (data == null) {
      _toast('截图不可用（原生层未就绪）');
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('穿搭截图'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: Image.memory(data, fit: BoxFit.contain),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: 'data:image/png;base64,${base64Encode(data)}'));
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('截图已复制（base64），保存到相册 M5 接入');
            },
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = DollCatalog.clothes
        .where((c) => c.category == _tabCategory)
        .toList()
      ..sort((a, b) {
        final fa = _favorites.contains(a.id) ? 0 : 1;
        final fb = _favorites.contains(b.id) ? 0 : 1;
        if (fa != fb) return fa - fb;
        final ra = _recent.indexOf(a.id);
        final rb = _recent.indexOf(b.id);
        return (ra < 0 ? 999 : ra) - (rb < 0 ? 999 : rb);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('玩偶工作室',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        actions: [
          Tooltip(
            message: _skinned ? '切换程序化玩偶' : '切换骨骼模型',
            child: IconButton(
              onPressed: () async {
                if (_skinned) {
                  await DollSceneChannel.unloadSkinned();
                  setState(() => _skinned = false);
                } else {
                  final ok = await DollSceneChannel.loadSkinned();
                  setState(() => _skinned = ok);
                  _toast(ok ? '已加载骨骼模型（含行走动画）' : '骨骼模型资源不可用');
                }
              },
              icon: Icon(
                _skinned ? Icons.accessibility_new_rounded : Icons.accessibility_rounded,
                color: _skinned ? const Color(0xFFFF9500) : const Color(0xFF1D1D1F),
              ),
            ),
          ),
          IconButton(
            tooltip: '保存截图',
            onPressed: _shareSnapshot,
            icon: const Icon(Icons.photo_camera_outlined),
          ),
        ],
      ),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(child: _sceneArea()),
              _wardrobePanel(items),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: 3D 区

  Widget _sceneArea() {
    return Stack(
      children: [
        Positioned.fill(
          child: DollScene3D(
            gender: _gender,
            skin: _skin,
            heightScale: _heightScale,
            slots: _slots,
          ),
        ),
        Positioned(
          left: 14,
          top: 8,
          child: Column(
            children: [
              _viewBtn('正面'),
              const SizedBox(height: 8),
              _viewBtn('侧面'),
              const SizedBox(height: 8),
              _viewBtn('背面'),
              const SizedBox(height: 8),
              _roundBtn(Icons.refresh_rounded, () {
                DollSceneChannel.resetView();
                HapticFeedback.selectionClick();
              }),
            ],
          ),
        ),
        Positioned(
          right: 14,
          top: 8,
          child: Column(
            children: [
              _poseBtn('站姿', 'standing'),
              const SizedBox(height: 8),
              _poseBtn('自然', 'relaxed'),
              const SizedBox(height: 8),
              _poseBtn('展示', 'presentation'),
            ],
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 8,
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$_genderLabel · $_dollName',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF86868B))),
              ),
              const Spacer(),
              const Text('单指旋转 · 双指缩放',
                  style: TextStyle(fontSize: 11, color: Color(0xFFAEAEB2))),
            ],
          ),
        ),
      ],
    );
  }

  String get _genderLabel => _gender == 'male'
      ? '男性玩偶'
      : _gender == 'female'
          ? '女性玩偶'
          : '中性玩偶';

  Widget _viewBtn(String label) {
    return GestureDetector(
      onTap: () {
        DollSceneChannel.face(label);
        HapticFeedback.selectionClick();
      },
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child:
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF1D1D1F))),
      ),
    );
  }

  Widget _poseBtn(String label, String pose) {
    return GestureDetector(
      onTap: () {
        DollSceneChannel.applyPose(pose);
        HapticFeedback.selectionClick();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child:
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF1D1D1F))),
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(icon, size: 17, color: const Color(0xFF1D1D1F)),
      ),
    );
  }

  // MARK: 衣橱面板（Liquid Glass）

  Widget _wardrobePanel(List<DollCloth> items) {
    return GlassContainer(
      radius: 24,
      blur: 20,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                if (_slots[_tabCategory] != null) _removeThumb(),
                for (final item in items)
                  if (_slots[_tabCategory] == null ||
                      _slots[_tabCategory]!['kind'] != item.kind ||
                      _slots[_tabCategory]!['color'] != item.color)
                    _thumb(item),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                if (_slots[_tabCategory] != null)
                  Expanded(child: _colorRow())
                else
                  const Spacer(),
                _panelBtn(Icons.undo_rounded, _canUndo, _undo),
                const SizedBox(width: 6),
                _panelBtn(Icons.redo_rounded, _canRedo, _redo),
                const SizedBox(width: 6),
                _panelBtn(Icons.restart_alt_rounded, true, _reset),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _removeThumb() {
    return GestureDetector(
      onTap: () => _removeSlot(_tabCategory),
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: AmoreBrand.orangeBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.remove, color: AmoreBrand.orangeDeep, size: 18),
            ),
            const SizedBox(height: 5),
            const Text('脱下',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF86868B))),
          ],
        ),
      ),
    );
  }

  Widget _thumb(DollCloth item) {
    final locked = item.price > 0 && !_owned.contains(item.id);
    final fav = _favorites.contains(item.id);
    return GestureDetector(
      onTap: () => _wear(item),
      onLongPress: () {
        setState(() {
          if (fav) {
            _favorites.remove(item.id);
          } else {
            _favorites.add(item.id);
          }
        });
        _toast(fav ? '已取消收藏' : '已收藏');
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Color(int.parse('FF${item.color.substring(1)}', radix: 16)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE3E3E8)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _iconFor(item),
                    color: Colors.white.withOpacity(0.95),
                    size: 22,
                  ),
                ),
                if (locked)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.lock_rounded,
                          color: Colors.white, size: 16),
                    ),
                  ),
                if (fav)
                  const Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(Icons.favorite_rounded,
                        color: Color(0xFFFF3B30), size: 11),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(item.name,
                style: TextStyle(
                    fontSize: 10.5,
                    color: locked
                        ? const Color(0xFFAEAEB2)
                        : const Color(0xFF1D1D1F))),
          ],
        ),
      ),
    );
  }

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

  Widget _colorRow() {
    const colors = [
      '#2B2B2E', '#5A5A5E', '#8E8E93', '#F5F5F7',
      '#5B8DEF', '#3478F6', '#67C7FF', '#8C9EFF',
      '#FF9500', '#FF6A00', '#F4A6C0', '#C4453C',
      '#34C759', '#6B4A32', '#C8A882', '#7A5A8A',
    ];
    final current = _slots[_tabCategory]?['color']?.toLowerCase();
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final hex in colors)
            GestureDetector(
              onTap: () => _setColor(hex),
              child: Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                  border: Border.all(
                    color: current == hex.toLowerCase()
                        ? const Color(0xFF1D1D1F)
                        : const Color(0xFFD1D1D6),
                    width: current == hex.toLowerCase() ? 2.2 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFFF2F2F7)
              : const Color(0xFFF2F2F7).withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon,
            size: 16,
            color: enabled ? const Color(0xFF1D1D1F) : const Color(0xFFC7C7CC)),
      ),
    );
  }
}
