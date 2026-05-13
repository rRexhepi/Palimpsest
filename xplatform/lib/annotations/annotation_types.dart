import 'package:flutter/material.dart';

/// 5-color highlight palette ported from `App/Components/ParagraphRow.swift`.
/// Names match the Apple side so a future sync feature can ship without a
/// migration.
enum HighlightColor {
  amber,
  sage,
  rose,
  slate,
  plum;

  Color get fill {
    switch (this) {
      case HighlightColor.amber:
        return const Color.fromARGB(140, 232, 191, 110);
      case HighlightColor.sage:
        return const Color.fromARGB(140, 168, 195, 162);
      case HighlightColor.rose:
        return const Color.fromARGB(140, 219, 154, 162);
      case HighlightColor.slate:
        return const Color.fromARGB(140, 168, 178, 196);
      case HighlightColor.plum:
        return const Color.fromARGB(140, 188, 156, 188);
    }
  }

  Color get swatch => fill.withValues(alpha: 1.0);

  String get label {
    switch (this) {
      case HighlightColor.amber:
        return 'Amber';
      case HighlightColor.sage:
        return 'Sage';
      case HighlightColor.rose:
        return 'Rose';
      case HighlightColor.slate:
        return 'Slate';
      case HighlightColor.plum:
        return 'Plum';
    }
  }
}

enum AnnotationKind { highlight, bookmark, note }

/// Anchored to a paragraph by `segmentId` + `paragraphIndex`. Survives a
/// re-import or re-align because both sides agree on the EPUB spine itemref
/// and our deterministic paragraph splitter (split on blank lines).
///
/// `quoteStart` / `quoteEnd` are character offsets inside the paragraph
/// for word- or sentence-range highlights from a drag-selection; both
/// null means the annotation covers the whole paragraph.
class Annotation {
  final String id;
  final String segmentId;
  final int paragraphIndex;
  final AnnotationKind kind;
  final HighlightColor color;
  final String? note;
  final String quote;
  final int? quoteStart;
  final int? quoteEnd;
  final DateTime createdAt;

  const Annotation({
    required this.id,
    required this.segmentId,
    required this.paragraphIndex,
    required this.kind,
    this.color = HighlightColor.amber,
    this.note,
    required this.quote,
    this.quoteStart,
    this.quoteEnd,
    required this.createdAt,
  });

  bool get isRange => quoteStart != null && quoteEnd != null;

  Annotation copyWith({
    AnnotationKind? kind,
    HighlightColor? color,
    String? note,
  }) =>
      Annotation(
        id: id,
        segmentId: segmentId,
        paragraphIndex: paragraphIndex,
        kind: kind ?? this.kind,
        color: color ?? this.color,
        note: note ?? this.note,
        quote: quote,
        quoteStart: quoteStart,
        quoteEnd: quoteEnd,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'segmentId': segmentId,
        'paragraphIndex': paragraphIndex,
        'kind': kind.name,
        'color': color.name,
        'note': note,
        'quote': quote,
        if (quoteStart != null) 'quoteStart': quoteStart,
        if (quoteEnd != null) 'quoteEnd': quoteEnd,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory Annotation.fromJson(Map<String, dynamic> j) => Annotation(
        id: j['id'] as String,
        segmentId: j['segmentId'] as String,
        paragraphIndex: j['paragraphIndex'] as int,
        kind: AnnotationKind.values
            .firstWhere((k) => k.name == j['kind'] as String,
                orElse: () => AnnotationKind.highlight),
        color: HighlightColor.values
            .firstWhere((c) => c.name == j['color'] as String,
                orElse: () => HighlightColor.amber),
        note: j['note'] as String?,
        quote: j['quote'] as String? ?? '',
        quoteStart: j['quoteStart'] as int?,
        quoteEnd: j['quoteEnd'] as int?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
