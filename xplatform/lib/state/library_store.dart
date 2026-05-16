import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../alignment/alignment_service.dart';
import '../alignment/alignment_types.dart';
import '../import/ebook_importer.dart';
import '../import/mobi_importer.dart';
import '../import/pdf_importer.dart';
import '../persistence/library_storage.dart';

class LibraryStore extends ChangeNotifier {
  final LibraryStorage storage;
  final AlignmentService alignment;
  final List<StoredBook> _books = [];
  bool _loaded = false;
  bool _importing = false;
  String? _lastError;

  LibraryStore({LibraryStorage? storage, AlignmentService? alignment})
      : storage = storage ?? LibraryStorage(),
        alignment = alignment ??
            AlignmentService(storage: storage ?? LibraryStorage());

  List<StoredBook> get books => List.unmodifiable(_books);
  bool get isImporting => _importing;
  bool get isLoaded => _loaded;
  String? get lastError => _lastError;

  Future<void> load() async {
    try {
      final all = await storage.loadAll();
      _books
        ..clear()
        ..addAll(all);
    } catch (e) {
      // Path provider can be unavailable in widget tests; degrade gracefully
      // to an empty in-memory library rather than crashing the UI.
      _lastError = 'Failed to load library: $e';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<StoredBook?> importViaCalibre(File source) async {
    _importing = true;
    _lastError = null;
    notifyListeners();
    Directory? tmpDir;
    final label = source.path.split('.').last.toUpperCase();
    try {
      tmpDir = await Directory.systemTemp.createTemp('palimp_calibre_');
      final tmpEpub = File('${tmpDir.path}/converted.epub');
      final exe = Platform.environment['PALIMPSEST_EBOOK_CONVERT'] ??
          (Platform.isWindows ? 'ebook-convert.exe' : 'ebook-convert');
      final proc = await Process.run(exe, [source.path, tmpEpub.path]);
      if (proc.exitCode != 0 || !tmpEpub.existsSync()) {
        _lastError =
            '$label conversion failed. Install Calibre and ensure '
            '`ebook-convert` is on PATH (or set PALIMPSEST_EBOOK_CONVERT).'
            '\n${proc.stderr}';
        return null;
      }
      // Hand off to the EPUB importer; clear the flag first so it can
      // re-set it without tripping the double-import guard.
      _importing = false;
      return await importEPUB(tmpEpub);
    } on ProcessException catch (e) {
      _lastError =
          '$label conversion failed: ${e.message}. '
          'Install Calibre and ensure `ebook-convert` is on PATH '
          '(or set PALIMPSEST_EBOOK_CONVERT).';
      return null;
    } catch (e) {
      _lastError = '$label conversion failed: $e';
      return null;
    } finally {
      try {
        tmpDir?.deleteSync(recursive: true);
      } catch (_) {}
      _importing = false;
      notifyListeners();
    }
  }

  Future<StoredBook?> importBook(File file) {
    final lower = file.path.toLowerCase();
    if (lower.endsWith('.epub')) return importEPUB(file);
    if (lower.endsWith('.mobi') ||
        lower.endsWith('.prc') ||
        lower.endsWith('.azw')) {
      return importMOBI(file);
    }
    if (lower.endsWith('.pdf') && Platform.isAndroid) return importPDF(file);
    return importViaCalibre(file);
  }

  Future<StoredBook?> importEPUB(File file) =>
      _runImport(file, 'book.epub', const EPUBImporter());

  Future<StoredBook?> importMOBI(File file) =>
      _runImport(file, 'book.mobi', const MOBIImporter());

  // Android only; desktop goes through importViaCalibre for better fidelity.
  Future<StoredBook?> importPDF(File file) =>
      _runImport(file, 'book.pdf', const PDFImporter());

  Future<StoredBook?> _runImport(
    File source,
    String storedFilename,
    EBookImporter importer,
  ) async {
    _importing = true;
    _lastError = null;
    notifyListeners();
    try {
      final imported = await importer.importBook(source);
      final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final dir = await storage.bookDir(id);
      final dest = File('${dir.path}/$storedFilename');
      await source.copy(dest.path);

      String? coverPath;
      if (imported.coverImageData != null) {
        final c = File('${dir.path}/cover');
        await c.writeAsBytes(imported.coverImageData!);
        coverPath = c.path;
      }

      final book = StoredBook(
        id: id,
        title: imported.title,
        author: imported.author,
        segments: imported.segments,
        coverPath: coverPath,
        addedAt: DateTime.now().toUtc(),
      );
      await storage.save(book);
      _books.insert(0, book);
      return book;
    } catch (e) {
      _lastError = e.toString();
      return null;
    } finally {
      _importing = false;
      notifyListeners();
    }
  }

  Future<StoredBook> attachAudio(StoredBook book, File audio) async {
    final dir = await storage.bookDir(book.id);
    final ext = audio.path.split('.').last;
    final dest = File('${dir.path}/audiobook.$ext');

    _clearStaleAudioArtifacts(dir);
    await audio.copy(dest.path);

    final updated = _withReplacedAudio(book, audioPath: dest.path);
    await _replace(updated);
    return updated;
  }

  /// Drops every prior `audiobook.*` file (the new pick may have a different
  /// extension) and the alignment JSON it was computed against. Without this,
  /// swapping in a different audiobook would leave a stale alignment.json
  /// that the next reader open would happily reload — wrong word timestamps,
  /// paragraphs jumping to the wrong audio position.
  void _clearStaleAudioArtifacts(Directory dir) {
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.startsWith('audiobook.') || name == 'alignment.json') {
        try {
          entity.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// `copyWith` can't set `alignmentPath` back to null (its `?? this.x`
  /// keeps the old value when you pass null), so we build directly.
  StoredBook _withReplacedAudio(StoredBook book, {required String audioPath}) =>
      StoredBook(
        id: book.id,
        title: book.title,
        author: book.author,
        segments: book.segments,
        coverPath: book.coverPath,
        audioPath: audioPath,
        alignmentPath: null,
        addedAt: book.addedAt,
        currentSegmentIndex: book.currentSegmentIndex,
        currentPageInChapter: book.currentPageInChapter,
        currentAudioSeconds: book.currentAudioSeconds,
      );

  Future<AlignmentMap?> loadAlignment(StoredBook book) =>
      storage.loadAlignment(book);

  Stream<AlignStage> alignBook(StoredBook book) async* {
    await for (final stage in alignment.alignBook(book)) {
      yield stage;
    }
    final dir = await storage.bookDir(book.id);
    final updated = book.copyWith(
      alignmentPath: '${dir.path}/alignment.json',
    );
    await _replace(updated);
  }

  Future<void> updateProgress(
    StoredBook book, {
    int? segmentIndex,
    int? pageInChapter,
    double? audioSeconds,
  }) async {
    final updated = book.copyWith(
      currentSegmentIndex: segmentIndex,
      currentPageInChapter: pageInChapter,
      currentAudioSeconds: audioSeconds,
    );
    await _replace(updated, notify: false);
  }

  Future<void> _replace(StoredBook updated, {bool notify = true}) async {
    final i = _books.indexWhere((b) => b.id == updated.id);
    if (i >= 0) _books[i] = updated;
    await storage.save(updated);
    if (notify) notifyListeners();
  }

  Future<void> delete(StoredBook book) async {
    await storage.delete(book.id);
    _books.removeWhere((b) => b.id == book.id);
    notifyListeners();
  }
}
