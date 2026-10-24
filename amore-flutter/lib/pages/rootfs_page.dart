// Rootfs 管理：沙盒存储总览 / 目录浏览 / 清理（对应设置 → Rootfs）
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/store.dart';
import '../core/aojit.dart';
import '../core/mirrors.dart';
import '../core/theme.dart';
import '../state/app_state.dart';

class RootfsPage extends StatefulWidget {
  const RootfsPage({super.key});

  @override
  State<RootfsPage> createState() => _RootfsPageState();
}

class _RootfsPageState extends State<RootfsPage> {
  Map<String, int> _sizes = {};
  List<_FsEntry> _root = [];
  bool _scanning = true;
  String _fsFooter = '';

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    await Future.delayed(const Duration(milliseconds: 50));
    final dir = AmoreStore.dataDir;
    final rootDir = Directory(dir);
    final entries = <_FsEntry>[];
    final sizes = <String, int>{};
    var total = 0;
    try {
      await for (final e in rootDir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          final len = e.lengthSync();
          total += len;
          final rel = e.path.substring(dir.length).replaceAll('\\', '/');
          final parts = rel.split('/');
          final top = parts.length > 1 ? parts[1] : '(文件)';
          if (top == 'history') {
            sizes['聊天记录'] = (sizes['聊天记录'] ?? 0) + len;
          } else if (top == 'attachments') {
            sizes['附件'] = (sizes['附件'] ?? 0) + len;
          } else if (top == 'avatars') {
            sizes['头像'] = (sizes['头像'] ?? 0) + len;
          } else if (top == 'backgrounds') {
            sizes['背景图'] = (sizes['背景图'] ?? 0) + len;
          } else {
            sizes['配置/其他'] = (sizes['配置/其他'] ?? 0) + len;
          }
        }
      }
      // 顶层目录列表
      await for (final e in rootDir.list(followLinks: false)) {
        if (e is Directory) {
          var sz = 0;
          try {
            await for (final f in e.list(recursive: true, followLinks: false)) {
              if (f is File) sz += f.lengthSync();
            }
          } catch (_) {}
          entries.add(_FsEntry(e.path.split('/').last, sz, isDir: true));
        } else if (e is File) {
          entries.add(_FsEntry(e.path.split('/').last, e.lengthSync()));
        }
      }
    } catch (_) {}
    entries.sort((a, b) => b.size.compareTo(a.size));
    if (mounted) {
      setState(() {
        _sizes = sizes;
        _root = entries;
        _scanning = false;
        _fsFooter = '沙盒根目录：$dir';
      });
    }
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  Future<void> _clean(String key, Directory dir) async {
    if (!dir.existsSync()) return;
    try {
      await for (final e in dir.list(followLinks: false)) {
        try {
          if (e is Directory) {
            await e.delete(recursive: true);
          } else {
            await e.delete();
          }
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ $key已清理')));
        _scan();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final total = _root.fold<int>(0, (s, e) => s + e.size);
    final items = [
      ('聊天记录', _sizes['聊天记录'] ?? 0, Directory('${AmoreStore.dataDir}/history'),
          '所有本地消息 JSON'),
      ('附件', _sizes['附件'] ?? 0, Directory('${AmoreStore.dataDir}/attachments'),
          '图片/视频/文件（重新导入可选）'),
      ('头像', _sizes['头像'] ?? 0, Directory('${AmoreStore.dataDir}/avatars'),
          '好友自定义头像'),
      ('背景图', _sizes['背景图'] ?? 0, Directory('${AmoreStore.dataDir}/backgrounds'),
          '聊天背景图片'),
      ('配置/其他', _sizes['配置/其他'] ?? 0, Directory(AmoreStore.dataDir),
          '供应商配置、技能包、MCP 服务等'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rootfs 管理',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: _scanning && _root.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    // 存储总览
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: AmoreTheme.cardBox(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('沙盒存储总览',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AmoreTheme.textSecondary)),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_fmt(total),
                                  style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: Text('共 ${_root.length} 项',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AmoreTheme.textFaint)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: total <= 0 ? 0 : 0.6,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '沙盒（HostIsolation.osAppSandbox）内数据均为本机私有，rootfs 大小 = 全部文件占用',
                            style: TextStyle(
                                fontSize: 11, color: AmoreTheme.textFaint),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    section('AOJIT'),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: AmoreTheme.cardBox(),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.bolt_rounded,
                            color: AmoreBrand.accent),
                        title: const Text('AOJIT 优化',
                            style: TextStyle(fontSize: 14.5)),
                        subtitle: Text(
                            Aojit.enabled ? '已开启：运行预录制镜像，不再逐条模拟指令' : '已关闭：全部按模拟方式执行',
                            style: const TextStyle(fontSize: 12)),
                        value: Aojit.enabled,
                        onChanged: (v) => setState(() => Aojit.setEnabled(v)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final c in Aojit.system)
                      _aojitCard(c),
                    _aojitGroup('Python 模块'),
                    for (final c in Aojit.pythonModules)
                      _aojitCard(c),
                    const SizedBox(height: 8),
                    Text(
                      '为下列库运行预先录制并编译好的 JIT 代码，不再逐条模拟指令。Shell 管道通常快 2-4 倍。切换后对新启动的命令生效。每个库只有一个镜像，录制自列出的版本：该版本全速运行。同一个库的其他版本中未改变的代码仍从镜像运行，其余部分模拟执行，因此也能获得部分提速。',
                      style: const TextStyle(
                          fontSize: 11, color: AmoreTheme.textFaint)),
                    const SizedBox(height: 16),
                    section('镜像源（沙盒包管理）'),
                    Container(
                      decoration: AmoreTheme.cardBox(),
                      child: Column(
                        children: [
                          _mirrorRow('Alpine APK', Mirrors.apkPresets, Mirrors.apk,
                              Mirrors.apkLabel(), 'rootfs.mirror_apk',
                              'rootfs.mirror_apk_custom'),
                          const Divider(height: 1),
                          _mirrorRow('Python pip', Mirrors.pipPresets, Mirrors.pip,
                              Mirrors.pipLabel(), 'rootfs.mirror_pip',
                              'rootfs.mirror_pip_custom'),
                          const Divider(height: 1),
                          _mirrorRow('Node.js npm', Mirrors.npmPresets, Mirrors.npm,
                              Mirrors.npmLabel(), 'rootfs.mirror_npm',
                              'rootfs.mirror_npm_custom'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '镜像源用于沙盒内安装软件包：apk（Alpine 包）、pip（Python 包）、npm（Node 包）。选择后立即生效，终端/编程环境安装包时使用。',
                      style: const TextStyle(
                          fontSize: 11, color: AmoreTheme.textFaint)),
                    const SizedBox(height: 16),
                    section('按类清理'),
                    for (final (name, sz, dir, desc) in items)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: AmoreTheme.cardBox(),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(name,
                              style: const TextStyle(fontSize: 14.5)),
                          subtitle: Text(desc,
                              style: const TextStyle(fontSize: 11.5)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_fmt(sz),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AmoreTheme.textSecondary)),
                              const SizedBox(width: 10),
                              if (sz > 0 && name != '配置/其他')
                                TextButton(
                                  style: TextButton.styleFrom(
                                      foregroundColor: AmoreTheme.danger,
                                      visualDensity:
                                          VisualDensity.compact),
                                  onPressed: () => _confirmClean(name, dir),
                                  child: const Text('清理'),
                                ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),
                    section('目录浏览（沙盒根）'),
                    Container(
                      decoration: AmoreTheme.cardBox(),
                      child: Column(
                        children: [
                          for (final e in _root)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                e.isDir
                                    ? Icons.folder_rounded
                                    : Icons.insert_drive_file_outlined,
                                size: 18,
                                color: e.isDir
                                    ? AmoreBrand.accent
                                    : AmoreTheme.textFaint,
                              ),
                              title: Text('${e.name}/',
                                  style: const TextStyle(fontSize: 12.5)),
                              trailing: Text(_fmt(e.size),
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AmoreTheme.textFaint)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_fsFooter,
                        style: const TextStyle(
                            fontSize: 10.5, color: AmoreTheme.textFaint)),
                  ],
                ),
        ),
      ),
    );
  }

  void _confirmClean(String name, Directory dir) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清理$name？'),
        content: const Text('该目录下文件将被删除，无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AmoreTheme.danger),
            onPressed: () {
              Navigator.pop(ctx);
              _clean(name, dir);
            },
            child: const Text('清理'),
          ),
        ],
      ),
    );
  }

  Widget _aojitGroup(String t) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AmoreTheme.textSecondary)),
      );

  Widget _aojitCard(AojitComponent c) {
    final ok = !c.partial;
    final badge = ok ? '可用' : '部分提速';
    final badgeColor = ok ? const Color(0xFF34C759) : AmoreBrand.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: AmoreTheme.cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.name,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withOpacity(0.5)),
                ),
                child: Text(badge,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: badgeColor,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(c.path,
              style: const TextStyle(
                  fontSize: 11, color: AmoreTheme.textFaint)),
          const SizedBox(height: 4),
          Text(c.desc,
              style: const TextStyle(
                  fontSize: 12, color: AmoreTheme.textSecondary)),
          const SizedBox(height: 6),
          Text('镜像录制自 ${c.mirror}',
              style: const TextStyle(
                  fontSize: 11, color: AmoreTheme.textFaint)),
          Text(
              c.fullSpeedNote ? '全速：已安装的正是录制时的版本。' : '已安装另一个版本：未改变的代码从镜像运行，其余部分模拟执行。',
              style: const TextStyle(
                  fontSize: 11, color: AmoreTheme.textFaint)),
          if (c.coverage.isNotEmpty)
            Text(c.coverage,
                style: const TextStyle(
                    fontSize: 11, color: AmoreTheme.textFaint)),
        ],
      ),
    );
  }

  Widget _mirrorRow(String title, List<MirrorPreset> presets, String current,
      String currentLabel, String key, String customKey) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 14.5)),
      subtitle: Text(
        current.isEmpty ? '未配置（默认源）' : currentLabel,
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: TextButton(
        onPressed: () => _pickMirror(title, presets, key, customKey),
        child: const Text('选择'),
      ),
    );
  }

  void _pickMirror(String title, List<MirrorPreset> presets, String key,
      String customKey) {
    final customCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('$title 镜像源'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in presets)
                  ListTile(
                    dense: true,
                    title: Text(p.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(p.url,
                        style: const TextStyle(fontSize: 10.5)),
                    trailing: const Icon(Icons.check_circle_outline_rounded,
                        size: 16, color: AmoreTheme.textFaint),
                    onTap: () {
                      Mirrors.select(key, customKey, p.url);
                      Navigator.pop(ctx);
                      _scan();
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('✓ $title 已切换到 ${p.name}')));
                    },
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextField(
                    controller: customCtl,
                    decoration: const InputDecoration(
                        labelText: '自定义镜像 URL',
                        hintText: 'https://mirrors.example.com/…'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final url = customCtl.text.trim();
                if (url.isEmpty) return;
                Mirrors.selectCustom(key, customKey, url);
                Navigator.pop(ctx);
                _scan();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('✓ $title 已使用自定义镜像')));
              },
              child: const Text('应用自定义'),
            ),
          ],
        ),
      ),
    );
  }

  Widget section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t, style: AmoreTheme.sectionLabel()),
      );
}

class _FsEntry {
  final String name;
  final int size;
  final bool isDir;
  _FsEntry(this.name, this.size, {this.isDir = false});
}