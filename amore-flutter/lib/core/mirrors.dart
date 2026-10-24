// 镜像源配置（存 config rootfs.mirror_*；为沙盒终端/包管理准备）
import 'store.dart';

class MirrorPreset {
  final String name;
  final String url;
  const MirrorPreset(this.name, this.url);
}

class Mirrors {
  // Alpine APK
  static const apkPresets = [
    MirrorPreset('官方（dl-cdn.alpinelinux.org）', 'https://dl-cdn.alpinelinux.org/alpine/'),
    MirrorPreset('清华 TUNA', 'https://mirrors.tuna.tsinghua.edu.cn/alpine/'),
    MirrorPreset('中科大 USTC', 'https://mirrors.ustc.edu.cn/alpine/'),
    MirrorPreset('阿里云', 'https://mirrors.aliyun.com/alpine/'),
  ];

  // Python pip
  static const pipPresets = [
    MirrorPreset('官方 PyPI', 'https://pypi.org/simple/'),
    MirrorPreset('清华 TUNA', 'https://pypi.tuna.tsinghua.edu.cn/simple/'),
    MirrorPreset('阿里云', 'https://mirrors.aliyun.com/pypi/simple/'),
    MirrorPreset('腾讯云', 'https://mirrors.cloud.tencent.com/pypi/simple/'),
    MirrorPreset('豆瓣', 'https://pypi.douban.com/simple/'),
  ];

  // Node.js npm
  static const npmPresets = [
    MirrorPreset('官方 npm', 'https://registry.npmjs.org/'),
    MirrorPreset('淘宝 npmmirror', 'https://registry.npmmirror.com/'),
    MirrorPreset('腾讯云', 'https://mirrors.cloud.tencent.com/npm/'),
  ];

  static String get apk {
    final custom = AmoreStore.getConfig('rootfs.mirror_apk_custom') ?? '';
    return custom.isNotEmpty ? custom : (AmoreStore.getConfig('rootfs.mirror_apk') ?? '');
  }

  static String get pip {
    final custom = AmoreStore.getConfig('rootfs.mirror_pip_custom') ?? '';
    return custom.isNotEmpty ? custom : (AmoreStore.getConfig('rootfs.mirror_pip') ?? '');
  }

  static String get npm {
    final custom = AmoreStore.getConfig('rootfs.mirror_npm_custom') ?? '';
    return custom.isNotEmpty ? custom : (AmoreStore.getConfig('rootfs.mirror_npm') ?? '');
  }

  static String apkLabel() =>
      _labelOf(apkPresets, 'rootfs.mirror_apk', 'rootfs.mirror_apk_custom', '官方（默认）');

  static String pipLabel() =>
      _labelOf(pipPresets, 'rootfs.mirror_pip', 'rootfs.mirror_pip_custom', '官方 PyPI（默认）');

  static String npmLabel() =>
      _labelOf(npmPresets, 'rootfs.mirror_npm', 'rootfs.mirror_npm_custom', '官方 npm（默认）');

  static String _labelOf(List<MirrorPreset> presets, String key, String customKey,
      String fallback) {
    final cur = AmoreStore.getConfig(key) ?? '';
    if (cur.isNotEmpty) {
      for (final p in presets) {
        if (p.url == cur) return p.name;
      }
    }
    final custom = AmoreStore.getConfig(customKey) ?? '';
    if (custom.isNotEmpty) return '自定义：$custom';
    return fallback;
  }

  /// 选择预设：写入对应 key 并清除自定义
  static void select(String key, String customKey, String url) {
    AmoreStore.setConfig(key, url);
    AmoreStore.setConfig(customKey, '');
  }

  /// 自定义：清掉预设 key，写自定义
  static void selectCustom(String key, String customKey, String url) {
    AmoreStore.setConfig(key, '');
    AmoreStore.setConfig(customKey, url);
  }
}
