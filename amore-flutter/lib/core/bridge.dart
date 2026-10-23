import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

/// AmoreBridge — Dart ↔ Rust Core 的 FFI JSON 总线客户端。
///
/// Rust Core 以静态库形式链进 App 二进制（iOS: libamore_core.a → Runner），
/// 因此用 [DynamicLibrary.process] 按符号名查找 `amore_call` / `amore_free`。
/// 每次调用传 method + payload(JSON)，返回统一信封 { ok, data | error }。
class AmoreBridge {
  AmoreBridge._();

  /// 数据目录（core_panic 自愈时用于重新 init）
  static String dataDir = '';

  static bool _ready = false;
  static late final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>) _call;
  static late final void Function(Pointer<Utf8>) _free;

  static void ensure() {
    if (_ready) return;
    final lib = DynamicLibrary.process();
    _call = lib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>>(
            'amore_call')
        .asFunction();
    _free = lib
        .lookup<NativeFunction<Void Function(Pointer<Utf8>)>>('amore_free')
        .asFunction();
    _ready = true;
  }

  /// 同步调用 Rust Core。payload 可省略（默认 {}）。
  /// 返回 data 部分；失败抛 [AmoreCoreError]。
  /// 遇到 core_panic 时自动重新初始化 Core 并重试一次（防止一次性失败锁死 App）。
  static Map<String, dynamic> call(String method,
      [Map<String, dynamic>? payload]) {
    try {
      return _callRaw(method, payload);
    } on AmoreCoreError catch (e) {
      if (e.code == 'core_panic' &&
          method != 'core.init' &&
          dataDir.isNotEmpty) {
        try {
          _callRaw('core.init', {'data_dir': dataDir});
        } catch (_) {}
        return _callRaw(method, payload);
      }
      rethrow;
    }
  }

  static Map<String, dynamic> _callRaw(String method,
      [Map<String, dynamic>? payload]) {
    ensure();

    final Pointer<Utf8> m = method.toNativeUtf8();
    final Pointer<Utf8> p =
        jsonEncode(payload ?? <String, dynamic>{}).toNativeUtf8();
    Pointer<Utf8> out = Pointer.fromAddress(0);
    try {
      out = _call(m, p);
      if (out.address == 0) {
        throw const AmoreCoreError('null_response', 'Rust Core 返回空指针');
      }
      final String raw = out.toDartString();
      final Map<String, dynamic> envelope =
          jsonDecode(raw) as Map<String, dynamic>;
      if (envelope['ok'] == true) {
        final d = envelope['data'];
        return d is Map<String, dynamic> ? d : <String, dynamic>{'value': d};
      }
      final err = envelope['error'] as Map<String, dynamic>? ?? const {};
      throw AmoreCoreError(
        (err['code'] as String?) ?? 'unknown',
        (err['message'] as String?) ?? '未知错误',
      );
    } finally {
      if (out.address != 0) _free(out);
      calloc.free(m);
      calloc.free(p);
    }
  }

  /// 便捷方法：core.version
  static Map<String, dynamic> coreVersion() => call('core.version');

  /// 便捷方法：core.ping（往返测试）
  static Map<String, dynamic> ping(Object echo) =>
      call('core.ping', {'echo': echo});
}

class AmoreCoreError implements Exception {
  final String code;
  final String message;
  const AmoreCoreError(this.code, this.message);

  @override
  String toString() => 'AmoreCoreError($code): $message';
}

/// 当前宿主平台描述（自检页用）
String hostPlatformLabel() {
  if (Platform.isIOS) return 'iOS (${Platform.operatingSystemVersion})';
  if (Platform.isMacOS) return 'macOS (${Platform.operatingSystemVersion})';
  return Platform.operatingSystem;
}
