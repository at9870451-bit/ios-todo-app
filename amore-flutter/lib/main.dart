import 'package:flutter/material.dart';

import 'core/bridge.dart';

void main() {
  runApp(const AmoreApp());
}

class AmoreApp extends StatelessWidget {
  const AmoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6C8CFF);
    return MaterialApp(
      title: 'Amore',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
      ),
      home: const BootstrapPage(),
    );
  }
}

/// M0 自检页：验证 Flutter UI ↔ FFI 桥 ↔ Rust Core 全链路。
class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  Map<String, dynamic>? _version;
  Map<String, dynamic>? _sysinfo;
  String? _pingEcho;
  String? _error;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runChecks());
  }

  Future<void> _runChecks() async {
    try {
      final v = AmoreBridge.coreVersion();
      final s = AmoreBridge.call('core.sysinfo');
      final p = AmoreBridge.ping({
        'from': 'flutter',
        'platform': hostPlatformLabel(),
        'ts': DateTime.now().toIso8601String(),
      });
      if (!mounted) return;
      setState(() {
        _version = v;
        _sysinfo = s;
        _pingEcho = p['echo'].toString();
        _error = null;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final okAll = !_running && _error == null;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -1.0),
            radius: 1.4,
            colors: [Color(0xFF1A2238), Color(0xFF0B0E14)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            children: [
              const Text('Amore',
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text('Flutter + Rust Core · 重构版 4.0',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.55), fontSize: 14)),
              const SizedBox(height: 22),
              _StatusCard(
                title: '桥接链路',
                loading: _running,
                ok: okAll,
                detail: _running
                    ? '正在自检…'
                    : (okAll
                        ? 'Dart FFI ↔ C ABI ↔ Rust JSON 总线 全部连通'
                        : (_error ?? '失败')),
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: 'Rust Core 版本',
                child: _version == null
                    ? const Text('—',
                        style: TextStyle(color: Colors.white38))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kv('名称', '${_version!['name']}'),
                          _kv('版本', 'v${_version!['version']}'),
                          _kv('API', '${_version!['api']}'),
                          _kv('平台',
                              '${_version!['platform']} / ${_version!['arch']}'),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: '运行时信息',
                child: _sysinfo == null
                    ? const Text('—',
                        style: TextStyle(color: Colors.white38))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kv('宿主', hostPlatformLabel()),
                          _kv('构建模式', '${_sysinfo!['build_mode']}'),
                          _kv('里程碑', '${_sysinfo!['milestone']}'),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              _InfoCard(
                title: '往返回声（core.ping）',
                child: Text(_pingEcho ?? '—',
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5)),
              ),
              const SizedBox(height: 24),
              Text(
                okAll
                    ? 'M0 骨架就绪：后续里程碑将在同一 Rust Core 上逐步构建存储层、聊天引擎与群聊。'
                    : '自检未通过：请检查 CI 构建日志（-force_load / 架构目标）。',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 12.5,
                    height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Text(k,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.45), fontSize: 13)),
            ),
            Expanded(
                child: Text(v, style: const TextStyle(fontSize: 13.5))),
          ],
        ),
      );
}

class _StatusCard extends StatelessWidget {
  final String title;
  final bool loading;
  final bool ok;
  final String detail;

  const _StatusCard(
      {required this.title,
      required this.loading,
      required this.ok,
      required this.detail});

  @override
  Widget build(BuildContext context) {
    final color = loading
        ? const Color(0xFFFFC44D)
        : (ok ? const Color(0xFF4ADE80) : const Color(0xFFF87171));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141A29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(
                loading
                    ? Icons.hourglass_top_rounded
                    : (ok
                        ? Icons.check_rounded
                        : Icons.close_rounded),
                color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(detail,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141A29),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 12.5,
                  letterSpacing: 0.4)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
