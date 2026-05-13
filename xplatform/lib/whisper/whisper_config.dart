import 'dart:io';

/// Tunables the Whisper transcription pipeline reads at startup. All
/// `Platform.*` lookups for transcription live in this file so the rest
/// of the pipeline can stay platform-agnostic.
///
/// Design: Linux is the reference. [WhisperConfig.base] is the
/// canonical CPU-multi-worker setup it ships with; [WhisperConfig.forHost]
/// starts from that and applies whatever a given platform needs to
/// override.
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

  /// Linux baseline. Fans the decode across `min(4, cores/2)` workers
  /// with the remaining cores spent inside each recognizer; CPU only.
  /// Every other platform inherits from this and applies a delta.
  factory WhisperConfig.base() {
    final cores = Platform.numberOfProcessors;
    final workers = cores <= 2
        ? 1
        : cores <= 4
            ? 2
            : cores <= 8
                ? 3
                : 4;
    return WhisperConfig(
      workerCount: workers,
      threadsPerWorker: (cores ~/ workers).clamp(1, 4),
      useNNAPI: false,
    );
  }

  /// Resolved config for the current host. Linux / Windows / macOS run
  /// the base config unchanged; mobile constrains worker count so the
  /// phone CPU doesn't end up multi-instance Whispering.
  factory WhisperConfig.forHost() {
    final base = WhisperConfig.base();
    if (Platform.isAndroid || Platform.isIOS) {
      return base.copyWith(workerCount: 1, threadsPerWorker: 2);
    }
    return base;
  }
}
