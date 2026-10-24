// 工具与权限配置（存 Rust config：notify.* / ai.* / tools.* / mcp.* / hook.*）
import 'store.dart';

class ToolsConfig {
  // ---- 系统授权 ----
  /// 通知授权（已授予 / 未授予）
  static bool get notifyGranted =>
      (AmoreStore.getConfig('notify.granted') ?? '1') != '0';

  static void setNotifyGranted(bool v) =>
      AmoreStore.setConfig('notify.granted', v ? '1' : '0');

  // ---- 高级设置 ----
  /// AI 能力模式：readonly / readwrite / full（存 config ai.mode）
  static String get aiMode =>
      AmoreStore.getConfig('ai.mode') ?? 'readwrite';

  static void setAiMode(String mode) =>
      AmoreStore.setConfig('ai.mode', mode);

  /// 兼容旧开关：完整权限 = full 模式
  static bool get fullAccess => aiMode == 'full';

  static void setFullAccess(bool v) =>
      setAiMode(v ? 'full' : 'readwrite');

  /// 是否可写（只读模式禁止写类操作）
  static bool get canWrite => aiMode != 'readonly';

  /// 模式说明
  static String aiModeDesc(String m) => switch (m) {
        'readonly' => '只读：AI 仅可读取数据，禁止修改与写操作',
        'full' => '完整权限：AI 可读写工作区，并关闭应用内沙盒',
        _ => '读写：AI 可读写数据（默认）',
      };

  /// 工具调用确认：按 AI 直接调用的工具执行审批
  static bool get toolConfirm =>
      (AmoreStore.getConfig('tools.confirm') ?? '0') != '0';

  static void setToolConfirm(bool v) =>
      AmoreStore.setConfig('tools.confirm', v ? '1' : '0');

  /// MCP 启动超时（秒，默认 10）
  static int get mcpTimeout {
    final raw = AmoreStore.getConfig('mcp.timeout') ?? '';
    return int.tryParse(raw) ?? 10;
  }

  static void setMcpTimeout(int sec) =>
      AmoreStore.setConfig('mcp.timeout', '$sec');

  /// ToolPkg 前置 Hook 超时（秒，默认 10）
  static int get hookTimeout {
    final raw = AmoreStore.getConfig('hook.timeout') ?? '';
    return int.tryParse(raw) ?? 10;
  }

  static void setHookTimeout(int sec) =>
      AmoreStore.setConfig('hook.timeout', '$sec');
}
