import 'dart:io';

import 'package:flutter/foundation.dart';

/// User-selectable CPU budget for the Whisper transcription pipeline.
/// Stored in SharedPreferences and read at pool-spawn time.
enum TranscriptionPerformance {
  /// Use everything the device has. Roughly 3x faster than [light] on a
  /// phone with 6+ cores; pulls ~540 MB resident if [WhisperConfig]
  /// decides 2 workers fit.
  max,

  /// Default. Roughly 2x faster than [light] with no extra memory cost —
  /// one worker, threads scaled to the device's perf cores.
  balanced,

  /// Smallest footprint. Mirrors the conservative 1 worker × 2 threads
  /// the mobile build shipped before this was tunable. Pick when the
  /// phone needs to stay responsive for other foreground apps.
  light,
}

extension TranscriptionPerformanceCodec on TranscriptionPerformance {
  static TranscriptionPerformance parse(
    String? raw, {
    TranscriptionPerformance? fallback,
  }) =>
      TranscriptionPerformance.values.firstWhere(
        (v) => v.name == raw,
        orElse: () => fallback ?? WhisperConfig.defaultForHost,
      );
}

/// Read by [WhisperTranscriber] at pool-spawn time, so setting changes
/// take effect on the next transcription run, not retroactively.
final ValueNotifier<TranscriptionPerformance> activeTranscriptionPerformance =
    ValueNotifier<TranscriptionPerformance>(TranscriptionPerformance.balanced);

/// All `Platform.*` lookups for the Whisper pipeline live here so the
/// rest of the code stays platform-agnostic.
class WhisperConfig {
  const WhisperConfig({
    required this.workerCount,
    required this.threadsPerWorker,
    required this.useNNAPI,
  });

  /// Isolate workers, each holding its own `OfflineRecognizer`.
  final int workerCount;

  /// `numThreads` handed to each recognizer's `decode` call. Total CPU
  /// thread pressure is `workerCount * threadsPerWorker`.
  final int threadsPerWorker;

  /// Ask sherpa-onnx to dispatch inference to Android's NNAPI. Off by
  /// default: vendor NPUs handle the int8 ops with different precision
  /// than ONNX Runtime CPU and the transcripts diverge from the Linux
  /// reference.
  final bool useNNAPI;

  WhisperConfig copyWith({
    int? workerCount,
    int? threadsPerWorker,
    bool? useNNAPI,
  }) {
    return WhisperConfig(
      workerCount: workerCount ?? this.workerCount,
      threadsPerWorker: threadsPerWorker ?? this.threadsPerWorker,
      useNNAPI: useNNAPI ?? this.useNNAPI,
    );
  }

  /// Each worker holds ~270 MB of int8 weights; the per-platform
  /// strategies budget cores and RAM against that.
  factory WhisperConfig.forLevel(TranscriptionPerformance level) =>
      (Platform.isAndroid || Platform.isIOS)
          ? _mobileForLevel(level)
          : _desktopForLevel(level);

  static TranscriptionPerformance get defaultForHost =>
      (Platform.isAndroid || Platform.isIOS)
          ? TranscriptionPerformance.balanced
          : TranscriptionPerformance.max;

  /// Mobile caps at 2 workers regardless of cores — phones thermal-
  /// throttle under sustained load and the OS is hostile to apps that
  /// peg every core. ONNX Runtime tops out at 4 intra-op threads, so
  /// extra cores beyond `workers × 4` are wasted anyway.
  static WhisperConfig _mobileForLevel(TranscriptionPerformance level) {
    final cores = Platform.numberOfProcessors;
    final totalRamMb = _detectTotalRamMb();
    switch (level) {
      case TranscriptionPerformance.max:
        final canMultiWorker = cores >= 6 &&
            (totalRamMb == null || totalRamMb >= 4000);
        final workers = canMultiWorker ? 2 : 1;
        final threads = ((cores ~/ workers).clamp(2, 4)).toInt();
        return WhisperConfig(
          workerCount: workers,
          threadsPerWorker: threads,
          useNNAPI: false,
        );
      case TranscriptionPerformance.balanced:
        return WhisperConfig(
          workerCount: 1,
          threadsPerWorker: cores >= 4 ? 4 : 2,
          useNNAPI: false,
        );
      case TranscriptionPerformance.light:
        return const WhisperConfig(
          workerCount: 1,
          threadsPerWorker: 2,
          useNNAPI: false,
        );
    }
  }

  /// Workers cap at 4 — beyond that ORT contention and L3 thrash eat
  /// the parallelism win.
  static WhisperConfig _desktopForLevel(TranscriptionPerformance level) {
    final cores = Platform.numberOfProcessors;
    final totalRamMb = _detectTotalRamMb();
    switch (level) {
      case TranscriptionPerformance.max:
        final workersByCores = ((cores / 4).floor()).clamp(1, 4);
        final workersByRam = totalRamMb == null
            ? 4
            : (((totalRamMb - 1500) ~/ 700)).clamp(1, 4);
        final workers = workersByCores < workersByRam
            ? workersByCores
            : workersByRam;
        final threads = ((cores ~/ workers).clamp(2, 4)).toInt();
        return WhisperConfig(
          workerCount: workers,
          threadsPerWorker: threads,
          useNNAPI: false,
        );
      case TranscriptionPerformance.balanced:
        final workers = cores >= 16 ? 2 : 1;
        return WhisperConfig(
          workerCount: workers,
          threadsPerWorker: cores >= 4 ? 4 : 2,
          useNNAPI: false,
        );
      case TranscriptionPerformance.light:
        return const WhisperConfig(
          workerCount: 1,
          threadsPerWorker: 2,
          useNNAPI: false,
        );
    }
  }

  /// Returns null when the platform doesn't expose RAM via a file we
  /// can read cheaply (iOS/macOS/Windows). Pool spawn falls back to
  /// core-only scaling rather than paying a method-channel round trip.
  static int? get totalRamMb => _detectTotalRamMb();

  static int? _detectTotalRamMb() {
    if (!Platform.isAndroid && !Platform.isLinux) return null;
    try {
      final f = File('/proc/meminfo');
      if (!f.existsSync()) return null;
      for (final line in f.readAsLinesSync()) {
        if (!line.startsWith('MemTotal:')) continue;
        final m = RegExp(r'(\d+)\s*kB').firstMatch(line);
        if (m == null) return null;
        return int.parse(m.group(1)!) ~/ 1024;
      }
    } catch (_) {}
    return null;
  }

  factory WhisperConfig.forHost() =>
      WhisperConfig.forLevel(activeTranscriptionPerformance.value);
}
