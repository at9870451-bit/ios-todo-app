// 本地代码引擎：AI/终端共用的确定性内置计算能力（纯 Dart，无 IO/网络沙盒）
// 支持：数学表达式求值、base64、URL 编解码、JSON 格式化、正则替换、文本统计
import 'dart:convert';
import 'dart:math' as math;

class CodeEngine {
  /// 统一入口：op + input + 可选参数 → 结果文本
  static String run(String op, String input, [String? arg]) {
    switch (op) {
      case 'eval':
        return '= ${evalFriendly(input)}';
      case 'base64':
        return arg == 'decode'
            ? utf8.decode(base64Decode(input))
            : base64Encode(utf8.encode(input));
      case 'url':
        return arg == 'decode'
            ? Uri.decodeComponent(input)
            : Uri.encodeComponent(input);
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

  /// 表达式求值（交给 _ExprParser 递归下降解析）
  static double evalExpr(String expr) {
    return _ExprParser(_tokenize(expr)).parse();
  }

  static String evalFriendly(String expr) {
    try {
      return _formatNum(evalExpr(expr));
    } catch (e) {
      return '错误：${e.toString().replaceFirst('Exception: ', '')}';
    }
  }

  static String _formatNum(double v) {
    if (v.isNaN || v.isInfinite) return '$v';
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.round().toString();
    return v.toStringAsPrecision(12);
  }

  static List<String> _tokenize(String expr) {
    final out = <String>[];
    final buf = StringBuffer();
    var i = 0;
    while (i < expr.length) {
      final c = expr[i];
      if (c == ' ') {
        i++;
        continue;
      }
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
      buf.clear();
      while (i < expr.length && RegExp(r'[a-zA-Z]').hasMatch(expr[i])) {
        buf.write(expr[i]);
        i++;
      }
      if (buf.isNotEmpty) {
        out.add(buf.toString());
      } else {
        throw Exception('无法识别的字符「$c」');
      }
    }
    return out;
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
    final words =
        text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final paras = text.trim().isEmpty
        ? 0
        : text.split(RegExp(r'\n\s*\n')).where((x) => x.trim().isNotEmpty).length;
    final lines = text.isEmpty ? 0 : text.split('\n').length;
    return '字符数（不含空白）：$chars；字符数：${text.length}；词语数：$words；段落数：$paras；行数：$lines';
  }
}

/// 数学表达式递归下降解析器（类成员方法互相引用，无 Dart 局部函数前向引用限制）
class _ExprParser {
  final List<String> t;
  int pos = 0;
  _ExprParser(this.t);

  double parse() => add();

  double add() {
    var v = mul();
    while (pos < t.length) {
      final k = t[pos];
      if (k == '+') {
        pos++;
        v += mul();
      } else if (k == '-') {
        pos++;
        v -= mul();
      } else {
        break;
      }
    }
    return v;
  }

  double mul() {
    var v = unary();
    while (pos < t.length) {
      final k = t[pos];
      if (k == '*') {
        pos++;
        v *= unary();
      } else if (k == '/') {
        pos++;
        v /= unary();
      } else if (k == '%') {
        pos++;
        v %= unary();
      } else if (k == '^') {
        pos++;
        v = math.pow(v, unary()).toDouble();
      } else {
        break;
      }
    }
    return v;
  }

  double unary() {
    if (pos < t.length && t[pos] == '-') {
      pos++;
      return -unary();
    }
    if (pos < t.length && t[pos] == '+') {
      pos++;
      return unary();
    }
    return atom();
  }

  double atom() {
    final k = t[pos];
    if (k == '(') {
      pos++;
      final v = add();
      if (pos >= t.length || t[pos] != ')') throw Exception('缺少右括号');
      pos++;
      return v;
    }
    // 函数调用：sin( expr ) / min( a, b )
    for (final f in _fnNames) {
      if (k == f) {
        pos++;
        if (pos >= t.length || t[pos] != '(') throw Exception('函数 $f 后需要 (');
        pos++;
        final a1 = add();
        if (pos < t.length && t[pos] == ',') {
          pos++;
          final a2 = add();
          if (pos >= t.length || t[pos] != ')') throw Exception('函数 $f 缺少右括号');
          pos++;
          return _applyFn2(f, a1, a2);
        }
        if (pos >= t.length || t[pos] != ')') throw Exception('函数 $f 缺少右括号');
        pos++;
        return _applyFn1(f, a1);
      }
    }
    final v = double.tryParse(k);
    if (v == null) throw Exception('无法解析「$k」（支持数字与 + - * / % ^ 及函数）');
    pos++;
    return v;
  }

  static const _fnNames = [
    'sin', 'cos', 'tan', 'sqrt', 'abs', 'log', 'ln',
    'round', 'floor', 'ceil', 'min', 'max', 'pow',
  ];

  static double _applyFn1(String fn, double x) {
    switch (fn) {
      case 'sin':
        return math.sin(x);
      case 'cos':
        return math.cos(x);
      case 'tan':
        return math.tan(x);
      case 'sqrt':
        return math.sqrt(x);
      case 'abs':
        return x.abs();
      case 'log':
        return math.log(x) / math.ln10;
      case 'ln':
        return math.log(x);
      case 'round':
        return x.roundToDouble();
      case 'floor':
        return x.floorToDouble();
      case 'ceil':
        return x.ceilToDouble();
      case 'min':
        return x;
      case 'max':
        return x;
      case 'pow':
        return math.pow(2, x).toDouble();
    }
    return x;
  }

  static double _applyFn2(String fn, double a, double b) {
    switch (fn) {
      case 'min':
        return a < b ? a : b;
      case 'max':
        return a > b ? a : b;
      case 'pow':
        return math.pow(a, b).toDouble();
    }
    return a;
  }
}