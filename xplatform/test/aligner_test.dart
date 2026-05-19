import 'package:flutter_test/flutter_test.dart';
import 'package:ink_and_echo/alignment/aligner.dart';
import 'package:ink_and_echo/alignment/alignment_types.dart';

/// Build a synthetic narrator-as-Whisper word stream from sentence text.
/// Each word lasts `wordSec`, gap of `gapSec` between.
List<AudioWord> _narrate(String text,
    {double wordSec = 0.4, double gapSec = 0.1, double startAt = 0.0}) {
  final words = text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
  final out = <AudioWord>[];
  var t = startAt;
  for (final w in words) {
    out.add(AudioWord(
      text: w,
      startSeconds: t,
      endSeconds: t + wordSec,
      confidence: 0.95,
    ));
    t += wordSec + gapSec;
  }
  return out;
}

void main() {
  group('Aligner', () {
    final aligner = const Aligner();

    test('matches distinctive book words to audio anchors', () {
      const chapter =
          'The chronometer chimed twice. Pemberton acknowledged the summons '
          'and proceeded toward the conservatory, his footsteps echoing on '
          'the marble. Aurelia waited beside the harpsichord, sleeves '
          'rustling against the silk drapery.';
      final segments = [const TextSegment(id: 'ch1', text: chapter)];
      final audio = _narrate(chapter);

      final map = aligner.align(audio: audio, segments: segments);

      expect(map.words, isNotEmpty);
      expect(map.audioWordStarts.length, audio.length);

      final anchored = map.words.map((w) => w.wordIndex).toSet();
      final tokens = chapter.split(RegExp(r'\s+'));
      for (final idx in anchored) {
        expect(tokens[idx].length >= 5, isTrue,
            reason: 'short words should never anchor');
      }

      for (var i = 1; i < map.words.length; i++) {
        expect(map.words[i].audioIndex, greaterThan(map.words[i - 1].audioIndex),
            reason: 'anchors must advance through the audio cursor');
      }
    });

    test('rejects common short words like "the"', () {
      const chapter = 'the the the the the the';
      final audio = _narrate(chapter);
      final map = aligner.align(
        audio: audio,
        segments: [const TextSegment(id: 's', text: chapter)],
      );
      expect(map.words, isEmpty,
          reason: '"the" is too short and too common, never anchors');
    });

    test('handles narrator filler skipping', () {
      const chapter =
          'Pemberton declared that the conservatory glittered with candlelight.';
      final audio = <AudioWord>[
        ..._narrate('uh um', startAt: 0.0),
        ..._narrate(chapter, startAt: 1.0),
      ];
      final map = aligner.align(
        audio: audio,
        segments: [const TextSegment(id: 's', text: chapter)],
      );
      expect(map.words, isNotEmpty);
      expect(map.words.first.startSeconds, greaterThan(0.5),
          reason: 'first anchor should land past the filler tokens');
    });

    test('produces sentence anchors when words land in a sentence', () {
      const chapter =
          'The chronometer chimed twice. Pemberton walked toward the '
          'conservatory. Aurelia waited beside the harpsichord.';
      final audio = _narrate(chapter);
      final map = aligner.align(
        audio: audio,
        segments: [const TextSegment(id: 's', text: chapter)],
      );
      expect(map.sentences, isNotEmpty);
      for (var i = 1; i < map.sentences.length; i++) {
        expect(map.sentences[i].sentenceIndex,
            greaterThan(map.sentences[i - 1].sentenceIndex));
      }
    });

    test('emits empty map for empty inputs', () {
      final emptyAudio = const Aligner().align(
        audio: const [],
        segments: [const TextSegment(id: 's', text: 'foo bar baz')],
      );
      expect(emptyAudio.words, isEmpty);

      final emptyText = const Aligner().align(
        audio: _narrate('Pemberton'),
        segments: const [],
      );
      expect(emptyText.words, isEmpty);
    });

    test('roundtrips through JSON', () {
      const chapter =
          'The chronometer chimed twice. Pemberton acknowledged the summons '
          'and proceeded toward the conservatory.';
      final audio = _narrate(chapter);
      final original = aligner.align(
        audio: audio,
        segments: [const TextSegment(id: 'ch1', text: chapter)],
      );
      final reparsed = AlignmentMap.fromJsonString(original.toJsonString());
      expect(reparsed.words.length, original.words.length);
      expect(reparsed.audioWordStarts.length, original.audioWordStarts.length);
    });
  });

  group('sentenceWordRanges', () {
    test('splits on terminal punctuation followed by whitespace', () {
      const t = 'Alpha beta gamma. Delta epsilon. Zeta eta theta.';
      final ranges = sentenceWordRanges(t);
      expect(ranges.length, 3);
      expect(ranges[0].start, 0);
      expect(ranges[0].end, 3);
      expect(ranges[1].start, 3);
      expect(ranges[1].end, 5);
      expect(ranges[2].start, 5);
      expect(ranges[2].end, 8);
    });

    test('treats trailing sentence without terminal punctuation', () {
      const t = 'Alpha beta. Gamma delta epsilon';
      final ranges = sentenceWordRanges(t);
      expect(ranges.length, 2);
      expect(ranges[1].end, 5);
    });
  });
}
