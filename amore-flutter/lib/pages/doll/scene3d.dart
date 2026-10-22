// Amore 玩偶 Tab — 原生 SceneKit PlatformView 封装（iOS）
// channel: amore/doll_scene
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DollScene3D extends StatefulWidget {
  final String gender;
  final String skin;
  final double heightScale;
  final Map<String, Map<String, String>> slots; // category → {kind, color}
  final VoidCallback? onViewReady;

  const DollScene3D({
    super.key,
    required this.gender,
    required this.skin,
    required this.heightScale,
    required this.slots,
    this.onViewReady,
  });

  @override
  State<DollScene3D> createState() => _DollScene3DState();
}

class _DollScene3DState extends State<DollScene3D> {
  static const _channel = MethodChannel('amore/doll_scene');

  bool _viewCreated = false;
  int _pushAttempts = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    // PlatformView 创建完成后再推送（时序兜底）
    _retryTimer = Timer.periodic(const Duration(milliseconds: 600), (t) async {
      if (_viewCreated || t.tick > 8) {
        t.cancel();
        if (!_viewCreated) return;
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DollScene3D old) {
    super.didUpdateWidget(old);
    if (old.gender != widget.gender ||
        old.skin != widget.skin ||
        old.heightScale != widget.heightScale) {
      _pushCharacter();
    }
    if (!mapEquals(old.slots, widget.slots)) {
      _pushSlots();
    }
  }

  Future<void> _pushCharacter() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod('setCharacter', {
        'gender': widget.gender,
        'skin': widget.skin,
        'heightScale': widget.heightScale,
      });
      await _pushSlots();
    } on PlatformException {
      // view 尚未就绪：延迟重试
      if (_pushAttempts < 5) {
        _pushAttempts++;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _pushCharacter();
        });
      }
    }
  }

  Future<void> _pushSlots() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod('updateSlots', {'slots': widget.slots});
    } on PlatformException {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const Center(
        child: Text('3D 预览当前支持 iPhone',
            style: TextStyle(color: Color(0xFF86868B), fontSize: 13)),
      );
    }
    return UiKitView(
      viewType: 'doll_scene',
      onPlatformViewCreated: (_) async {
        _viewCreated = true;
        await _pushCharacter();
        widget.onViewReady?.call();
      },
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }
}

/// 全局便捷通道（供页面按钮调用：姿势/视角/截图）
class DollSceneChannel {
  static const _channel = MethodChannel('amore/doll_scene');

  static Future<void> applyPose(String pose) async {
    try {
      await _channel.invokeMethod('applyPose', {'pose': pose});
    } on PlatformException {
      // ignore
    }
  }

  static Future<void> face(String label) async {
    try {
      await _channel.invokeMethod('face', {'label': label});
    } on PlatformException {
      // ignore
    }
  }

  static Future<void> resetView() async {
    try {
      await _channel.invokeMethod('resetView');
    } on PlatformException {
      // ignore
    }
  }

  /// 原生是否已默认加载骨骼模型
  static Future<bool> defaultSkinned() async {
    try {
      return await _channel.invokeMethod<bool>('defaultSkinned') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 加载内置真骨骼模型（CesiumMan：完整骨骼+蒙皮+行走动画）
  static Future<bool> loadSkinned([String name = 'CesiumMan']) async {
    try {
      return await _channel.invokeMethod<bool>('loadSkinned', {'name': name}) ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> unloadSkinned() async {
    try {
      await _channel.invokeMethod('unloadSkinned');
    } on PlatformException {
      // ignore
    }
  }

  /// 返回 PNG 数据（保存/分享用）
  static Future<Uint8List?> snapshot() async {
    try {
      return await _channel.invokeMethod<Uint8List>('snapshot');
    } on PlatformException {
      return null;
    }
  }
}
