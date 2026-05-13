import 'dart:convert';

/// One paragraph or chapter of source text addressable by stable id.
/// `id` matches an EPUB spine itemref so anchors round-trip across reimports.
class TextSegment {
  final String id;
  final String? title;
  final String text;

  const TextSegment({required this.id, this.title, required this.text});
}

class AlignmentInput {
  final List<TextSegment> segments;
  const AlignmentInput(this.segments);
}

class WordAnchor {
  final String segmentId;
  final int wordIndex;
  final double startSeconds;
  final double endSeconds;
  final int audioIndex;
  final double confidence;

  const WordAnchor({
    required this.segmentId,
    required this.wordIndex,
    required this.startSeconds,
    required this.endSeconds,
    this.audioIndex = -1,
    required this.confidence,
  });

  factory WordAnchor.fromJson(Map<String, dynamic> j) => WordAnchor(
        segmentId: j['segmentId'] as String,
        wordIndex: j['wordIndex'] as int,
        startSeconds: (j['startSeconds'] as num).toDouble(),
        endSeconds: (j['endSeconds'] as num).toDouble(),
        audioIndex: (j['audioIndex'] as int?) ?? -1,
        confidence: (j['confidence'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'segmentId': segmentId,
        'wordIndex': wordIndex,
        'startSeconds': startSeconds,
        'endSeconds': endSeconds,
        'audioIndex': audioIndex,
        'confidence': confidence,
      };
}

class SentenceAnchor {
  final String segmentId;
  final int sentenceIndex;
  final double startSeconds;
  final double endSeconds;

  const SentenceAnchor({
    required this.segmentId,
    required this.sentenceIndex,
    required this.startSeconds,
    required this.endSeconds,
  });

  factory SentenceAnchor.fromJson(Map<String, dynamic> j) => SentenceAnchor(
        segmentId: j['segmentId'] as String,
        sentenceIndex: j['sentenceIndex'] as int,
        startSeconds: (j['startSeconds'] as num).toDouble(),
        endSeconds: (j['endSeconds'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'segmentId': segmentId,
        'sentenceIndex': sentenceIndex,
        'startSeconds': startSeconds,
        'endSeconds': endSeconds,
      };
}

class AlignmentMap {
  final List<WordAnchor> words;
  final List<SentenceAnchor> sentences;
  /// Per-audio-word start timestamps from Whisper, in order. Index matches
  /// `WordAnchor.audioIndex` so playback can project audio time onto book
  /// position at narrator pace.
  final List<double> audioWordStarts;
  final DateTime createdAt;
  final String modelIdentifier;

  const AlignmentMap({
    required this.words,
    required this.sentences,
    this.audioWordStarts = const [],
    required this.createdAt,
    required this.modelIdentifier,
  });

  factory AlignmentMap.fromJson(Map<String, dynamic> j) => AlignmentMap(
        words: (j['words'] as List)
            .map((e) => WordAnchor.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        sentences: (j['sentences'] as List)
            .map((e) => SentenceAnchor.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        audioWordStarts: (j['audioWordStarts'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList(growable: false) ??
            const [],
        createdAt: DateTime.parse(j['createdAt'] as String),
        modelIdentifier: j['modelIdentifier'] as String,
      );

  factory AlignmentMap.fromJsonString(String s) =>
      AlignmentMap.fromJson(jsonDecode(s) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'words': words.map((w) => w.toJson()).toList(growable: false),
        'sentences': sentences.map((s) => s.toJson()).toList(growable: false),
        'audioWordStarts': audioWordStarts,
        'createdAt': _iso8601Z(createdAt),
        'modelIdentifier': modelIdentifier,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Swift's JSONEncoder.dateEncodingStrategy = .iso8601 emits e.g.
/// "2026-05-07T17:42:57Z" — UTC, second precision, trailing Z. Match that
/// so files written on either platform round-trip identically.
String _iso8601Z(DateTime dt) {
  final u = dt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}
