import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../persistence/library_storage.dart';
import 'annotation_types.dart';

/// One-file-per-book annotations store. Lives at
/// `<bookDir>/annotations.json`. Loaded into memory on first use, written
/// back synchronously on every mutation.
class AnnotationStore extends ChangeNotifier {
  final LibraryStorage storage;
  final StoredBook book;
  final List<Annotation> _items = [];
  bool _loaded = false;

  AnnotationStore({required this.storage, required this.book});

  bool get isLoaded => _loaded;
  List<Annotation> get items => List.unmodifiable(_items);

  List<Annotation> forSegment(String segmentId) =>
      _items.where((a) => a.segmentId == segmentId).toList();

  List<Annotation> forParagraph(String segmentId, int paragraphIndex) => _items
      .where((a) =>
          a.segmentId == segmentId && a.paragraphIndex == paragraphIndex)
      .toList();

  Future<File> _file() async {
    final dir = await storage.bookDir(book.id);
    return File('${dir.path}/annotations.json');
  }

  Future<void> load() async {
    final f = await _file();
    if (!f.existsSync()) {
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      final raw = jsonDecode(await f.readAsString()) as List;
      _items
        ..clear()
        ..addAll(raw.map((e) => Annotation.fromJson(e as Map<String, dynamic>)));
    } catch (_) {
      // Corrupt store — start fresh rather than refusing to open the book.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final f = await _file();
    await f.writeAsString(
      jsonEncode(_items.map((a) => a.toJson()).toList()),
    );
  }

  Future<Annotation> add(Annotation a) async {
    _items.add(a);
    notifyListeners();
    await _save();
    return a;
  }

  Future<void> remove(String id) async {
    _items.removeWhere((a) => a.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> updateNote(String id, String text) async {
    final i = _items.indexWhere((a) => a.id == id);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(note: text);
    notifyListeners();
    await _save();
  }

  Future<void> updateColor(String id, HighlightColor color) async {
    final i = _items.indexWhere((a) => a.id == id);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(color: color);
    notifyListeners();
    await _save();
  }
}
