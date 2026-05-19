import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_and_echo/import/ebook_importer.dart';

void main() {
  group('EPUBImporter against Crime and Punishment fixture', () {
    final fixture = File('test/fixtures/sample.epub');
    late ImportedBook book;

    setUpAll(() async {
      book = await const EPUBImporter().importBook(fixture);
    });

    test('extracts title and author', () {
      expect(book.title.toLowerCase(), contains('crime'));
      expect(book.author.isNotEmpty, isTrue);
      expect(book.author, isNot('Unknown'));
    });

    test('produces a non-trivial spine of segments', () {
      expect(book.segments.length, greaterThan(5),
          reason: 'a novel should have several chapters / spine items');
      for (final s in book.segments) {
        expect(s.id.isNotEmpty, isTrue);
        expect(s.text.isNotEmpty, isTrue);
      }
    });

    test('segments have stable spine-itemref ids (not auto-generated)', () {
      final ids = book.segments.map((s) => s.id).toSet();
      expect(ids.length, book.segments.length,
          reason: 'spine ids must be unique');
    });

    test('attaches chapter titles from TOC where present', () {
      final titled = book.segments.where((s) => (s.title ?? '').isNotEmpty);
      expect(titled.length, greaterThan(0),
          reason: 'TOC parsing should hit at least some segments');
    });

    test('strips HTML to plain text', () {
      for (final s in book.segments) {
        expect(s.text.contains('<'), isFalse,
            reason: 'segment "${s.id}" still contains a "<"');
        expect(s.text.contains('>'), isFalse,
            reason: 'segment "${s.id}" still contains a ">"');
      }
    });

    test('preserves paragraph breaks between block elements', () {
      final hasParagraphs =
          book.segments.any((s) => s.text.contains('\n\n'));
      expect(hasParagraphs, isTrue);
    });

    test('text is long enough to feed the aligner', () {
      final totalChars =
          book.segments.fold<int>(0, (a, s) => a + s.text.length);
      expect(totalChars, greaterThan(100000),
          reason: 'a full novel should produce >100k chars of plain text');
    });
  });

  group('stripHTML', () {
    test('decodes named entities', () {
      expect(stripHTML('a &amp; b &lt;c&gt;'), 'a & b <c>');
    });

    test('drops script and style blocks entirely', () {
      const html =
          '<p>before</p><script>alert(1)</script><style>body{}</style><p>after</p>';
      final out = stripHTML(html);
      expect(out.contains('alert'), isFalse);
      expect(out.contains('body'), isFalse);
      expect(out.contains('before'), isTrue);
      expect(out.contains('after'), isTrue);
    });

    test('converts <br> and block-end tags to whitespace', () {
      const html = '<p>one</p><p>two<br>three</p>';
      final out = stripHTML(html);
      expect(out.split(RegExp(r'\s+')).length, 3);
    });
  });
}
