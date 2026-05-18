import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../persistence/library_storage.dart';
import '../whisper/whisper_transcriber.dart';
import 'aligner.dart';
import 'alignment_types.dart';

class AlignStage {
  final String label;
  final double? fraction;
  const AlignStage(this.label, {this.fraction});
}

/// Orchestrator: download model → transcribe audio → run aligner → write
/// alignment.json next to the book. Mirrors `AlignmentService.swift`'s
/// surface from the Apple build.
class AlignmentService {
  final LibraryStorage storage;
  final Aligner aligner;
  WhisperTranscriber? _transcriber;
  final WhisperTranscriber Function()? _transcriberFactory;

  AlignmentService({
    required this.storage,
    WhisperTranscriber? transcriber,
    Aligner? aligner,
    WhisperTranscriber Function()? transcriberFactory,
  })  : aligner = aligner ?? const Aligner(),
        _transcriber = transcriber,
        _transcriberFactory = transcriberFactory;

  /// Lazily build the transcriber so the FFmpeg + ffi plugins don't load
  /// in tests / on screens that never trigger alignment.
  WhisperTranscriber get transcriber {
    final existing = _transcriber;
    if (existing != null) return existing;
    final created = (_transcriberFactory ?? WhisperTranscriber.new)();
    _transcriber = created;
    return created;
  }

  /// Tear down any spawned worker pool so the next alignment respawns
  /// it from [WhisperConfig.forHost] — picks up live changes to the
  /// transcription performance setting without restarting the app.
  Future<void> resetTranscriberPool() async {
    final existing = _transcriber;
    if (existing == null) return;
    await existing.resetPool();
  }

  Stream<AlignStage> alignBook(StoredBook book) async* {
    if (book.audioPath == null) {
      throw StateError('Book ${book.id} has no audio attached');
    }
    final audioFile = File(book.audioPath!);
    if (!audioFile.existsSync()) {
      throw StateError('Audio file missing on disk: ${book.audioPath}');
    }

    await for (final p in transcriber.downloadModel()) {
      yield AlignStage(p.label, fraction: p.fraction);
    }

    // Transcript cache, keyed by sha256(audio). Same audiobook attached to
    // a different book record, or re-aligned after replacing the EPUB, both
    // skip the multi-minute Whisper pass.
    yield const AlignStage('Hashing audio…', fraction: 0.02);
    final audioHash = await _sha256OfFile(audioFile);
    final cacheFile = await _transcriptCacheFile(audioHash);
    List<AudioWord> audioWords = const [];
    final cached = _readTranscriptCache(cacheFile);
    if (cached != null) {
      audioWords = cached;
      yield AlignStage(
        'Loaded cached transcript (${cached.length} words).',
        fraction: 0.95,
      );
    } else {
      // Chunked transcribe is required, not optional: whisper loads the
      // chunk's WAV into a float buffer (4 B × 16 kHz × duration), so a
      // 25-hour audiobook would need ~5.7 GB if done in one pass. JIT
      // slicing keeps the working set to one chunk (~115 MB) and emits a
      // real `i / N` fraction the UI can render.
      await for (final p in transcriber.transcribeChunked(audioFile)) {
        if (p.words != null) {
          audioWords = p.words!;
        }
        yield AlignStage(p.label, fraction: p.fraction);
      }
      // Write best-effort. A cache write failure shouldn't fail the align.
      try {
        await _writeTranscriptCache(cacheFile, audioWords);
      } catch (_) {}
    }

    yield const AlignStage('Aligning transcript to ebook…', fraction: 0.98);
    final map = aligner.align(
      audio: audioWords,
      segments: book.segments,
    );

    await storage.writeAlignment(book, map);
    yield AlignStage(
      'Done — ${map.words.length} word anchors, '
      '${map.sentences.length} sentence anchors.',
      fraction: 1.0,
    );
  }

  /// Audio time the narrator says the given paragraph word.
  ///
  /// Picks the two anchors that bracket the target in global book order, then
  /// linearly interpolates an audio-word index between them and reads the
  /// corresponding entry out of `audioWordStarts`. This works across segment
  /// boundaries — paragraphs with zero anchors of their own still resolve, as
  /// long as some anchor exists before and another after them in the book.
  /// One-sided extrapolation kicks in at the very head and tail.
  ///
  /// The old behavior (return the nearest in-segment anchor's startSeconds)
  /// often started playback several words late, because the nearest anchor
  /// sat somewhere in the middle of the paragraph rather than at its start.
  static double? seekTimeForParagraph(
    AlignmentMap map, {
    required List<TextSegment> segments,
    required String segmentId,
    int wordIndex = 0,
  }) {
    if (map.words.isEmpty || map.audioWordStarts.isEmpty) return null;

    // Build (segmentId -> [order index, cumulative word offset]) once. Word
    // counts use the same whitespace tokenization the aligner does so the
    // wordIndex on a WordAnchor lines up with this table.
    final segOrder = <String, int>{};
    final segCumStart = <String, int>{};
    var cumulative = 0;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      segOrder[seg.id] = i;
      segCumStart[seg.id] = cumulative;
      cumulative +=
          seg.text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;
    }
    if (!segOrder.containsKey(segmentId)) return null;
    final targetGlobal = (segCumStart[segmentId] ?? 0) + wordIndex;

    // Sort anchors by global book position. Skip anchors whose segmentId
    // isn't in the current spine (defensive — a re-import that dropped
    // some segments shouldn't crash playback).
    int? globalOf(WordAnchor a) {
      final base = segCumStart[a.segmentId];
      if (base == null) return null;
      return base + a.wordIndex;
    }
    final ordered = map.words
        .where((a) => segOrder.containsKey(a.segmentId) && a.audioIndex >= 0)
        .toList()
      ..sort((a, b) => globalOf(a)!.compareTo(globalOf(b)!));
    if (ordered.isEmpty) return null;

    double timeForAudioIndex(int idx) {
      if (idx < 0) return map.audioWordStarts.first;
      if (idx >= map.audioWordStarts.length) {
        return map.audioWordStarts.last;
      }
      return map.audioWordStarts[idx];
    }

    // Find the rightmost anchor with globalIdx <= target (prev), and the
    // leftmost with globalIdx >= target (next). Linear scan — even 10k
    // anchors is microseconds per tap.
    WordAnchor? prev;
    WordAnchor? next;
    for (final a in ordered) {
      final g = globalOf(a)!;
      if (g <= targetGlobal) prev = a;
      if (g >= targetGlobal) {
        next = a;
        break;
      }
    }

    // Exact match on the prev anchor: skip the interpolation math.
    if (prev != null && globalOf(prev)! == targetGlobal) {
      return timeForAudioIndex(prev.audioIndex);
    }

    // Bracketed by two distinct anchors → interpolate in audio-index space.
    if (prev != null && next != null && prev != next) {
      final bookSpan = globalOf(next)! - globalOf(prev)!;
      final audioSpan = next.audioIndex - prev.audioIndex;
      if (bookSpan > 0) {
        final fraction = (targetGlobal - globalOf(prev)!) / bookSpan;
        final audioIdx =
            (prev.audioIndex + fraction * audioSpan).round();
        return timeForAudioIndex(audioIdx);
      }
    }

    // One-sided — extrapolate from the nearest anchor + an estimated rate
    // taken from its closest neighbor in `ordered`. Falls back to the
    // anchor's own time if a rate can't be computed.
    final anchor = prev ?? next!;
    final anchorPos = ordered.indexOf(anchor);
    final neighborPos =
        prev != null ? anchorPos - 1 : anchorPos + 1;
    if (neighborPos >= 0 && neighborPos < ordered.length) {
      final neighbor = ordered[neighborPos];
      final bookSpan = (globalOf(anchor)! - globalOf(neighbor)!).abs();
      final audioSpan = (anchor.audioIndex - neighbor.audioIndex).abs();
      if (bookSpan > 0) {
        final rate = audioSpan / bookSpan;
        final delta = targetGlobal - globalOf(anchor)!;
        final audioIdx = (anchor.audioIndex + delta * rate).round();
        return timeForAudioIndex(audioIdx);
      }
    }
    return timeForAudioIndex(anchor.audioIndex);
  }
}

/// Streaming sha256 of a file. Reads in 1 MB chunks so a 100+ MB M4B
/// doesn't sit in memory just to compute its hash.
Future<String> _sha256OfFile(File f) async {
  final digest = await sha256.bind(f.openRead()).first;
  return digest.toString();
}

Future<File> _transcriptCacheFile(String sha256Hex) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/transcript_cache');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return File('${dir.path}/$sha256Hex.json');
}

// Bump this whenever the transcription pipeline changes in a way that
// makes previously-cached transcripts no longer correct — caches with a
// different version are silently ignored, forcing a fresh transcription.
//
// History:
//  - v1: initial release (600s chunks; Whisper truncating to 30s; word
//        timestamps collapsed to chunk boundaries).
//  - v2: 30s chunks, linear timestamp fallback.
const int _kTranscriptCacheVersion = 2;

List<AudioWord>? _readTranscriptCache(File f) {
  if (!f.existsSync()) return null;
  try {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final v = json['version'];
    if (v is! int || v != _kTranscriptCacheVersion) return null;
    final list = (json['words'] as List)
        .map((e) => AudioWord.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return list;
  } catch (_) {
    // Corrupted cache — pretend it doesn't exist; the next write replaces it.
    return null;
  }
}

Future<void> _writeTranscriptCache(File f, List<AudioWord> words) async {
  final tmp = File('${f.path}.part');
  await tmp.writeAsString(jsonEncode({
    'version': _kTranscriptCacheVersion,
    'words': words.map((w) => w.toJson()).toList(growable: false),
  }));
  await tmp.rename(f.path);
}
