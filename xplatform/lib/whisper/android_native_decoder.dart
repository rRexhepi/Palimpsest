import 'package:flutter/services.dart';

/// Dart wrapper for the `palimpsest/native_decoder` MethodChannel
/// implemented in `android/.../NativeAudioDecoder.kt`. The slot the
/// platform-agnostic `FfmpegRunner` skeleton plugs in on Android.
class AndroidNativeDecoder {
  static const _channel = MethodChannel('palimpsest/native_decoder');

  /// Decode (a range of) [sourcePath] into a 16-bit signed-little-endian
  /// WAV at [outputPath], downmixed to [channels] and resampled to
  /// [sampleRate]. Throws on failure; the caller maps that to the same
  /// non-zero-exit-code shape ffmpeg would have produced.
  static Future<void> decode({
    required String sourcePath,
    required String outputPath,
    double startSeconds = 0,
    double? durationSeconds,
    int sampleRate = 16000,
    int channels = 1,
  }) {
    return _channel.invokeMethod<void>('decode', {
      'source': sourcePath,
      'output': outputPath,
      'startSeconds': startSeconds,
      'durationSeconds': durationSeconds,
      'sampleRate': sampleRate,
      'channels': channels,
    });
  }

  /// Total media duration in seconds via `MediaMetadataRetriever`. Returns
  /// `0` rather than throwing so callers can fall back to other strategies.
  static Future<double> durationSeconds(String sourcePath) async {
    try {
      final result = await _channel.invokeMethod<num>('duration', {
        'source': sourcePath,
      });
      final v = result?.toDouble() ?? 0.0;
      return v.isFinite && v > 0 ? v : 0;
    } catch (_) {
      return 0;
    }
  }
}
