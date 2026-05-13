import 'dart:io';

import 'package:read_pdf_text/read_pdf_text.dart';

import '../alignment/alignment_types.dart';
import 'ebook_importer.dart';

// Android-only: read_pdf_text wraps PDFBox. Desktop callers go through
// importViaCalibre instead, which produces better text for non-trivial
// layouts.
class PDFImporter implements EBookImporter {
  const PDFImporter();

  @override
  Future<ImportedBook> importBook(File file) async {
    final List<String> pages;
    try {
      pages = await ReadPdfText.getPDFtextPaginated(file.path);
    } catch (e) {
      throw ImporterError('Failed to open PDF: $e');
    }
    if (pages.isEmpty) {
      throw const ImporterError('PDF has no readable pages.');
    }
    final text = pages.join('\n\n');
    if (text.trim().isEmpty) {
      throw const ImporterError(
          'No text in this PDF (likely scanned). Convert to EPUB with Calibre.');
    }

    final filename = file.uri.pathSegments.last;
    final dot = filename.lastIndexOf('.');
    final title = dot <= 0 ? filename : filename.substring(0, dot);

    return ImportedBook(
      title: title,
      author: 'Unknown',
      segments: _splitOnChapterLines(text),
    );
  }
}

final RegExp _chapterLineRe = RegExp(
  r'^\s*(chapter|part|book)\s+'
  r'([ivxlcdm]+|\d+|one|two|three|four|five|six|seven|eight|nine|ten)'
  r'\b[^\n]*$',
  caseSensitive: false,
  multiLine: true,
);

List<TextSegment> _splitOnChapterLines(String text) {
  final hits = _chapterLineRe.allMatches(text).toList();
  if (hits.isEmpty) {
    return [TextSegment(id: 'pdf-1', title: null, text: text.trim())];
  }

  final out = <TextSegment>[];
  if (hits.first.start > 0) {
    final pre = text.substring(0, hits.first.start).trim();
    if (pre.length >= 200) {
      out.add(TextSegment(id: 'pdf-pre', title: null, text: pre));
    }
  }
  for (var i = 0; i < hits.length; i++) {
    final m = hits[i];
    final end = i + 1 < hits.length ? hits[i + 1].start : text.length;
    final body = text.substring(m.start, end).trim();
    if (body.isEmpty) continue;
    final heading =
        text.substring(m.start, m.end).replaceAll(RegExp(r'\s+'), ' ').trim();
    out.add(TextSegment(id: 'pdf-${i + 1}', title: heading, text: body));
  }
  return out;
}
