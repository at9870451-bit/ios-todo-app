// MCP 客户端：Model Context Protocol over HTTP（JSON-RPC 2.0）
// 支持 tools/list（拉取工具目录）与 tools/call（执行工具）；
// 服务器 URL 为 HTTP JSON-RPC 端点（如 http://host:port/mcp）。
import 'dart:convert';

import 'package:dio/dio.dart';

import 'store.dart';
import 'tools_config.dart';

/// MCP 服务配置（存 Rust config：skills.mcp 数组）
class McpService {
  String id;
  String name;
  String url;
  String token; // 可选 Bearer
  bool enabled;

  McpService({
    this.id = '',
    this.name = '',
    this.url = '',
    this.token = '',
    this.enabled = true,
  });

  factory McpService.fromJson(Map<String, dynamic> j) => McpService(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
        token: j['token']?.toString() ?? '',
        enabled: j['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id.isEmpty ? 'mcp_${DateTime.now().millisecondsSinceEpoch}' : id,
        'name': name,
        'url': url,
        'token': token,
        'enabled': enabled,
      };
}

/// MCP 工具目录项
class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const McpTool({
    required this.name,
    this.description = '',
    this.inputSchema = const {},
  });

  factory McpTool.fromJson(Map<String, dynamic> j) => McpTool(
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        inputSchema: j['inputSchema'] is Map
            ? Map<String, dynamic>.from(j['inputSchema'] as Map)
            : j['input_schema'] is Map
                ? Map<String, dynamic>.from(j['input_schema'] as Map)
                : const {},
      );
}

/// 从 config 读取 MCP 服务列表
List<McpService> mcpServices() {
  final raw = AmoreStore.getConfig('skills.mcp') ?? '';
  if (raw.trim().isEmpty) return [];
  try {
    final list = (jsonDecode(raw) as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => McpService.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  } catch (_) {
    return [];
  }
}

/// 保存 MCP 服务列表（带基础 JSON 序列化）
void saveMcpServices(List<McpService> list) {
  AmoreStore.setConfig('skills.mcp', jsonEncode(list.map((e) => e.toJson()).toList()));
}

/// 启用的 MCP 服务（用于工具注入）
List<McpService> enabledMcpServices() =>
    mcpServices().where((s) => s.enabled).toList();

/// MCP 客户端（每服务一个实例；轻量、无连接池）
class McpClient {
  final McpService service;
  late final Dio _dio;

  McpClient(this.service) {
    final t = ToolsConfig.mcpTimeout; // MCP 启动超时（秒，可在工具与权限页调整）
    _dio = Dio(BaseOptions(
      connectTimeout: Duration(seconds: t),
      receiveTimeout: Duration(seconds: t.clamp(10, 300)),
      validateStatus: (s) => s != null && s < 500,
      headers: {
        'Content-Type': 'application/json',
        if (service.token.isNotEmpty)
          'Authorization': 'Bearer ${service.token}',
      },
    ));
  }

  int _id = 0;

  Future<Map<String, dynamic>> _rpc(String method, Map<String, dynamic> params) async {
    final url = service.url.trim();
    if (url.isEmpty) {
      throw Exception('MCP 服务「${service.name}」缺少 URL');
    }
    final resp = await _dio.post<Map<String, dynamic>>(
      url,
      data: {'jsonrpc': '2.0', 'id': ++_id, 'method': method, 'params': params},
    );
    final data = resp.data;
    if (data == null) throw Exception('MCP 无响应（HTTP ${resp.statusCode}）');
    if (data['error'] != null) {
      final e = data['error'];
      final msg = e is Map ? (e['message'] ?? 'unknown').toString() : e.toString();
      throw Exception('MCP ${method.split('.').last} 失败：$msg');
    }
    return data['result'] is Map
        ? Map<String, dynamic>.from(data['result'] as Map)
        : <String, dynamic>{};
  }

  /// 拉取工具目录（先试直接 tools/list，失败则 initialize 握手后重试）
  Future<List<McpTool>> listTools() async {
    try {
      return _parseTools(await _rpc('tools/list', {}));
    } catch (e) {
      // 需要 initialize 握手（新版 MCP 服务器）
      await _rpc('initialize', {
        'protocolVersion': '2024-11-05',
        'clientInfo': {'name': 'amore', 'version': '4.0'},
        'capabilities': {},
      });
      return _parseTools(await _rpc('tools/list', {}));
    }
  }

  List<McpTool> _parseTools(Map<String, dynamic> result) {
    final list = result['tools'] as List? ?? const [];
    return list
        .whereType<Map>()
        .map((e) => McpTool.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 执行工具：返回文本结果（content[].text 拼接）
  Future<String> callTool(String name, Map<String, dynamic> args) async {
    final result = await _rpc('tools/call', {
      'name': name,
      'arguments': args,
    });
    if (result['isError'] == true) {
      final parts = (result['content'] as List?) ?? const [];
      throw Exception('MCP 工具 $name 返回错误：${_contentText(parts)}');
    }
    final parts = (result['content'] as List?) ?? const [];
    return _contentText(parts);
  }

  String _contentText(List<dynamic> parts) {
    final buf = <String>[];
    for (final p in parts) {
      if (p is Map) {
        final t = (p['text'] ?? '').toString();
        if (t.isNotEmpty) buf.add(t);
      }
    }
    return buf.join('\n');
  }
}
