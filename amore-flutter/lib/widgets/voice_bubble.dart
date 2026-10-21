// 对应 Swift：ChatsView.swift 的 VoiceBubble / PersonaVoice —— 语音条（TTS 合成 + 播放）
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/theme.dart';

/// 语音条：点击合成 TTS 并播放。
/// plain=true 时不画自身背景（群聊嵌在气泡里用，对齐 build 89 的 plain 模式）。
class VoiceBubble extends StatefulWidget {
  final String content;
  final ChatFriend? friend; // 用于取好友专属语音配置
  final bool plain;
  final bool mine;

  const VoiceBubble({
    super.key,
    required this.content,
    this.friend,
    this.plain = false,
    this.mine = false,
  });

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  bool _loading = false;
  bool _playing = false;
  final _player = AudioPlayer();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// 解析好友生效的语音参数（好友专属 > 全局配置）
  (String, String, String) _voiceConfig() {
    final cfg = AmoreStore.allConfig();
    var engine = widget.friend?.voiceEngine.isNotEmpty == true
        ? widget.friend!.voiceEngine
        : (cfg['voice_engine'] ?? 'server');
    var voiceId = widget.friend?.voiceId ?? '';
    var key = widget.friend?.ttsKey ?? '';
    if (engine == 'cloud_sf' && key.isEmpty) {
      key = cfg['sf_tts_key'] ?? '';
      voiceId = voiceId.isEmpty ? (cfg['sf_tts_voice'] ?? 'female-yujie') : voiceId;
    }
    return (engine, voiceId, key);
  }

  Future<void> _play() async {
    if (_loading || _playing) return;
    setState(() => _loading = true);
    try {
      final (engine, voiceId, key) = _voiceConfig();
      final req = AmoreStore.ttsRequest(
          engine: engine, voiceId: voiceId, apiKey: key, text: widget.content);
      if (req['error'] != null) {
        throw Exception(req['error'].toString());
      }
      final url = (req['url'] ?? '').toString();
      final headers = Map<String, dynamic>.from(req['headers'] as Map? ?? {});
      final body = Map<String, dynamic>.from(req['body'] as Map? ?? {});

      Response<List<int>> resp;
      final dio = Dio(BaseOptions(responseType: ResponseType.bytes));
      if (url == 'provider') {
        // OpenAI 风格：用激活 provider 的 base
        final cfg = AmoreStore.allConfig();
        final activeId = AmoreStore.activeProviderId();
        final p = AmoreStore.listProviders().where((x) => x.id == activeId).toList();
        if (p.isEmpty) throw Exception('未配置模型供应商，无法使用 model 语音引擎');
        var base = p.first.baseURL.trim();
        if (base.isEmpty) {
          base = AmoreStore.vendors().where((v) => v.key == p.first.vendor).map((v) => v.base).firstOrNull ?? '';
        }
        if (base.endsWith('/')) base = base.substring(0, base.length - 1);
        resp = await dio.post<List<int>>('$base/audio/speech',
            data: body, options: Options(headers: headers));
      } else {
        resp = await dio.post<List<int>>(url, data: body, options: Options(headers: headers));
      }

      if (resp.data == null || resp.data!.isEmpty) {
        throw Exception('语音服务无返回（HTTP ${resp.statusCode}）');
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(resp.data!);
      await _player.play(DeviceFileSource(file.path));
      setState(() {
        _loading = false;
        _playing = true;
      });
      await _player.onPlayerComplete.first;
      if (mounted) setState(() => _playing = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('语音不可用：${e.toString().substring(0, e.toString().length.clamp(0, 80))}')));
      }
    }
  }

  /// 按内容长度估算秒数（约 4 字/秒）
  int get _seconds => (widget.content.length / 4).ceil().clamp(1, 60);

  @override
  Widget build(BuildContext context) {
    final inner = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _loading
              ? Icons.hourglass_top_rounded
              : _playing
                  ? Icons.stop_rounded
                  : Icons.play_arrow_rounded,
          color: widget.plain || widget.mine ? Colors.white : AmoreBrand.orange,
          size: 22,
        ),
        const SizedBox(width: 8),
        // 波形条
        ...List.generate(12, (i) {
          final h = 6.0 + ((i * 37) % 14).toDouble();
          return Container(
            width: 2.5,
            height: _playing ? h : h * 0.7,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: (widget.plain || widget.mine
                      ? Colors.white.withOpacity(0.85)
                      : AmoreBrand.orange.withOpacity(0.75))
                  .withOpacity(_playing ? 1.0 : 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
        const SizedBox(width: 8),
        Text('${_seconds}″',
            style: TextStyle(
                fontSize: 12,
                color: widget.plain || widget.mine
                    ? Colors.white.withOpacity(0.8)
                    : AmoreTheme.textSecondary)),
      ],
    );

    if (widget.plain) {
      return GestureDetector(onTap: _play, child: inner);
    }

    return GestureDetector(
      onTap: _play,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: widget.mine ? Colors.white.withOpacity(0.16) : AmoreTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: widget.mine
              ? null
              : Border.all(color: AmoreTheme.cardBorder),
        ),
        child: inner,
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
