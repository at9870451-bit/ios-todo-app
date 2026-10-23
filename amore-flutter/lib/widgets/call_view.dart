// 对应 Swift：CallView.swift —— 全屏语音通话（UI + 状态机；录音 M5 接入）
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/theme.dart';
import 'friend_avatar.dart';

class CallView extends StatefulWidget {
  final ChatFriend friend;
  const CallView({super.key, required this.friend});

  @override
  State<CallView> createState() => _CallViewState();
}

enum CallPhase { connecting, talking, ended }

class _CallViewState extends State<CallView>
    with SingleTickerProviderStateMixin {
  CallPhase _phase = CallPhase.connecting;
  bool _pressing = false;
  late final AnimationController _waveCtl;

  @override
  void initState() {
    super.initState();
    _waveCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    // 模拟接通（真实接听 M5 接 ASR/TTS 流水线）
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted && _phase == CallPhase.connecting) {
        setState(() => _phase = CallPhase.talking);
      }
    });
  }

  @override
  void dispose() {
    _waveCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // 头像 + 呼吸光圈
            AnimatedBuilder(
              animation: _waveCtl,
              builder: (_, __) {
                final phase = _phase == CallPhase.talking && _pressing
                    ? _waveCtl.value
                    : _phase == CallPhase.talking
                        ? 0.5 + 0.5 * sin(_waveCtl.value * 6.28)
                        : 0.4;
                return Container(
                  padding: EdgeInsets.all(10 + phase * 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AmoreBrand.orange.withOpacity(0.22 * phase + 0.05),
                        width: 6),
                  ),
                  child: FriendAvatar(
                      name: widget.friend.name,
                      avatarFile: widget.friend.avatarFile,
                      size: 96),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(widget.friend.name,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1D1D1F))),
            const SizedBox(height: 8),
            Text(
              _phase == CallPhase.connecting
                  ? '正在呼叫…'
                  : _phase == CallPhase.talking
                      ? (_pressing ? '松开发送' : '通话中 · 按住说话')
                      : '通话已结束',
              style: const TextStyle(fontSize: 13.5, color: AmoreTheme.textSecondary),
            ),
            const Spacer(),
            if (_phase == CallPhase.talking)
              // 按住说话按钮
              GestureDetector(
                onLongPressStart: (_) => setState(() => _pressing = true),
                onLongPressEnd: (_) {
                  setState(() => _pressing = false);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('语音识别 M5 接入，当前已记录一条 [语音] 消息')));
                },
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _pressing ? AmoreBrand.orange : null,
                        : const Color(0xFFFFF4E8),
                    border: Border.all(
                        color: _pressing
                            ? AmoreBrand.orange
                            : const Color(0xFFFFE2C2),
                        width: 1.4),
                  ),
                  child: Icon(_pressing ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _pressing
                          ? Colors.white
                          : AmoreBrand.orangeDeep,
                      size: 34),
                ),
              ),
            const SizedBox(height: 40),
            // 挂断
            GestureDetector(
              onTap: () {
                setState(() => _phase = CallPhase.ended);
                Future.delayed(const Duration(milliseconds: 700), () {
                  if (context.mounted) Navigator.pop(context);
                });
              },
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AmoreTheme.danger.withOpacity(0.9),
                  boxShadow: [
                    BoxShadow(
                        color: AmoreTheme.danger.withOpacity(0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}
