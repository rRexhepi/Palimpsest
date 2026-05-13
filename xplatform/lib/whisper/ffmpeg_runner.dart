import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

/// Result of a single ffmpeg / ffprobe invocation. `code` follows ffmpeg
/// convention (0 = success, non-zero = failure); `output` is the merged
/// stdout/stderr so callers can surface failures with real diagnostics.
class FfmpegResult {
  final int code;
  final String output;
  const FfmpegResult(this.code, this.output);
  bool get ok => code == 0;
}

/// Platform-dispatched ffmpeg/ffprobe runner.
///
/// On Android / iOS we use `ffmpeg_kit_flutter_new_min` — ships the binaries
/// inside the app bundle. On Windows / Linux / macOS we shell out to a
/// system-installed `ffmpeg` / `ffprobe` on PATH (or whatever
/// `PALIMPSEST_FFMPEG` / `PALIMPSEST_FFPROBE` env vars point to). Desktop
/// users see a clear `StateError` at first transcribe if the binaries are
/// missing.
class FfmpegRunner {
  static final FfmpegRunner instance = FfmpegRunner._();
  FfmpegRunner._();

  bool get _useNative => Platform.isAndroid || Platform.isIOS;

  Future<FfmpegResult> ffmpeg(List<String> args) =>
      _useNative ? _runNativeFfmpeg(args) : _runHostBinary(_ffmpegBin, args);

  Future<FfmpegResult> ffprobe(List<String> args) =>
      _useNative ? _runNativeFfprobe(args) : _runHostBinary(_ffprobeBin, args);

  /// Spawn ffmpeg with its stdout/stderr exposed for streaming consumption.
  /// Desktop-only — `ffmpeg_kit` on mobile gives no equivalent live pipe.
  /// Callers must `await Process.exitCode` to reap the child.
  Future<Process> startFfmpeg(List<String> args) {
    if (_useNative) {
      throw UnsupportedError(
        'startFfmpeg is desktop-only. On mobile, use ffmpeg() which runs the '
        'invocation to completion.',
      );
    }
    return Process.start(_ffmpegBin, args, runInShell: false);
  }

  bool get supportsStreamingFfmpeg => !_useNative;

  Future<FfmpegResult> _runNativeFfmpeg(List<String> args) async {
    final session = await FFmpegKit.executeWithArguments(args);
    final code = await session.getReturnCode();
    final out = (await session.getOutput()) ?? '';
    final value = code?.getValue() ?? -1;
    return FfmpegResult(ReturnCode.isSuccess(code) ? 0 : value, out);
  }

  Future<FfmpegResult> _runNativeFfprobe(List<String> args) async {
    final session = await FFprobeKit.executeWithArguments(args);
    final code = await session.getReturnCode();
    final out = (await session.getOutput()) ?? '';
    final value = code?.getValue() ?? -1;
    return FfmpegResult(ReturnCode.isSuccess(code) ? 0 : value, out);
  }

  String get _ffmpegBin =>
      Platform.environment['PALIMPSEST_FFMPEG'] ?? 'ffmpeg';
  String get _ffprobeBin =>
      Platform.environment['PALIMPSEST_FFPROBE'] ?? 'ffprobe';

  Future<FfmpegResult> _runHostBinary(String exe, List<String> args) async {
    try {
      final result = await Process.run(exe, args, runInShell: false);
      final out = '${result.stdout}\n${result.stderr}'.trim();
      return FfmpegResult(result.exitCode, out);
    } on ProcessException catch (e) {
      return FfmpegResult(
        127,
        'Failed to launch "$exe": ${e.message}. '
        'Install ffmpeg/ffprobe and ensure they are on PATH, or set '
        'PALIMPSEST_FFMPEG / PALIMPSEST_FFPROBE.',
      );
    }
  }
}
