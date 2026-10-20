// 对应 Swift：ConversationListView.swift —— 历史会话（服务端同步）
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../core/store.dart';
import '../core/theme.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _sessions = [];
  String? _error;

  String get _server {
    final url = AmoreStore.getConfig('server_url') ?? 'http://154.12.16.204:8080';
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String? get _token => AmoreStore.getConfig('auth_token');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_token == null || _token!.isEmpty) {
      setState(() => _error = '未登录');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await Dio().get('$_server/api/ios/conversations',
          options: Options(headers: {'Authorization': 'Bearer $_token'}));
      if (resp.statusCode == 200 && resp.data is Map) {
        setState(() => _sessions = List<Map<String, dynamic>>.from(
            (resp.data['data']?['list'] as List?) ?? []));
      } else {
        setState(() => _error = '服务返回 ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final userCtl = TextEditingController();
    final passCtl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('登录服务器账号',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(controller: userCtl, decoration: const InputDecoration(hintText: '用户名')),
            const SizedBox(height: 10),
            TextField(
                controller: passCtl,
                obscureText: true,
                decoration: const InputDecoration(hintText: '密码')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  try {
                    final resp = await Dio().post('$_server/api/ios/auth/login', data: {
                      'username': userCtl.text.trim(),
                      'password': passCtl.text,
                    });
                    final token = resp.data['data']?['token']?.toString() ?? '';
                    if (token.isNotEmpty) {
                      AmoreStore.setConfig('auth_token', token);
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      _load();
                    } else {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('登录失败：无返回 token')));
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('登录失败：${e.toString().substring(0, e.toString().length.clamp(0, 80))}')));
                  }
                },
                child: const Text('登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('历史会话', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
      body: Container(
        decoration: AmoreTheme.pageGradient(),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AmoreTheme.accent))
              : (_error == '未登录' || _token == null || _token!.isEmpty)
                  ? _notLoggedIn()
                  : _error != null
                      ? _errorView()
                      : _sessions.isEmpty
                          ? _empty()
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _sessions.length,
                              itemBuilder: (_, i) {
                                final s = _sessions[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(14),
                                  decoration: AmoreTheme.cardBox(),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s['title']?.toString() ?? '会话',
                                          style: const TextStyle(
                                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text(s['updated_at']?.toString() ?? '',
                                          style: const TextStyle(
                                              fontSize: 11, color: AmoreTheme.textFaint)),
                                    ],
                                  ),
                                );
                              },
                            ),
        ),
      ),
    );
  }

  Widget _notLoggedIn() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: AmoreTheme.textFaint),
            const SizedBox(height: 14),
            const Text('登录后同步云端会话',
                style: TextStyle(color: AmoreTheme.textSecondary, fontSize: 14.5)),
            const SizedBox(height: 6),
            const Text('群聊会话不参与同步（已排除）',
                style: TextStyle(color: AmoreTheme.textFaint, fontSize: 12)),
            const SizedBox(height: 18),
            FilledButton(onPressed: _login, child: const Text('登录服务器账号')),
          ],
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 52, color: AmoreTheme.warn),
              const SizedBox(height: 14),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: AmoreTheme.textSecondary)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open_rounded, size: 52, color: AmoreTheme.textFaint),
            const SizedBox(height: 14),
            const Text('服务器上还没有会话记录',
                style: TextStyle(color: AmoreTheme.textSecondary, fontSize: 14)),
          ],
        ),
      );
}
