// 本地代码引擎：AI/终端共用的确定性内置计算能力（纯 Dart，无 IO/网络沙盒）
// 支持：数学表达式求值、base64、URL 编解码、JSON 格式化、正则替换、文本统计
import 'dart:convert';
import 'dart:math' as math;

class CodeEngine {
  /// 统一入口：op + input + 可选参数 → 结果文本
  static String run(String op, String input, [String? arg]) {
    switch (op) {
      case 'eval':
        return '= ${evalExpr(input)}';
      case 'base64':
        return arg == 'decode' ? utf8.decode(base64Decode(input)) : base64Encode(utf8.encode(input));
      case 'url':
        return arg == 'decode' ? Uri.decodeComponent(input) : Uri.encodeComponent(input);
      case 'json':
        return jsonFormat(input);
      case 'regex':
        return regexOp(input, arg ?? '');
      case 'stats':
        return textStats(input);
      default:
        throw Exception('未知代码操作：$op（eval/base64/url/json/regex/stats）');
    }
  }

  // ---- 数学表达式求值（递归下降解析器）----

  static double evalExpr(String expr) {
    final tokens = _tokenize(expr);
    if (tokens.isEmpty) throw Exception('表达式为空');
    var pos = 0;
    double parseExpr() => parseAdd();

    double parseAdd() {
      var v = parseMul();
      while (pos < tokens.length) {
        final t = tokens[pos];
        if (t == '+') { pos++; v += parseMul(); }
        else if (t == '-') { pos++; v -= parseMul(); }
        else break;
      }
      return v;
    }

    double parseMul() {
      var v = parseUnary();
      while (pos < tokens.length) {
        final t = tokens[pos];
        if (t == '*') { pos++; v *= parseUnary(); }
        else if (t == '/') { pos++; v /= parseUnary(); }
        else if (t == '%') { pos++; v %= parseUnary(); }
        else if (t == '^') { pos++; v = math.pow(v, parseUnary()).toDouble(); }
        else break;
      }
      return v;
    }

    double parseUnary() {
      if (pos < tokens.length && tokens[pos] == '-') { pos++; return -parseUnary(); }
      if (pos < tokens.length && tokens[pos] == '+') { pos++; return parseUnary(); }
      return parseAtom();
    }

    double parseAtom() {
      final t = tokens[pos];
      if (t == '(') {
        pos++;
        final v = parseExpr();
        if (pos >= tokens.length || tokens[pos] != ')') {
          throw Exception('缺少右括号');
        }
        pos++;
        return v;
      }
      // 函数调用：sin( expr )
      final fnMatch = _fnCall.firstWhere((e) => tokens[pos].startsWith(e.$1), orElse: () => ('', ''));
      if (fnMatch.$1.isNotEmpty) {
        pos++;
        if (pos >= tokens.length || tokens[pos] != '(') {
          throw Exception('函数 ${fnMatch.$1} 后需要 (');
        }
        pos++;
        final arg = parseExpr();
        if (pos >= tokens.length || tokens[pos] != ')') {
          throw Exception('函数 ${fnMatch.$1} 缺少右括号');
        }
        pos++;
        return _applyFn(fnMatch.$1, arg);
      }
      final v = double.tryParse(t);
      if (v == null) throw Exception('无法解析「$t」（支持数字与 + - * / % ^ 及函数）');
      pos++;
      return v;
    }

    final result = parseExpr();
    if (pos < tokens.length) throw Exception('表达式有多余内容：${tokens[pos]}');
    // 结果规整：整数去小数
    return result;
  }

  static const _fnCall = [
    ('sin', ''), ('cos', ''), ('tan', ''),
    ('sqrt', ''), ('abs', ''), ('log', ''), ('ln', ''),
    ('round', ''), ('floor', ''), ('ceil', ''),
    ('min', ''), ('max', ''), ('pow', ''),
  ];

  static double _applyFn(String fn, double x) {
    switch (fn) {
      case 'sin': return math.sin(x);
      case 'cos': return math.cos(x);
      case 'tan': return math.tan(x);
      case 'sqrt': return math.sqrt(x);
      case 'abs': return x.abs();
      case 'log': return math.log(x) / math.ln10;
      case 'ln': return math.log(x);
      case 'round': return x.roundToDouble();
      case 'floor': return x.floorToDouble();
      case 'ceil': return x.ceilToDouble();
      case 'min': return x; // 单参 min/max 返回自身
      case 'max': return x;
      case 'pow': return math.pow(2, x).toDouble(); // pow(a,b) 用 a^b 运算符
    }
    return x;
  }

  static String _formatNum(double v) {
    if (v.isNaN || v.isInfinite) return '$v';
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.round().toString();
    var s = v.toStringAsPrecision(12);
    if (s.contains('e')) {
      // 科学计数法保持
    }
    return s;
  }

  static List<String> _tokenize(String expr) {
    final out = <String>[];
    final buf = StringBuffer();
    var i = 0;
    while (i < expr.length) {
      final c = expr[i];
      if (c == ' ') { i++; continue; }
      if ('0123456789.'.contains(c)) {
        buf.clear();
        while (i < expr.length && '0123456789.'.contains(expr[i])) {
          buf.write(expr[i]);
          i++;
        }
        out.add(buf.toString());
        continue;
      }
      if ('+-*/%^()'.contains(c)) {
        out.add(c);
        i++;
        continue;
      }
      // 函数名
      buf.clear();
      while (i < expr.length && (RegExp(r'[a-zA-Z]').hasMatch(expr[i]))) {
        buf.write(expr[i]);
        i++;
      }
      if (buf.isNotEmpty) out.add(buf.toString());
      else {
        throw Exception('无法识别的字符「$c」');
      }
    }
    return out;
  }

  static String evalFriendly(String expr) {
    try {
      return _formatNum(evalExpr(expr));
    } catch (e) {
      return '错误：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  // ---- base64 / URL / JSON / 正则 / 统计 ----

  static String jsonFormat(String input) {
    final decoded = jsonDecode(input);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  static String regexOp(String input, String arg) {
    // arg 格式：pattern::replacement（:: 分隔；无替换则只统计匹配数）
    final sep = arg.indexOf('::');
    final pattern = sep < 0 ? arg : arg.substring(0, sep);
    final replacement = sep < 0 ? '' : arg.substring(sep + 2);
    if (pattern.isEmpty) throw Exception('缺少正则表达式');
    final re = RegExp(pattern);
    if (sep < 0) {
      return '匹配 ${re.allMatches(input).length} 处';
    }
    return input.replaceAll(re, replacement);
  }

  static String textStats(String text) {
    final chars = text.replaceAll(RegExp(r'\s'), '').length;
    final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final paras = text.trim().isEmpty
        ? 0
        : text.split(RegExp(r'\n\s*\n')).where((x) => x.trim().isNotEmpty).length;
    final lines = text.isEmpty ? 0 : text.split('\n').length;
    return '字符数（不含空白）：$chars；字符数：${text.length}；词语数：$words；段落数：$paras；行数：$lines';
  }
}
