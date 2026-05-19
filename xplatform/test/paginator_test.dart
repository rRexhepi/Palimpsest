import 'package:flutter_test/flutter_test.dart';
import 'package:ink_and_echo/reader/paginator.dart';

void main() {
  group('Paginator', () {
    test('keeps short chapters on a single page', () {
      final pages = const Paginator(wordsPerPage: 100).paginate(const [
        'Alpha beta gamma delta epsilon zeta.',
        'Eta theta iota kappa.',
      ]);
      expect(pages.length, 1);
      expect(pages.single.paragraphs.length, 2);
    });

    test('breaks paragraphs at sentence boundaries when over budget', () {
      const long =
          'The chronometer chimed twice in the conservatory. Pemberton acknowledged the summons and proceeded toward the marble staircase. Aurelia waited beside the harpsichord, sleeves rustling against the silk drapery as candlelight glittered in the prisms.';
      final pages = const Paginator(wordsPerPage: 12).paginate([long]);
      expect(pages.length, greaterThan(1));
      // First page should not end mid-sentence
      final firstPageText = pages.first.paragraphs.last;
      expect(
        firstPageText.endsWith('.') || firstPageText.endsWith('?') ||
            firstPageText.endsWith('!'),
        isTrue,
        reason: 'page should end on a sentence boundary',
      );
    });

    test('marks continuations across pages', () {
      const long =
          'A. B. C. D. E. F. G. H. I. J. K. L. M. N. O. P. Q. R. S. T.';
      final pages = const Paginator(wordsPerPage: 6).paginate([long]);
      expect(pages.length, greaterThan(1));
      // All but the first page should start as a continuation.
      for (var i = 1; i < pages.length; i++) {
        expect(pages[i].startsContinuation, isTrue);
      }
      // All but the last page should end as a continuation.
      for (var i = 0; i < pages.length - 1; i++) {
        expect(pages[i].endsContinuation, isTrue);
      }
    });

    test('empty input produces no pages', () {
      expect(const Paginator().paginate(const []), isEmpty);
    });

    test('a giant single-sentence paragraph still produces a page', () {
      final words = List.generate(300, (i) => 'word$i').join(' ');
      final pages = const Paginator(wordsPerPage: 50).paginate(['$words.']);
      expect(pages, isNotEmpty);
    });
  });
}
