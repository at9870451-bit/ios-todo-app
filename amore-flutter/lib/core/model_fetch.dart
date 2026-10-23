// 从已配置的 API 接口读取模型列表（OpenAI /v1/models 兼容 + Gemini + Anthropic）
import 'package:dio/dio.dart';

import 'models.dart';
import 'store.dart';

class ModelFetch {
  ModelFetch._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 40),
    validateStatus: (s) => s != null && s < 500,
  ));

  /// 生效的 Base（用户填写优先，否则厂商官方默认）
  static String baseOf(AIProvider p) {
    final b = p.baseURL.trim();
    if (b.isNotEmpty) return b;
    for (final v in AmoreStore.vendors()) {
      if (v.key == p.vendor) return v.base;
    }
    return '';
  }

  /// 候选模型端点（按优先级）
  static List<String> endpoints(AIProvider p) {
    var base = baseOf(p).trim();
    if (base.isEmpty) return const [];
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    // 容错：误填了 completions / responses 后缀
    base = base.replaceAll(RegExp(r'/chat/completions$'), '');
    base = base.replaceAll(RegExp(r'/responses$'), '');
    base = base.replaceAll(RegExp(r'/completions$'), '');

    final isGemini = p.vendor == 'google' ||
        p.vendor == 'gemini_generic' ||
        base.contains('generativelanguage.googleapis.com');
    final out = <String>[];
    if (isGemini) {
      if (base.endsWith('/models')) {
        out.add(base);
      } else if (base.endsWith('/v1beta') || base.endsWith('/v1')) {
        out.add('$base/models');
      } else {
        out.add('$base/v1beta/models');
      }
    } else if (base.endsWith('/v1') || base.endsWith('/v1beta')) {
      out.add('$base/models');
    } else if (base.contains('/v1/')) {
      final i = base.indexOf('/v1/');
      out.add('${base.substring(0, i)}/v1/models');
    } else if (base.endsWith('/models')) {
      out.add(base);
    } else {
      out.add('$base/v1/models');
      out.add('$base/models');
    }
    return out;
  }

  static Map<String, String> headers(AIProvider p) {
    final k = p.apiKey.trim();
    return {
      'Content-Type': 'application/json',
      if (k.isNotEmpty) 'Authorization': 'Bearer $k',
      if (k.isNotEmpty) 'x-api-key': k, // Anthropic
      'anthropic-version': '2023-06-01', // Anthropic 需要；其他服务忽略
    };
  }

  /// 读取接口模型列表；所有候选端点失败则抛异常
  static Future<List<String>> fetch(AIProvider p) async {
    final urls = endpoints(p);
    if (urls.isEmpty) {
      throw Exception('请先填写 Base URL 或选择厂商');
    }
    Object? lastErr;
    final k = p.apiKey.trim();
    final isGeminiVendor = p.vendor == 'google' || p.vendor == 'gemini_generic';
    for (final url in urls) {
      try {
        var full = url;
        if ((isGeminiVendor || url.contains('generativelanguage')) &&
            k.isNotEmpty &&
            !url.contains('key=')) {
          full = '$url?key=${Uri.encodeQueryComponent(k)}';
        }
        final resp = await _dio.get(full, options: Options(headers: headers(p)));
        if (resp.statusCode == 200) {
          final list = parse(resp.data);
          if (list.isNotEmpty) return list;
          lastErr = Exception('接口返回中没有模型字段');
        } else {
          lastErr = Exception('HTTP ${resp.statusCode}');
        }
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('$lastErr');
  }

  /// 解析多种返回格式（OpenAI data[].id / Gemini models[].name / 纯数组）
  static List<String> parse(dynamic data) {
    final out = <String>{};

    void take(dynamic list) {
      if (list is! List) return;
      for (final m in list) {
        if (m is String) {
          if (m.trim().isNotEmpty) out.add(m.trim());
        } else if (m is Map) {
          final id = m['id'] ?? m['name'] ?? m['model'] ?? m['model_name'];
          if (id != null) {
            var s = id.toString().trim();
            if (s.startsWith('models/')) s = s.substring(7);
            if (s.isNotEmpty) out.add(s);
          }
        }
      }
    }

    if (data is Map) {
      take(data['data']);
      take(data['models']);
      take(data['result']);
      final nested = data['data'];
      if (nested is Map) {
        take(nested['models']);
        take(nested['data']);
      }
    } else if (data is List) {
      take(data);
    }
    final list = out.toList()..sort();
    return list;
  }
}