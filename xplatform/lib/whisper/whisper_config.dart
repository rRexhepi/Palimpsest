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

/// Live perf level shared across the app. main.dart writes it on startup
/// after reading SharedPreferences and again whenever the user changes
/// the setting; [WhisperTranscriber] reads it lazily when spawning its
/// worker pool, so changes take effect on the next transcription run.
final ValueNotifier<TranscriptionPerformance> activeTranscriptionPerformance =
    ValueNotifier<TranscriptionPerformance>(TranscriptionPerformance.balanced);

/// Tunables the Whisper transcription pipeline reads when spawning its
/// worker pool. All `Platform.*` lookups for transcription live in this
/// file so the rest of the pipeline can stay platform-agnostic.
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

  /// Resolved config for the current host at [level]. The skeleton picks
  /// the platform's scaling strategy; each strategy decides how cores +
  /// RAM map to workers + threads given that platform's constraints
  /// (phones throttle on heat / battery / foreground responsiveness;
  /// desktops assume plug-in power and lean into the chip).
  ///
  /// Each Whisper worker holds ~270 MB of int8 quantized weights plus a
  /// per-decode working set; the strategies budget RAM accordingly.
  factory WhisperConfig.forLevel(TranscriptionPerformance level) =>
      (Platform.isAndroid || Platform.isIOS)
          ? _mobileForLevel(level)
          : _desktopForLevel(level);

  /// Sensible default tier per platform. Mobile defaults to [balanced] so
  /// transcription stays the user's foreground choice without pegging
  /// every core; desktop defaults to [max] since the chip has the
  /// thermal headroom and the user is at a plugged-in machine.
  static TranscriptionPerformance get defaultForHost =>
      (Platform.isAndroid || Platform.isIOS)
          ? TranscriptionPerformance.balanced
          : TranscriptionPerformance.max;

  /// Phone strategy. Conservative on workers because each one pins
  /// 270 MB of resident model and a phone OS treats sustained CPU + RAM
  /// pressure as a thermal + lifecycle problem. ONNX Runtime stops
  /// scaling past 4 intra-op threads, so we spend cores beyond that on
  /// a second worker when (and only when) the phone has the RAM.
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

  /// Desktop strategy. Workers scale with cores up to a hard ceiling of
  /// 4 (above that, ORT contention + L3 thrash starts eating the win).
  /// Each worker still wants the same 4 intra-op threads, so the box
  /// ends up doing `workers × 4` concurrent transcribes — matches the
  /// pre-tunable `base()` behavior the app shipped with.
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

  /// Total system RAM in megabytes for the current device, or null when
  /// the platform doesn't expose it via a file we can read cheaply.
  /// Exposed for Settings UI so the user can see the detection result.
  static int? get totalRamMb => _detectTotalRamMb();

  /// Total system RAM in megabytes, read from `/proc/meminfo` on Linux
  /// and Android (the kernel exposes it there for both). Returns null on
  /// iOS/macOS/Windows — those need a platform channel to ask the OS
  /// memory APIs, and we'd rather degrade to core-only scaling than
  /// add a method-channel round-trip during pool spawn.
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

  /// Resolved config for whatever perf level is currently active.
  factory WhisperConfig.forHost() =>
      WhisperConfig.forLevel(activeTranscriptionPerformance.value);
}
