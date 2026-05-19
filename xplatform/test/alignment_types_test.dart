import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_and_echo/alignment/alignment_types.dart';

void main() {
  group('AlignmentMap', () {
    final fixture = File('test/fixtures/alignment.json');

    test('parses real Apple-built alignment.json', () {
      final raw = fixture.readAsStringSync();
      final map = AlignmentMap.fromJsonString(raw);

      expect(map.modelIdentifier, 'openai_whisper-base.en');
      expect(map.createdAt.toUtc().toIso8601String(),
          startsWith('2026-05-07T17:42:57'));
      expect(map.words, isNotEmpty);
      expect(map.sentences, isNotEmpty);
      expect(map.audioWordStarts, isNotEmpty);

      final firstWord = map.words.first;
      expect(firstWord.segmentId, 'id47');
      expect(firstWord.wordIndex, 7);
      expect(firstWord.audioIndex, 92);
      expect(firstWord.startSeconds, closeTo(60.66, 0.01));
      expect(firstWord.endSeconds, closeTo(61.32, 0.01));
      expect(firstWord.confidence, closeTo(0.99, 0.01));
    });

    test('round-trips structurally (parse -> serialize -> parse)', () {
      final raw = fixture.readAsStringSync();
      final original = AlignmentMap.fromJsonString(raw);
      final reserialized = original.toJsonString();
      final reparsed = AlignmentMap.fromJsonString(reserialized);

      expect(reparsed.words.length, original.words.length);
      expect(reparsed.sentences.length, original.sentences.length);
      expect(reparsed.audioWordStarts.length, original.audioWordStarts.length);
      expect(reparsed.modelIdentifier, original.modelIdentifier);
      expect(reparsed.createdAt.toUtc(), original.createdAt.toUtc());

      for (var i = 0; i < original.words.length; i++) {
        final a = original.words[i];
        final b = reparsed.words[i];
        expect(b.segmentId, a.segmentId, reason: 'word $i segmentId');
        expect(b.wordIndex, a.wordIndex, reason: 'word $i wordIndex');
        expect(b.audioIndex, a.audioIndex, reason: 'word $i audioIndex');
        expect(b.startSeconds, a.startSeconds, reason: 'word $i start');
        expect(b.endSeconds, a.endSeconds, reason: 'word $i end');
        expect(b.confidence, a.confidence, reason: 'word $i confidence');
      }
      for (var i = 0; i < original.sentences.length; i++) {
        final a = original.sentences[i];
        final b = reparsed.sentences[i];
        expect(b.segmentId, a.segmentId);
        expect(b.sentenceIndex, a.sentenceIndex);
        expect(b.startSeconds, a.startSeconds);
        expect(b.endSeconds, a.endSeconds);
      }
      for (var i = 0; i < original.audioWordStarts.length; i++) {
        expect(reparsed.audioWordStarts[i], original.audioWordStarts[i]);
      }
    });

    test('createdAt encodes back to ISO 8601 UTC with trailing Z', () {
      final raw = fixture.readAsStringSync();
      final map = AlignmentMap.fromJsonString(raw);
      final encoded = jsonDecode(map.toJsonString()) as Map<String, dynamic>;
      expect(encoded['createdAt'], '2026-05-07T17:42:57Z');
    });

    test('tolerates missing optional fields', () {
      final minimal = jsonEncode({
        'words': [
          {
            'segmentId': 'x',
            'wordIndex': 0,
            'startSeconds': 1.0,
            'endSeconds': 2.0,
            'confidence': 0.9,
          }
        ],
        'sentences': [],
        'createdAt': '2026-01-01T00:00:00Z',
        'modelIdentifier': 'test',
      });
      final map = AlignmentMap.fromJsonString(minimal);
      expect(map.audioWordStarts, isEmpty);
      expect(map.words.first.audioIndex, -1);
    });
  });
}
