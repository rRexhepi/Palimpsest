/// Word-budget paginator. Mirrors the Apple build's split: ~170 words per
/// single page on phone, ~120 words per page in two-page spread mode (we
/// only do single-page on Android right now). When a paragraph would push
/// the running word count past the budget, close the page on the nearest
/// sentence boundary.
///
/// Output: list of `Page`, each containing a list of paragraph strings to
/// render in order. Sentence-level overflow keeps the same paragraph
/// straddling two pages, with a partial-tail flag so the renderer can omit
/// indentation on the continuation.
class ReaderPage {
  final List<String> paragraphs;
  final bool startsContinuation;
  final bool endsContinuation;
  const ReaderPage({
    required this.paragraphs,
    this.startsContinuation = false,
    this.endsContinuation = false,
  });
}

class Paginator {
  final int wordsPerPage;

  const Paginator({this.wordsPerPage = 170});

  /// `paragraphs` are already paragraph-split + soft-wrap-collapsed (the
  /// reader does that pre-pass on the segment text).
  List<ReaderPage> paginate(List<String> paragraphs) {
    if (paragraphs.isEmpty) return const [];
    final pages = <ReaderPage>[];
    final current = <String>[];
    var currentWords = 0;
    var startsContinuation = false;

    void flush({required bool endsContinuation}) {
      if (current.isEmpty) return;
      pages.add(ReaderPage(
        paragraphs: List<String>.from(current),
        startsContinuation: startsContinuation,
        endsContinuation: endsContinuation,
      ));
      current.clear();
      currentWords = 0;
      startsContinuation = endsContinuation;
    }

    for (final original in paragraphs) {
      var remaining = original;
      while (true) {
        final remainingWords = _wordCount(remaining);
        if (currentWords + remainingWords <= wordsPerPage) {
          current.add(remaining);
          currentWords += remainingWords;
          break;
        }
        // Try to split on a sentence boundary so the page closes cleanly.
        final budgetLeft = wordsPerPage - currentWords;
        final split = _splitOnSentence(
          remaining,
          maxWords: budgetLeft > 0 ? budgetLeft : 1,
        );
        if (split == null) {
          // No reachable boundary. If page is non-empty, close it and try
          // again on a fresh page. If page is already empty (giant single-
          // sentence paragraph), force it on its own page.
          if (current.isEmpty) {
            current.add(remaining);
            currentWords += remainingWords;
            break;
          }
          flush(endsContinuation: false);
          continue;
        }
        final (head, tail) = split;
        current.add(head);
        flush(endsContinuation: true);
        remaining = tail;
      }
    }
    flush(endsContinuation: false);
    return pages;
  }
}

int _wordCount(String s) =>
    s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// Split `p` so that `head` ends at a sentence boundary and contains at
/// most `maxWords` words. Returns null if no usable boundary is reachable
/// (e.g. paragraph is one giant sentence longer than the budget).
(String head, String tail)? _splitOnSentence(
  String p, {
  required int maxWords,
}) {
  if (maxWords <= 0) return null;
  final boundaries = <int>[];
  for (var i = 0; i < p.length; i++) {
    final ch = p[i];
    if (ch == '.' || ch == '!' || ch == '?') {
      var j = i + 1;
      while (j < p.length &&
          (p[j] == '"' ||
              p[j] == "'" ||
              p[j] == '”' ||
              p[j] == '’' ||
              p[j] == ')')) {
        j++;
      }
      if (j >= p.length || _isWs(p[j])) {
        boundaries.add(j);
      }
    }
  }
  if (boundaries.isEmpty) return null;

  int? bestEnd;
  for (final end in boundaries) {
    final head = p.substring(0, end);
    final w = _wordCount(head);
    if (w == 0) continue;
    if (w <= maxWords) {
      bestEnd = end;
    } else {
      break;
    }
  }
  if (bestEnd == null) return null;
  final head = p.substring(0, bestEnd).trim();
  final tail = p.substring(bestEnd).trim();
  if (head.isEmpty || tail.isEmpty) return null;
  return (head, tail);
}

bool _isWs(String ch) =>
    ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
