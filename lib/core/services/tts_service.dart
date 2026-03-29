import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import '../config/app_config.dart';
import '../utils/app_error.dart';
import '../models/advisor_model.dart';

/// TTS 服务 — 阿里云 CosyVoice
///
/// 使用你在 visionKey 相同账号下的 dashscope API Key
/// 模型：cosyvoice-v3-flash（低延迟，性价比高）
/// 协议：HTTP（非流式，请求完整音频后播放）
class TtsService {
  TtsService._();
  static final TtsService to = TtsService._();

  // ══════════════════════════════════════════════════════════════
  //  ⚙️  配置区（统一引用 AppConfig）
  // ══════════════════════════════════════════════════════════════

  /// 与 vision 同一个账号的 Key（来自 AppConfig）
  static const _apiKey = AppConfig.dashscopeKey;
  static const _model  = AppConfig.ttsModel;

  /// 各助理专属音色（CosyVoice v3 系统音色）
  /// 参考：https://help.aliyun.com/zh/model-studio/cosyvoice-voice-list
  static const _voiceMap = {
    AdvisorCharacter.xiaoTang: 'longxiaochun',   // 小春 — 甜美少女
    AdvisorCharacter.linWan:   'longshu',          // 书 — 知性女声
    AdvisorCharacter.xiaoYou:  'longyue',          // 悦 — 元气活泼
    AdvisorCharacter.chuXia:   'longwan',          // 婉 — 温柔文艺
  };

  // ══════════════════════════════════════════════════════════════

  final AudioPlayer _player = AudioPlayer();

  /// 是否正在播放
  bool get isPlaying => _player.playing;

  /// 播放状态流（供 UI 监听）
  Stream<bool> get playingStream => _player.playingStream;

  /// 播放完成事件流
  Stream<void> get completedStream => _player.playerStateStream
      .where((s) => s.processingState == ProcessingState.completed)
      .map((_) {});

  // ──────────────────────────────────────────────────────────────

  /// 将文本转语音并播放
  ///
  /// [text] 要合成的文字
  /// [character] 当前助理（决定音色）
  /// [onStart] 开始播放回调
  /// [onDone] 播放完成回调
  Future<void> speak({
    required String text,
    required AdvisorCharacter character,
    VoidCallback? onStart,
    VoidCallback? onDone,
  }) async {
    if (text.isEmpty) return;

    // Web 端不支持 just_audio 播放本地 bytes，走 HTML Audio
    if (kIsWeb) {
      await _speakWeb(text: text, character: character,
          onStart: onStart, onDone: onDone);
      return;
    }

    try {
      final bytes = await _fetchAudio(text, character);
      if (bytes == null) return;

      await _player.stop();
      await _player.setAudioSource(
        _BytesAudioSource(bytes, 'audio/mp3'),
      );
      onStart?.call();
      await _player.play();

      // 等待播放完成
      await _player.playerStateStream.firstWhere(
        (s) => s.processingState == ProcessingState.completed,
      );
      onDone?.call();
    } catch (e, st) {
      AppLogger.e('TtsService', 'speak 异常', ErrorMapper.from(e), st);
      onDone?.call();
    }
  }

  /// 停止播放
  Future<void> stop() async {
    await _player.stop();
  }

  /// 释放资源
  void dispose() {
    _player.dispose();
  }

  // ──────────────────────────────────────────────────────────────
  //  私有方法
  // ──────────────────────────────────────────────────────────────

  /// 调用阿里云 CosyVoice HTTP API，返回 mp3 bytes
  Future<Uint8List?> _fetchAudio(
      String text, AdvisorCharacter character) async {
    if (AppConfig.useMock) {
      AppLogger.d('TtsService', 'Key 未配置，TTS Mock 跳过');
      return null;
    }

    final voice = _voiceMap[character] ?? 'longxiaochun';

    // 超过300字截断，避免请求太慢
    final truncated =
        text.length > 300 ? '${text.substring(0, 300)}...' : text;

    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.ttsBase),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
              'X-DashScope-DataInspection': 'enable',
            },
            body: jsonEncode({
              'model': _model,
              'input': {'text': truncated},
              'parameters': {
                'voice': voice,
                'format': 'mp3',
                'sample_rate': 22050,
                'volume': 80,
                'speech_rate': 1.0,
                'pitch_rate': 1.0,
              },
            }),
          )
          .timeout(AppConfig.ttsTimeout);

      if (response.statusCode == 200) {
        // 返回的是二进制 mp3 数据
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('audio') ||
            contentType.contains('octet-stream')) {
          return response.bodyBytes;
        }
        // 某些情况下返回 JSON（含 base64）
        try {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final audioStr = json['output']?['audio'] as String?;
          if (audioStr != null) {
            return base64Decode(audioStr);
          }
        } catch (_) {}
        return response.bodyBytes;
      } else {
        AppLogger.e('TtsService', 'API error ${response.statusCode}');
        return null;
      }
    } catch (e, st) {
      AppLogger.e('TtsService', '_fetchAudio 异常', ErrorMapper.from(e), st);
      return null;
    }
  }

  /// Web 端使用 HTML Audio Element 播放（绕过 just_audio 的 Web 限制）
  Future<void> _speakWeb({
    required String text,
    required AdvisorCharacter character,
    VoidCallback? onStart,
    VoidCallback? onDone,
  }) async {
    try {
      final bytes = await _fetchAudio(text, character);
      if (bytes == null) {
        onDone?.call();
        return;
      }
      // Web 端暂时直接调 onStart/onDone，实际播放需要 dart:html
      // 在真机版本上 just_audio 会正常工作
      onStart?.call();
      AppLogger.d('TtsService', 'Web端TTS：音频已获取（${bytes.length} bytes）');
      // 模拟播放时间（文字长度 / 5 秒，最多10秒）
      final duration = (text.length / 5).clamp(1.0, 10.0);
      await Future.delayed(Duration(seconds: duration.toInt()));
      onDone?.call();
    } catch (e) {
      AppLogger.w('TtsService', '_speakWeb 异常', e);
      onDone?.call();
    }
  }
}

// ──────────────────────────────────────────────────────────────
//  内存字节流 AudioSource（给 just_audio 用）
// ──────────────────────────────────────────────────────────────

class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  final String _mimeType;

  _BytesAudioSource(this._bytes, this._mimeType);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: _mimeType,
    );
  }
}
