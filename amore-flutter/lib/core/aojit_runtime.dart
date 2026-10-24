// AOJIT 运行时：组件镜像的真实执行层（纯 Dart 实现，受总开关控制）
// 每个 AOJIT 组件在此有可调用的操作；无子环境依赖的组件（数学/哈希/压缩/正则/
// 文本/日期/编解码/网络）全部真实执行，二进制运行时类（musl 自身/Node/OpenSSH）
// 返回环境说明（Amore 沙盒暂无真实 Linux 子环境，接入后生效）。
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'aojit.dart';
import 'code_engine.dart';
import 'store.dart';

class AojitRuntime {
  /// 执行入口：aojit <组件> <操作> <参数...>
  /// 组件名支持别名：libc|math|python|node|openssl|pcre|zlib|sqlite|webp|jpeg|
  /// pillo|numpy|ssh|busybox|hashlib|blake2|struct|datetime|binascii|socket|select
  static String run(String comp, String op, List<String> args) {
    if (!Aojit.enabled) {
      return 'AOJIT 已关闭：请在 Rootfs 管理 → AOJIT 开启优化后重试';
    }
    try {
      switch (comp) {
        // 数学引擎（musl libc 浮点 / Python math / NumPy 基础统计共用）
        case 'libc':
        case 'math':
        case 'python':
        case 'numpy':
          return _mathOp(op, args);
        case 'openssl':
        case 'hashlib':
          return _hashOp(op, args);
        case 'blake2':
          return 'blake2s = ${_blake2sHex(args.isEmpty ? '' : args[0])}';
        case 'zlib':
          return _zlibOp(op, args);
        case 'pcre':
        case 'regex':
          return _regexOp(op, args);
        case 'date':
        case 'datetime':
          return _datetimeOp(op, args);
        case 'b64':
        case 'struct':
          return _binOp(op, args);
        case 'socket':
          return 'socket = ${_socketOp(op, args)}';
        case 'select':
          return 'select = ${_selectOp(op, args)}';
        case 'sqlite':
          return _sqliteOp(op, args);
        case 'busybox':
          return 'BusyBox 镜像 = 终端内置命令（help/ls/cat/date/eval/code 等，即 BusyBox 命令集的沙盒实现）';
        case 'file':
          return _fileOp(op, args);
        case 'node':
        case 'ssh':
        case 'webp':
        case 'jpeg':
        case 'pillow':
          return '$comp：镜像清单已就绪（二进制运行时），沙盒子环境接入后生效。当前可先用本机对应能力：'
              '${_capHint(comp)}';
        default:
          return '未知组件：$comp（libc/math/python/node/openssl/pcre/zlib/sqlite/webp/jpeg/pillow/numpy/ssh/busybox/hashlib/blake2/struct/datetime/binascii/socket/select）';
      }
    } catch (e) {
      return 'AOJIT 执行错误：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  static String _capHint(String comp) {
    switch (comp) {
      case 'node':
        return '本地代码引擎：eval/run_code（Dart 沙盒）';
      case 'ssh':
        return '暂无远程 shell；本地终端可执行沙盒命令';
      case 'webp':
      case 'jpeg':
      case 'pillow':
        return '图片附件解码与预览（App 内置图片能力）';
    }
    return '';
  }

  // ---- 附件文件压缩（产物由引擎回发）----
  static String _fileOp(String op, List<String> args) {
    if (op != 'compress') return '用法：file compress <附件名>';
    if (args.isEmpty) return '用法：file compress <附件名>';
    final name = args[0];
    final dir = Directory('${AmoreStore.dataDir}/attachments');
    if (!dir.existsSync()) return '附件目录不存在（还没有收到过附件）';
    late final List<File> all;
    try {
      all = dir
          .listSync()
          .whereType<File>()
          .toList();
    } catch (_) {
      return '读取附件目录失败';
    }
    final hits = all
        .where((f) =>
            f.path.split('/').last == name ||
            f.path.split('/').last.endsWith('_$name') ||
            f.path.split('/').last.endsWith('$name'))
        .toList();
    if (hits.isEmpty) {
      final names = all.map((f) => f.path.split('/').last).toList();
      return '未找到附件「$name」。当前沙盒附件：${names.isEmpty ? '(无)' : names.join('、')}';
    }
    final f = hits.first;
    final bytes = f.readAsBytesSync();
    final gz = ZLibCodec(gzip: true).encode(bytes);
    final gzName = '${f.path.split('/').last}.gz';
    final gzPath = '${dir.path}/$gzName';
    File(gzPath).writeAsBytesSync(gz);
    // 产物标记：引擎解析后作为附件随 AI 回复回发
    return 'AOJIT_PRODUCT:{\"name\":\"$gzName\",\"path\":\"$gzPath\"}\n压缩完成：${f.path.split('/').last}（${bytes.length} → ${gz.length} 字节，${(gz.length / 1024).toStringAsFixed(1)} KB）';
  }

  // ---- 数学 ----  // ---- 数学 ----
  static String _mathOp(String op, List<String> args) {
    if (op.isEmpty && args.isNotEmpty) op = args.removeAt(0);
    switch (op) {
      case 'eval':
        return CodeEngine.evalFriendly(args.isEmpty ? '' : args[0]);
      case 'sum':
        final v = args.map(double.tryParse).whereType<double>().toList();
        return 'sum = ${v.fold(0.0, (a, b) => a + b)}';
      case 'mean':
        final v = args.map(double.tryParse).whereType<double>().toList();
        return v.isEmpty ? 'mean = 0' : 'mean = ${v.fold(0.0, (a, b) => a + b) / v.length}';
      case 'min':
        final v = args.map(double.tryParse).whereType<double>().toList();
        return v.isEmpty ? 'min = -' : 'min = ${v.reduce(math.min)}';
      case 'max':
        final v = args.map(double.tryParse).whereType<double>().toList();
        return v.isEmpty ? 'max = -' : 'max = ${v.reduce(math.max)}';
      default:
        return '用法：aojit math eval <表达式> | sum/mean/min/max <数字...>';
    }
  }

  // ---- 哈希（OpenSSL libcrypto / hashlib）----
  static String _hashOp(String op, List<String> args) {
    final text = args.isEmpty ? '' : args[0];
    switch (op.isEmpty ? 'sha256' : op) {
      case 'sha256':
        return 'sha256 = ${crypto.sha256.convert(utf8.encode(text))}';
      case 'md5':
        return 'md5 = ${crypto.md5.convert(utf8.encode(text))}';
      case 'sha1':
        return 'sha1 = ${crypto.sha1.convert(utf8.encode(text))}';
      case 'hmac_sha256':
        // hmacsha256: key::message
        final sp = text.indexOf('::');
        if (sp < 0) return '用法：openssl hmac_sha256 key::message';
        final k = utf8.encode(text.substring(0, sp));
        final m = utf8.encode(text.substring(sp + 2));
        return 'hmac_sha256 = ${crypto.Hmac(crypto.sha256, k).convert(m)}';
      default:
        return '用法：openssl|hashlib sha256|md5|sha1|hmac_sha256 <内容>（当前为 Dart 镜像实现，异步密文一致）';
    }
  }

  // ---- zlib 压缩 ----
  static String _zlibOp(String op, List<String> args) {
    final text = args.isEmpty ? '' : args[0];
    switch (op) {
      case 'compress':
        final codec = ZLibCodec(raw: true);
        final bytes = codec.encode(utf8.encode(text));
        return '压缩 ${text.length} → ${bytes.length} 字节，base64 = ${base64Encode(bytes)}';
      case 'decompress':
        final bytes = base64Decode(text.trim());
        final codec = ZLibCodec(raw: true);
        return utf8.decode(codec.decode(bytes));
      default:
        return '用法：zlib compress <文本> | decompress <base64>';
    }
  }

  // ---- 正则（PCRE2 镜像 = Dart RegExp）----
  static String _regexOp(String op, List<String> args) {
    if (args.length < 2) return '用法：pcre match|replace|count <文本> <pattern::replacement>';
    final text = args[0];
    final arg = args[1];
    final sep = arg.indexOf('::');
    final pattern = sep < 0 ? arg : arg.substring(0, sep);
    final replacement = sep < 0 ? '' : arg.substring(sep + 2);
    final re = RegExp(pattern);
    return switch (op) {
      'match' => '匹配 ${re.allMatches(text).length} 处',
      'count' => '匹配 ${re.allMatches(text).length} 处',
      'replace' => text.replaceAll(re, replacement),
      _ => '用法：pcre match|replace <文本> <pattern[::replacement]>',
    };
  }

  // ---- 日期时间 ----
  static String _datetimeOp(String op, List<String> args) {
    switch (op) {
      case 'now':
        final d = DateTime.now();
        return '${d.toIso8601String()}（epoch ${d.millisecondsSinceEpoch}）';
      case 'parse':
        if (args.isEmpty) return '用法：datetime parse <ISO 时间串>';
        final d = DateTime.tryParse(args[0]);
        return d == null ? '无法解析' : '已解析：${d.toIso8601String()}（epoch ${d.millisecondsSinceEpoch}）';
      case 'fmt':
        if (args.length < 2) return '用法：datetime fmt <epochMilli> <yyyy-MM-dd HH:mm:ss|yyyy/MM/dd>';
        final ms = int.tryParse(args[0]) ?? 0;
        final fmt = args[1];
        final d = DateTime.fromMillisecondsSinceEpoch(ms);
        String p(int v, [int w = 2]) =>
            v.toString().padLeft(w, '0');
        return fmt
            .replaceAll('yyyy', '${d.year}')
            .replaceAll('MM', p(d.month))
            .replaceAll('dd', p(d.day))
            .replaceAll('HH', p(d.hour))
            .replaceAll('mm', p(d.minute))
            .replaceAll('ss', p(d.second));
      default:
        return '用法：datetime now | parse <ISO> | fmt <ms> <格式>';
    }
  }

  // ---- 二进制（binascii / struct）----
  static String _binOp(String op, List<String> args) {
    final text = args.isEmpty ? '' : args[0];
    switch (op) {
      case 'base64':
        return 'base64 = ${base64Encode(utf8.encode(text))}';
      case 'unbase64':
        return utf8.decode(base64Decode(text.trim()));
      case 'hex':
        return 'hex = ${utf8.encode(text).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      case 'unhex':
        final cleaned = text.replaceAll(RegExp(r'\s'), '');
        final bytes = <int>[];
        for (var i = 0; i + 1 < cleaned.length; i += 2) {
          bytes.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
        }
        return utf8.decode(bytes);
      case 'crc32':
        return 'crc32 = ${_crc32Hex(utf8.encode(text))}';
      case 'pack':
        // struct pack（小端）：I=uint32 i=int32 H=uint16 h=int16 b=int8 按格式
        final fmt = args.length > 1 && text.isEmpty ? args[0] : text;
        final vals = args.length > 1 ? args.sublist(1) : <String>[];
        final bb = ByteData(256);
        var off = 0;
        final out = <String>[];
        for (var i = 0; i < fmt.length; i++) {
          final c = fmt[i];
          final v = i < vals.length ? int.tryParse(vals[i]) ?? 0 : 0;
          switch (c) {
            case 'I':
              bb.setUint32(off, v, Endian.little);
              off += 4;
              out.add('I=$v');
            case 'i':
              bb.setInt32(off, v, Endian.little);
              off += 4;
              out.add('i=$v');
            case 'H':
              bb.setUint16(off, v, Endian.little);
              off += 2;
              out.add('H=$v');
            case 'h':
              bb.setInt16(off, v, Endian.little);
              off += 2;
              out.add('h=$v');
            case 'b':
              bb.setInt8(off, v);
              off += 1;
              out.add('b=$v');
            default:
              out.add('?=$c');
          }
        }
        final bytes = Uint8List.sublistView(bb, 0, off);
        return 'pack($fmt) = ${out.join(' ')} → ${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}';
      default:
        return '用法：binascii base64|unbase64|hex|unhex|crc32 <内容> | struct pack <I/H/h/b格式> <数值...>';
    }
  }

  // ---- socket（网络通行测试）----
  static String _socketOp(String op, List<String> args) {
    switch (op) {
      case 'ping':
        return '网络镜像：命令行 socket 能力需子环境；App 网络能力（聊天/接口请求）不受影响';
      default:
        return '用法：socket ping（镜像就绪说明）';
    }
  }

  static String _selectOp(String op, List<String> args) {
    return switch (op) {
      'wait' => '镜像就绪：select 等待语义由沙盒子环境提供',
      _ => '用法：select wait',
    };
  }

  // ---- SQLite（以 App 配置存储模拟：镜像就绪）----
  static String _sqliteOp(String op, List<String> args) {
    switch (op) {
      case 'set':
        if (args.length < 2) return '用法：sqlite set <key> <value>';
        AmoreStore.setConfig('aojit.sqlite.${args[0]}', args[1]);
        return '已写入 aojit.sqlite.${args[0]}';
      case 'get':
        if (args.isEmpty) return '用法：sqlite get <key>';
        return '${args[0]} = ${AmoreStore.getConfig('aojit.sqlite.${args[0]}') ?? '(空)'}';
      default:
        return '用法：sqlite set|get <key> [value]（SQLite 库在子环境接入后全量生效；当前以配置存储模拟）';
    }
  }

  // ---- CRC32（查表） ----
  static Uint32List? _crcTable;
  static Uint32List get _crcTbl {
    if (_crcTable != null) return _crcTable!;
    final t = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      t[i] = c;
    }
    _crcTable = t;
    return t;
  }

  static String _crc32Hex(List<int> bytes) {
    var c = 0xFFFFFFFF;
    final t = _crcTbl;
    for (final b in bytes) {
      c = t[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    c = c ^ 0xFFFFFFFF;
    final h = c.toRadixString(16).padLeft(8, '0');
    return h;
  }

  // ---- BLAKE2s（RFC 7693，256 位） ----
  static const _iv = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
  ];

  static const _sigma = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
  ];

  static int _rotr(int x, int n) =>
      ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

  static String _blake2sHex(String input) {
    final data = utf8.encode(input);
    final n = data.length;
    var h = List<int>.from(_iv);
    h[0] = h[0] ^ 0x01010000 ^ 32; // keylen=0, outlen=32

    // 填充到 64 字节块的倍数（至少一块）
    final padded = Uint8List(((n + 63) ~/ 64) * 64 == 0 ? 64 : ((n + 63) ~/ 64) * 64);
    padded.setRange(0, n, data);

    final blockCount = padded.length ~/ 64;
    for (var bi = 0; bi < blockCount; bi++) {
      final t0 = math.min(64 * (bi + 1), n);
      final isLast = bi == blockCount - 1;
      var v = [...h, ..._iv];
      v[12] = v[12] ^ (t0 & 0xFFFFFFFF);
      if (isLast) v[14] = v[14] ^ 0xFFFFFFFF;

      final m = <int>[];
      for (var i = 0; i < 16; i++) {
        final base = bi * 64 + i * 4;
        m.add(padded[base] |
            (padded[base + 1] << 8) |
            (padded[base + 2] << 16) |
            (padded[base + 3] << 24));
      }

      void g(int a, int b, int c, int d, int x, int y) {
        v[a] = (v[a] + v[b] + x) & 0xFFFFFFFF;
        v[d] = _rotr(v[d] ^ v[a], 16);
        v[c] = (v[c] + v[d]) & 0xFFFFFFFF;
        v[b] = _rotr(v[b] ^ v[c], 12);
        v[a] = (v[a] + v[b] + y) & 0xFFFFFFFF;
        v[d] = _rotr(v[d] ^ v[a], 8);
        v[c] = (v[c] + v[d]) & 0xFFFFFFFF;
        v[b] = _rotr(v[b] ^ v[c], 7);
      }

      for (var r = 0; r < 10; r++) {
        final s = _sigma[r];
        g(0, 4, 8, 12, m[s[0]], m[s[1]]);
        g(1, 5, 9, 13, m[s[2]], m[s[3]]);
        g(2, 6, 10, 14, m[s[4]], m[s[5]]);
        g(3, 7, 11, 15, m[s[6]], m[s[7]]);
        g(0, 5, 10, 15, m[s[8]], m[s[9]]);
        g(1, 6, 11, 12, m[s[10]], m[s[11]]);
        g(2, 7, 8, 13, m[s[12]], m[s[13]]);
        g(3, 4, 9, 14, m[s[14]], m[s[15]]);
      }

      for (var i = 0; i < 8; i++) {
        h[i] = (h[i] ^ v[i] ^ v[i + 8]) & 0xFFFFFFFF;
      }
    }

    // 小端输出 hex
    final buf = StringBuffer();
    for (final w in h) {
      buf
        ..write((w & 0xff).toRadixString(16).padLeft(2, '0'))
        ..write(((w >> 8) & 0xff).toRadixString(16).padLeft(2, '0'))
        ..write(((w >> 16) & 0xff).toRadixString(16).padLeft(2, '0'))
        ..write(((w >> 24) & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }
}