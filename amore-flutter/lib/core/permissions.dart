// 权限设置：AI/Agent 对各系统能力的访问控制（存 Rust config：perms.*）
// 默认全部允许（Bypass）；"全部自动允许" 为总开关。
import 'store.dart';

class Permissions {
  static const keys = [
    'healthkit',
    'calendar',
    'reminders',
    'photos',
    'location',
    'homekit',
    'clipboard',
  ];

  static bool _on(String k) {
    final raw = AmoreStore.getConfig('perms.$k');
    // 空 = 默认允许（Bypass）
    return raw == null || raw == '1' || raw.isEmpty;
  }

  /// 全部自动允许（总开关）
  static bool get allAllow => _on('all_allow');

  /// 允许修改配置（配置工具）
  static bool get configTools => _on('config_tools');

  /// 某项权限是否生效（总开关开 → 全部放行；否则看单项）
  static bool allow(String key) => allAllow ? true : _on(key);

  static void set(String key, bool v) {
    AmoreStore.setConfig('perms.$key', v ? '1' : '0');
  }

  static void setAllAllow(bool v) {
    AmoreStore.setConfig('perms.all_allow', v ? '1' : '0');
    // 总开关关闭时单项恢复各自设置；开启时全部放行
  }

  static void setConfigTools(bool v) {
    AmoreStore.setConfig('perms.config_tools', v ? '1' : '0');
  }
}
