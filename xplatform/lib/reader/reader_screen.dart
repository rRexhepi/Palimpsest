import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../alignment/alignment_service.dart';
import '../alignment/alignment_types.dart';
import '../annotations/annotation_store.dart';
import '../annotations/annotation_types.dart';
import '../audio/audio_player.dart';
import '../persistence/library_storage.dart';
import '../state/library_store.dart';
import '../theme.dart';
import 'audio_sheet.dart';
import 'curl_page_view.dart';
import 'paginator.dart';

const _kHeaderHeight = 44.0;
const _kPagePadding = EdgeInsets.fromLTRB(28, 14, 28, 12);
const _kBodyFontSize = 17.0;
const _kBodyLineHeight = 25.0 / 17.0;
const _kWordsPerPage = 170;

enum _SegmentKind { chapter, part, frontMatter }

// Heading types that group chapters (Part / Book / Volume / Section).
// Shown verbatim, never counted as a chapter.
final RegExp _partPrefixRe =
    RegExp(r'^(part|book|volume|section)\b', caseSensitive: false);

// Anything that smells like front/back matter. Substring match so e.g.
// "Author's Preface" or "Translator's Foreword" both hit.
final RegExp _frontMatterRe = RegExp(
  r'(preface|foreword|introduction|prologue|epilogue|afterword|interlude|'
  r'dedication|acknowledg|contents|cover|title\s+page|copyright|notes|'
  r'references|bibliography|glossary|index|appendix|about\s+the\s+(author|book)|'
  r'frontispiece|half\s*title|colophon|errata)',
  caseSensitive: false,
);

// Already-numbered titles (e.g. "Chapter 7") -- keep the wording, don't
// re-prefix.
final RegExp _chapterPrefixRe =
    RegExp(r'^chapter\b', caseSensitive: false);

_SegmentKind _classifySegmentTitle(String title) {
  if (_partPrefixRe.hasMatch(title)) return _SegmentKind.part;
  if (_frontMatterRe.hasMatch(title)) return _SegmentKind.frontMatter;
  return _SegmentKind.chapter;
}

class ReaderScreen extends StatefulWidget {
  final LibraryStore store;
  final StoredBook book;
  final bool animationsEnabled;
  final ValueChanged<String?>? onOpened;
  const ReaderScreen({
    super.key,
    required this.store,
    required this.book,
    this.animationsEnabled = true,
    this.onOpened,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late StoredBook _book;
  late int _segmentIndex;
  late CurlPageController _pageController;
  int _pageInChapter = 0;
  // Per-segment cache of paginated pages, keyed by segmentId.
  final Map<String, List<ReaderPage>> _pagesBySegment = {};
  // Flat index across all chapters. Each entry is (segmentIndex, pageInChapter).
  // Same model as iOS `flatGlobalIndex` so a horizontal swipe past the last
  // page of a chapter lands on the first page of the next, no chevron tap.
  final List<({int seg, int page})> _flatIndex = [];
  // Inverse map: cumulative page offset per segment so chapter jumps map
  // back to a global page index in O(1).
  final List<int> _segPageOffsets = [];

  final _player = PalimpsestAudioPlayer();
  late final AnnotationStore _annotations;
  AlignmentMap? _alignment;
  bool _aligning = false;
  // First-run alignment shows a fullscreen overlay (matches iOS
  // `alignmentFullscreen`). Dismissing it via "Continue in background"
  // leaves the inline `_AlignBanner` running.
  bool _showAlignFullscreen = false;
  AlignStage? _alignStage;
  Timer? _progressTimer;
  bool _chromeShown = true;

  // Tablet rail state — same model as iOS `iosSidebarVisible` / `sidebarTab`.
  bool _railExpanded = false;
  _SidebarTab _railTab = _SidebarTab.chapters;

  // Two-page spread (iPad-landscape parity, `.mid` spineLocation on iOS).
  // The PageView's controller swaps semantics between modes — single-page
  // granular vs spread-pair granular — so we recreate it on toggle.
  bool _spreadMode = false;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _annotations = AnnotationStore(storage: widget.store.storage, book: _book);
    _annotations.load();
    _segmentIndex = _book.currentSegmentIndex.clamp(
      0,
      _book.segments.isEmpty ? 0 : _book.segments.length - 1,
    );
    // Pre-paginate every chapter so a single PageView can span the whole
    // book — same flat-index model the iOS pageCurl uses. Books typically
    // pre-paginate in <100ms even for long novels.
    _rebuildFlatIndex();
    final saved = _book.currentPageInChapter
        .clamp(0, _pagesForCurrentChapter().length - 1);
    _pageInChapter = saved;
    _pageController =
        CurlPageController(initialPage: _globalIndex(_segmentIndex, saved));
    widget.onOpened?.call(_book.id);
    _player.initSession();
    if (_book.audioPath != null) {
      _player
          .loadFile(_book.audioPath!,
              bookId: _book.id, title: _book.title, author: _book.author)
          .then((_) {
        if (_book.currentAudioSeconds != null) {
          _player.seekSeconds(_book.currentAudioSeconds!);
        }
      });
    }
    if (_book.alignmentPath != null) {
      widget.store.loadAlignment(_book).then((map) {
        if (mounted) setState(() => _alignment = map);
      });
    }
    _progressTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _persistProgress());
  }

  Future<void> _persistProgress() async {
    if (!mounted) return;
    await widget.store.updateProgress(
      _book,
      segmentIndex: _segmentIndex,
      pageInChapter: _pageInChapter,
      audioSeconds: _player.position.inMilliseconds / 1000.0,
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _persistProgress();
    _pageController.dispose();
    _player.dispose();
    _annotations.dispose();
    super.dispose();
  }

  TextSegment get _segment => _book.segments[_segmentIndex];

  // Chapter-bar label. Part/Book/Volume/Section headings, front/back
  // matter, and titles already starting with "Chapter " all pass
  // through unchanged. Anything else gets a "Chapter N · " prefix where
  // N counts chapter-kind segments only (front matter and Parts don't
  // bump the counter).
  String _displayChapterLabel(int idx) {
    final seg = _book.segments[idx];
    final raw = seg.title?.trim();
    if (raw == null || raw.isEmpty) return 'Section ${idx + 1}';

    final kind = _classifySegmentTitle(raw);
    if (kind != _SegmentKind.chapter) return raw;

    if (_chapterPrefixRe.hasMatch(raw)) return raw;

    var n = 0;
    for (var i = 0; i <= idx; i++) {
      final t = _book.segments[i].title?.trim() ?? '';
      if (t.isEmpty) continue;
      if (_classifySegmentTitle(t) == _SegmentKind.chapter) n++;
    }
    return 'Chapter $n · $raw';
  }

  List<ReaderPage> _pagesForSegment(TextSegment seg) {
    final cached = _pagesBySegment[seg.id];
    if (cached != null) return cached;
    final paragraphs = seg.text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    final pages = const Paginator(wordsPerPage: _kWordsPerPage)
        .paginate(paragraphs);
    final out = pages.isEmpty
        ? const [ReaderPage(paragraphs: ['(empty section)'])]
        : pages;
    _pagesBySegment[seg.id] = out;
    return out;
  }

  List<ReaderPage> _pagesForCurrentChapter() => _pagesForSegment(_segment);

  /// Build the (segmentIndex, pageInChapter) flat list once per session.
  /// Cheap — pagination is just word counting per paragraph.
  void _rebuildFlatIndex() {
    _flatIndex.clear();
    _segPageOffsets.clear();
    var offset = 0;
    for (var i = 0; i < _book.segments.length; i++) {
      _segPageOffsets.add(offset);
      final pages = _pagesForSegment(_book.segments[i]);
      for (var p = 0; p < pages.length; p++) {
        _flatIndex.add((seg: i, page: p));
      }
      offset += pages.length;
    }
  }

  int _globalIndex(int seg, int page) => _segPageOffsets[seg] + page;

  void _goToSegment(int i, {bool toLastPage = false}) {
    final pages = _pagesForSegment(_book.segments[i]);
    final targetPage = toLastPage ? pages.length - 1 : 0;
    setState(() {
      _segmentIndex = i;
      _pageInChapter = targetPage;
    });
    if (_pageController.hasClients) {
      final globalIdx = _globalIndex(i, targetPage);
      _pageController.jumpToPage(_spreadMode ? globalIdx & ~1 : globalIdx);
    }
  }

  void _onPageChanged(int idx) {
    if (idx < 0 || idx >= _flatIndex.length) return;
    final m = _flatIndex[idx];
    setState(() {
      if (m.seg != _segmentIndex) _segmentIndex = m.seg;
      _pageInChapter = m.page;
    });
    // Persist immediately on every turn — the 2-second timer alone misses
    // saves when the user flips a page and backs out of the reader inside
    // that window. dispose's `_persistProgress` is async and races against
    // the widget tear-down, so the safest place to commit is here.
    _persistProgress();
  }

  /// Swap `_pageController` to match the new spread mode. Old controller
  /// dispose is deferred to the next frame so any active PageView still has
  /// a valid client during the build that triggered the swap.
  void _swapControllerForMode(bool spread) {
    final old = _pageController;
    final globalIdx = _globalIndex(_segmentIndex, _pageInChapter);
    _pageController = CurlPageController(
      initialPage: spread ? globalIdx & ~1 : globalIdx,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
    });
  }

  Future<void> _attachAudio() async {
    // Android: SAF greys out `.m4b` under `FileType.custom` (no registered
    // MIME), so we go `FileType.audio` to get the `audio/*` view that
    // surfaces every audiobook format.
    // Desktop (Linux/Windows): file_picker drives zenity/kdialog and its
    // `audio/*` MIME filter also drops `.m4b` on most installs, so we go
    // back to explicit extensions there.
    final result = Platform.isAndroid
        ? await FilePicker.platform.pickFiles(type: FileType.audio)
        : await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: const [
              'm4b', 'm4a', 'mp3', 'wav', 'aac',
              'flac', 'ogg', 'opus', 'mp4',
            ],
          );
    if (result == null || result.files.single.path == null) return;
    final updated =
        await widget.store.attachAudio(_book, File(result.files.single.path!));
    setState(() {
      _book = updated;
      // Drop the in-memory alignment too — `attachAudio` already deleted
      // the JSON and cleared the StoredBook's alignmentPath, but the
      // reader holds its own cached `_alignment` that gates "Play from
      // here" / "Re-align" labels. Without this, the reader keeps showing
      // "Re-align" against stale word anchors.
      _alignment = null;
    });
    await _player.loadFile(
      updated.audioPath!,
      bookId: _book.id,
      title: _book.title,
      author: _book.author,
    );
  }

  Future<void> _runAlign() async {
    setState(() {
      _aligning = true;
      // First-run shows the fullscreen overlay; re-aligns surface inline
      // since the user is already in the middle of reading.
      _showAlignFullscreen = _alignment == null;
      _alignStage = const AlignStage('Preparing…');
    });
    try {
      await for (final stage in widget.store.alignBook(_book)) {
        if (!mounted) return;
        setState(() => _alignStage = stage);
      }
      final fresh = widget.store.books.firstWhere((b) => b.id == _book.id);
      final map = await widget.store.loadAlignment(fresh);
      if (mounted) {
        setState(() {
          _book = fresh;
          _alignment = map;
        });
        // Visible completion feedback. Without this the fullscreen
        // dismisses and the reader returns to looking exactly as it did,
        // so the user can't tell whether anything actually happened.
        // We also distinguish 0-anchor outcomes (audio/text mismatch)
        // from real success, since "Play from here" silently does
        // nothing when there are no anchors for that segment.
        final wordCount = map?.words.length ?? 0;
        final messenger = ScaffoldMessenger.of(context);
        if (wordCount == 0) {
          messenger.showSnackBar(SnackBar(
            content: const Text(
                "Alignment finished but no anchors landed. The audiobook may not match this EPUB."),
            action: SnackBarAction(label: 'Retry', onPressed: _runAlign),
          ));
        } else {
          messenger.showSnackBar(SnackBar(
            content: Text(
                'Alignment complete · $wordCount paragraph anchors synced'),
          ));
        }
      }
    } catch (e, st) {
      debugPrint('alignment error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alignment failed: $e'),
            action: SnackBarAction(label: 'Retry', onPressed: _runAlign),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _aligning = false;
          _showAlignFullscreen = false;
        });
      }
    }
  }

  Future<void> _seekToParagraph(
      TextSegment segment, int paragraphIndex, String paragraphText) {
    if (_alignment == null) return Future.value();
    final approxOffset = segment.text.indexOf(paragraphText);
    final wordsBefore = approxOffset < 0
        ? 0
        : segment.text
            .substring(0, approxOffset)
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .length;
    final t = AlignmentService.seekTimeForParagraph(
      _alignment!,
      segments: _book.segments,
      segmentId: segment.id,
      wordIndex: wordsBefore,
    );
    if (t == null) return Future.value();
    return _player.seekSeconds(t).then((_) => _player.play());
  }

  void _showChapters() => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheet) => _ChapterDrawer(
          book: _book,
          annotations: _annotations,
          currentSegmentIndex: _segmentIndex,
          onPickChapter: (i) {
            Navigator.of(sheet).pop();
            _goToSegment(i);
          },
        ),
      );

  void _showOverflowMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.canvas,
      builder: (sheet) {
        final colors = sheet.colors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.bookmarks_outlined, color: colors.inkSoft),
                title: Text('All annotations',
                    style: TextStyle(color: colors.ink)),
                trailing: Text('${_annotations.items.length}',
                    style: TextStyle(color: colors.inkMuted)),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _showAnnotations();
                },
              ),
              ListTile(
                leading: Icon(Icons.headphones_outlined, color: colors.inkSoft),
                title: Text(
                  _book.audioPath == null
                      ? 'Attach audiobook'
                      : 'Audio controls',
                  style: TextStyle(color: colors.ink),
                ),
                onTap: () {
                  Navigator.of(sheet).pop();
                  if (_book.audioPath == null) {
                    _attachAudio();
                  } else {
                    _showAudioSheet();
                  }
                },
              ),
              if (_book.audioPath != null)
                ListTile(
                  leading: Icon(
                    _alignment == null
                        ? Icons.auto_awesome
                        : Icons.refresh,
                    color: colors.accent,
                  ),
                  title: Text(
                    _alignment == null
                        ? 'Align audio with text'
                        : 'Re-align audio with text',
                    style: TextStyle(color: colors.accent),
                  ),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    _runAlign();
                  },
                ),
              if (_book.audioPath != null)
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: colors.inkSoft),
                  title: Text('Replace audiobook…',
                      style: TextStyle(color: colors.ink)),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    _attachAudio();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAudioSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheet) => AudioSheet(
        player: _player,
        book: _book,
        hasAlignment: _alignment != null,
        isAligning: _aligning,
        onAlign: () {
          Navigator.of(sheet).pop();
          _runAlign();
        },
      ),
    );
  }

  void _showAnnotations() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheet) => _AnnotationsSheet(
        annotations: _annotations,
        book: _book,
        onJumpTo: (a) {
          Navigator.of(sheet).pop();
          final i = _book.segments.indexWhere((s) => s.id == a.segmentId);
          if (i >= 0) _goToSegment(i);
        },
      ),
    );
  }

  // Map (chapter pageIdx, paragraph idx within page) -> absolute
  // paragraph index in the segment, accounting for continuation flags
  // so annotations survive re-pagination at different page sizes.
  int _absoluteParagraphIndex(
      TextSegment segment, int pageIdxInChapter, int pIndexInPage) {
    final pages = _pagesForSegment(segment);
    var idx = 0;
    for (var i = 0; i < pageIdxInChapter; i++) {
      idx += pages[i].paragraphs.length;
      if (pages[i].endsContinuation) idx -= 1;
    }
    idx += pIndexInPage;
    if (pages[pageIdxInChapter].startsContinuation) idx -= 1;
    return idx;
  }

  Future<void> _onParagraphLongPress(int segIdx, int pageIdxInChapter,
      int pIndexInPage, String text, Offset globalPos) async {
    final segment = _book.segments[segIdx];
    final segId = segment.id;
    final absoluteIdx =
        _absoluteParagraphIndex(segment, pageIdxInChapter, pIndexInPage);

    final action = await _showSelectionMenu(
      context: context,
      anchor: globalPos,
      hasAlignment: _alignment != null,
      existing: _annotations.forParagraph(segId, absoluteIdx),
    );
    if (action == null || !mounted) return;

    final colors = context.colors;
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    switch (action.type) {
      case _ParaActionType.highlight:
        await _annotations.add(Annotation(
          id: id,
          segmentId: segId,
          paragraphIndex: absoluteIdx,
          kind: AnnotationKind.highlight,
          color: action.color!,
          quote: text,
          createdAt: DateTime.now().toUtc(),
        ));
      case _ParaActionType.bookmark:
        await _annotations.add(Annotation(
          id: id,
          segmentId: segId,
          paragraphIndex: absoluteIdx,
          kind: AnnotationKind.bookmark,
          quote: text,
          createdAt: DateTime.now().toUtc(),
        ));
      case _ParaActionType.note:
        if (!mounted) return;
        final note = await _promptForNote(initial: null);
        if (note != null && note.isNotEmpty) {
          await _annotations.add(Annotation(
            id: id,
            segmentId: segId,
            paragraphIndex: absoluteIdx,
            kind: AnnotationKind.note,
            color: HighlightColor.amber,
            quote: text,
            note: note,
            createdAt: DateTime.now().toUtc(),
          ));
        }
      case _ParaActionType.play:
        await _seekToParagraph(segment, absoluteIdx, text);
      case _ParaActionType.playNeedsAlign:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Run audio alignment first to play from a specific paragraph.'),
            action: _book.audioPath == null
                ? null
                : SnackBarAction(
                    label: 'Align now',
                    onPressed: _runAlign,
                  ),
          ),
        );
      case _ParaActionType.remove:
        if (action.annotationId != null) {
          await _annotations.remove(action.annotationId!);
        }
    }
    setState(() {}); // rerender to apply highlight color
    // Suppress unused colors warning
    colors.canvas;
  }

  // Called from the in-text selection toolbar (Highlight / Note).
  // start / end are char offsets inside paragraphText. We translate
  // the per-page paragraph index to the absolute one using the same
  // continuation-aware walk as _onParagraphLongPress.
  Future<void> _onSelectionAction(
    int segIdx,
    int pageIdxInChapter,
    int pIndexInPage,
    String paragraphText,
    int start,
    int end,
    _ParaActionType type,
  ) async {
    if (start >= end) return;
    final segment = _book.segments[segIdx];
    final segId = segment.id;
    final absoluteIdx =
        _absoluteParagraphIndex(segment, pageIdxInChapter, pIndexInPage);
    final quote = paragraphText.substring(start, end);
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

    switch (type) {
      case _ParaActionType.highlight:
        await _annotations.add(Annotation(
          id: id,
          segmentId: segId,
          paragraphIndex: absoluteIdx,
          kind: AnnotationKind.highlight,
          color: HighlightColor.amber,
          quote: quote,
          quoteStart: start,
          quoteEnd: end,
          createdAt: DateTime.now().toUtc(),
        ));
      case _ParaActionType.note:
        if (!mounted) return;
        final note = await _promptForNote(initial: null);
        if (note != null && note.isNotEmpty) {
          await _annotations.add(Annotation(
            id: id,
            segmentId: segId,
            paragraphIndex: absoluteIdx,
            kind: AnnotationKind.note,
            color: HighlightColor.amber,
            quote: quote,
            quoteStart: start,
            quoteEnd: end,
            note: note,
            createdAt: DateTime.now().toUtc(),
          ));
        }
      case _ParaActionType.bookmark:
      case _ParaActionType.play:
      case _ParaActionType.playNeedsAlign:
      case _ParaActionType.remove:
        // Selection toolbar only offers highlight + note; the rest live
        // on the ... button for the whole paragraph.
        break;
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<String?> _promptForNote({String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (dialog) {
        final colors = dialog.colors;
        return AlertDialog(
          backgroundColor: colors.canvas,
          title: Text('Note', style: TextStyle(color: colors.ink)),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            style: TextStyle(color: colors.ink),
            decoration: InputDecoration(
              hintText: 'Type your note…',
              hintStyle: TextStyle(color: colors.inkMuted),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: Text('Cancel',
                  style: TextStyle(color: colors.inkSoft)),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialog).pop(controller.text.trim()),
              child: Text('Save',
                  style: TextStyle(color: colors.accent)),
            ),
          ],
        );
      },
    );
  }

  void _flipBy(int direction) {
    if (!_pageController.hasClients || _flatIndex.isEmpty) return;
    final step = (_spreadMode ? 2 : 1) * direction;
    final target = _pageController.page + step;
    if (target < 0 || target >= _flatIndex.length) return;
    _pageController.animateToPage(target);
  }

  KeyEventResult _handleReaderKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.pageDown ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _flipBy(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.pageUp) {
      _flipBy(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.shortestSide >= 600;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleReaderKey,
      child: Scaffold(
        backgroundColor: colors.canvasCool,
        body: ListenableBuilder(
          listenable: _annotations,
          builder: (_, _) => Stack(
            children: [
              SafeArea(
                child: isTablet
                    ? _buildTabletLayout(colors, size)
                    : _buildPhoneLayout(colors),
              ),
              if (_showAlignFullscreen && _alignStage != null)
                Positioned.fill(
                  child: _AlignmentFullscreen(
                    book: _book,
                    stage: _alignStage!,
                    colors: colors,
                    onContinueInBackground: () =>
                        setState(() => _showAlignFullscreen = false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneLayout(PalimpsestColors colors) {
    return Column(
      children: [
        if (_chromeShown)
          _IOSHeader(
            title: _displayChapterLabel(_segmentIndex),
            onBack: () => Navigator.of(context).pop(),
            onChapters: _showChapters,
            onOverflow: _showOverflowMenu,
            colors: colors,
          ),
        if (_aligning && _alignStage != null)
          _AlignBanner(stage: _alignStage!, colors: colors),
        Expanded(child: _readerPageView(spread: false)),
        if (_chromeShown)
          _book.audioPath == null
              ? _AttachAudiobookBar(onTap: _attachAudio, colors: colors)
              : _CompactAudioBar(
                  player: _player,
                  hasAlignment: _alignment != null,
                  onTap: _showAudioSheet,
                  colors: colors,
                ),
      ],
    );
  }

  /// iPad-equivalent. Collapsed icon rail on the left expands to a sidebar
  /// with the same Chapters / Bookmarks / Notes tabs the macOS sidebar
  /// uses. Two-page spread when the tablet is in landscape (matches iOS
  /// `.mid` spineLocation), single page in portrait. Full audio bar at the
  /// bottom (rate / sleep / re-align pills).
  Widget _buildTabletLayout(PalimpsestColors colors, Size size) {
    final wantsSpread = size.width > size.height;
    if (wantsSpread != _spreadMode) {
      _spreadMode = wantsSpread;
      _swapControllerForMode(wantsSpread);
    }
    return Row(
      children: [
        if (_railExpanded)
          _ExpandedSidebar(
            book: _book,
            annotations: _annotations,
            currentSegmentIndex: _segmentIndex,
            tab: _railTab,
            onTab: (t) => setState(() => _railTab = t),
            onPickChapter: (i) => _goToSegment(i),
            onJumpToAnnotation: (a) {
              final i = _book.segments.indexWhere((s) => s.id == a.segmentId);
              if (i >= 0) _goToSegment(i);
            },
            onCollapse: () => setState(() => _railExpanded = false),
            colors: colors,
          )
        else
          _CollapsedRail(
            currentTab: _railTab,
            onTab: (t) {
              setState(() {
                _railTab = t;
                _railExpanded = true;
              });
            },
            onToggleExpand: () => setState(() => _railExpanded = true),
            onSettings: _openSettingsSheet,
            onBackToLibrary: () => Navigator.of(context).pop(),
            colors: colors,
          ),
        Container(width: 1, color: colors.hairline),
        Expanded(
          child: Column(
            children: [
              _TabletTopBar(
                title: _displayChapterLabel(_segmentIndex),
                onOverflow: _showOverflowMenu,
                colors: colors,
              ),
              if (_aligning && _alignStage != null)
                _AlignBanner(stage: _alignStage!, colors: colors),
              Expanded(
                child: _readerPageView(spread: wantsSpread),
              ),
              _TabletAudioFooter(
                player: _player,
                book: _book,
                hasAlignment: _alignment != null,
                isAligning: _aligning,
                onAttach: _attachAudio,
                onAlign: _runAlign,
                onReplaceAudio: _attachAudio,
                colors: colors,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.canvas,
      isScrollControlled: true,
      builder: (sheet) {
        final colors = sheet.colors;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: Icon(Icons.bookmarks_outlined, color: colors.inkSoft),
                title: Text('All annotations',
                    style: TextStyle(color: colors.ink)),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _showAnnotations();
                },
              ),
              if (_book.audioPath != null)
                ListTile(
                  leading: Icon(
                    _alignment == null ? Icons.auto_awesome : Icons.refresh,
                    color: colors.accent,
                  ),
                  title: Text(
                    _alignment == null
                        ? 'Align audio with text'
                        : 'Re-align audio with text',
                    style: TextStyle(color: colors.accent),
                  ),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    _runAlign();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// Page surface used by both phone and tablet. `spread` controls
  /// two-up vs one-up layout. The controller's `page` is the global
  /// page index in both modes — in spread mode it just rounds down to
  /// the nearest even number to anchor the displayed pair.
  Widget _readerPageView({required bool spread}) {
    final colors = context.colors;
    return CurlPageView(
      key: ValueKey(spread ? 'reader-spread' : 'reader-single'),
      controller: _pageController,
      pageCount: _flatIndex.length,
      spread: spread,
      animationsEnabled: widget.animationsEnabled,
      pageInsets: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      onPageChanged: _onPageChanged,
      onMiddleTap: () => setState(() => _chromeShown = !_chromeShown),
      pageBuilder: (leafCtx, idx) {
        if (idx < 0 || idx >= _flatIndex.length) {
          return Container(color: colors.canvas);
        }
        return _buildFlatPage(leafCtx, idx);
      },
    );
  }

  Widget _buildFlatPage(BuildContext leafCtx, int idx) {
    final m = _flatIndex[idx];
    final seg = _book.segments[m.seg];
    final page = _pagesForSegment(seg)[m.page];
    final colors = context.colors;
    // Page card chrome — same cue as iOS: rounded corners + hairline +
    // drop shadow on a cooler canvas so the page reads as a real leaf
    // rather than pasted onto the device. Outer padding is supplied by
    // CurlPageView via `pageInsets` so the curl shader's container rect
    // matches the visible card. In spread mode we drop the rounding on
    // the spine-side corners so the two pages meet flush, like the
    // facing pages of a real book.
    final side = LeafSideScope.of(leafCtx);
    const outerRadius = Radius.circular(6);
    final borderRadius = switch (side) {
      LeafSide.single => const BorderRadius.all(outerRadius),
      LeafSide.left => const BorderRadius.only(
          topLeft: outerRadius, bottomLeft: outerRadius),
      LeafSide.right => const BorderRadius.only(
          topRight: outerRadius, bottomRight: outerRadius),
    };
    return Container(
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: borderRadius,
        border: Border.all(color: colors.hairlineStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _PageView(
        page: page,
        pageIdx: m.page,
        chapterLabel: _displayChapterLabel(m.seg),
        annotations: _annotations,
        segmentId: seg.id,
        onParagraphLongPress: (pIdx, text, globalPos) =>
            _onParagraphLongPress(m.seg, m.page, pIdx, text, globalPos),
        onSelectionAction: (pIdx, text, start, end, type) =>
            _onSelectionAction(m.seg, m.page, pIdx, text, start, end, type),
      ),
    );
  }
}

class _IOSHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onChapters;
  final VoidCallback onOverflow;
  final PalimpsestColors colors;
  const _IOSHeader({
    required this.title,
    required this.onBack,
    required this.onChapters,
    required this.onOverflow,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _CircleHeaderBtn(
              icon: const Icon(CupertinoIcons.chevron_back, size: 18),
              colors: colors,
              onTap: onBack,
            ),
            const SizedBox(width: 4),
            _CircleHeaderBtn(
              icon: const Icon(Icons.menu, size: 16),
              colors: colors,
              onTap: onChapters,
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _CircleHeaderBtn(
              icon: const Icon(Icons.more_horiz, size: 18),
              colors: colors,
              onTap: onOverflow,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _CircleHeaderBtn extends StatelessWidget {
  final Widget icon;
  final PalimpsestColors colors;
  final VoidCallback onTap;
  const _CircleHeaderBtn({
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: IconTheme.merge(
              data: IconThemeData(color: colors.inkSoft), child: icon),
        ),
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  final ReaderPage page;
  final int pageIdx;
  final String chapterLabel;
  final AnnotationStore annotations;
  final String segmentId;
  final void Function(int pIndexInPage, String text, Offset globalPos)
      onParagraphLongPress;
  final void Function(int pIndexInPage, String text, int start, int end,
      _ParaActionType type)? onSelectionAction;

  const _PageView({
    required this.page,
    required this.pageIdx,
    required this.chapterLabel,
    required this.annotations,
    required this.segmentId,
    required this.onParagraphLongPress,
    this.onSelectionAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: annotations,
      builder: (_, _) => Padding(
        padding: _kPagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chapter kicker — uppercase muted, 1.5 letter-spacing, matches
            // iOS `chapterHeader`. Only on the first page of a chapter.
            if (pageIdx == 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(
                  chapterLabel.toUpperCase(),
                  style: TextStyle(
                    color: colors.inkMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            Expanded(
              // Pagination is by word count (170/page) and doesn't measure
              // rendered height, so a small / unmaximized window can let
              // a page overflow vertically. ClampingScrollPhysics lets the
              // user scroll only the overflowing tail; pages that fit
              // stay non-scrollable.
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < page.paragraphs.length; i++)
                      _ParagraphRow(
                        text: page.paragraphs[i],
                        isContinuationStart:
                            i == 0 && page.startsContinuation,
                        isContinuationEnd:
                            i == page.paragraphs.length - 1 &&
                                page.endsContinuation,
                        marks: _marksForParagraphInPage(i),
                        colors: colors,
                        onMenu: (globalPos) => onParagraphLongPress(
                            i, page.paragraphs[i], globalPos),
                        onSelectionAction: (type, start, end, quote) =>
                            onSelectionAction?.call(
                                i, page.paragraphs[i], start, end, type),
                      ),
                  ],
                ),
              ),
            ),
            // In-card page number footer, mono, centered. Matches iOS
            // `pageSurface` trailing `Text("\(pageIndex + 1)")`.
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Center(
                child: Text(
                  '${pageIdx + 1}',
                  style: TextStyle(
                    color: colors.inkMuted,
                    fontSize: 10,
                    fontFamilyFallback: const [
                      'JetBrains Mono',
                      'Cascadia Code',
                      'Roboto Mono',
                      'monospace',
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Annotation> _marksForParagraphInPage(int idx) {
    // We do NOT have the absolute paragraph index here — we only show
    // pertinent visual hints. The on-tap callback computes the absolute
    // index by re-walking pages on the parent state.
    return annotations
        .forSegment(segmentId)
        .where((a) =>
            page.paragraphs.length > idx &&
            (a.quote.startsWith(page.paragraphs[idx].substring(
                    0,
                    page.paragraphs[idx].length > 40
                        ? 40
                        : page.paragraphs[idx].length)) ||
                page.paragraphs[idx].startsWith(a.quote.substring(
                    0, a.quote.length > 40 ? 40 : a.quote.length))))
        .toList();
  }
}

class _ParagraphRow extends StatelessWidget {
  final String text;
  final bool isContinuationStart;
  final bool isContinuationEnd;
  final List<Annotation> marks;
  final PalimpsestColors colors;
  final ValueChanged<Offset> onMenu;
  final void Function(_ParaActionType type, int start, int end, String quote)?
      onSelectionAction;

  const _ParagraphRow({
    required this.text,
    required this.isContinuationStart,
    required this.isContinuationEnd,
    required this.marks,
    required this.colors,
    required this.onMenu,
    this.onSelectionAction,
  });

  @override
  Widget build(BuildContext context) {
    final wholeHighlight = marks
        .where((a) => a.kind == AnnotationKind.highlight && !a.isRange)
        .firstOrNull;
    final rangeHighlights = marks
        .where((a) => a.kind == AnnotationKind.highlight && a.isRange)
        .toList();
    final hasBookmark =
        marks.any((a) => a.kind == AnnotationKind.bookmark);
    final note = marks
        .where((a) => a.kind == AnnotationKind.note && a.note?.isNotEmpty == true)
        .firstOrNull;

    final baseStyle = TextStyle(
      color: colors.ink,
      fontSize: _kBodyFontSize,
      height: _kBodyLineHeight,
    );

    Widget paragraphText = SelectableText.rich(
      TextSpan(children: _composeSpans(text, rangeHighlights, baseStyle)),
      style: baseStyle,
      contextMenuBuilder: (ctx, state) =>
          _buildSelectionMenu(ctx, state, text),
    );

    if (wholeHighlight != null) {
      paragraphText = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: wholeHighlight.color.fill,
          borderRadius: BorderRadius.circular(2),
        ),
        child: paragraphText,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasBookmark)
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 6),
              child: Icon(Icons.bookmark, size: 12, color: colors.accent),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                paragraphText,
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                      decoration: BoxDecoration(
                        color: colors.canvasCool,
                        borderRadius: BorderRadius.circular(4),
                        border: Border(
                            left: BorderSide(
                                color: colors.accent, width: 2)),
                      ),
                      child: Text(
                        note.note!,
                        style: TextStyle(
                          color: colors.inkSoft,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ... button -- the only path to whole-paragraph actions
          // (bookmark, "play from here") now that SelectableText owns
          // long-press inside the body of the paragraph.
          SizedBox(
            width: 28,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => onMenu(d.globalPosition),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: colors.inkMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionMenu(
      BuildContext ctx, EditableTextState state, String text) {
    final selection = state.textEditingValue.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: state.contextMenuAnchors,
        buttonItems: state.contextMenuButtonItems,
      );
    }
    final start = math.max(0, math.min(selection.start, text.length));
    final end = math.max(0, math.min(selection.end, text.length));
    final quote = text.substring(start, end);
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        ContextMenuButtonItem(
          label: 'Highlight',
          onPressed: () {
            state.hideToolbar();
            onSelectionAction?.call(
                _ParaActionType.highlight, start, end, quote);
          },
        ),
        ContextMenuButtonItem(
          label: 'Note',
          onPressed: () {
            state.hideToolbar();
            onSelectionAction?.call(
                _ParaActionType.note, start, end, quote);
          },
        ),
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: quote));
            state.hideToolbar();
          },
        ),
      ],
    );
  }
}

// Splits text into TextSpans, painting a background colour wherever a
// range highlight applies. Overlaps go to whoever sorted first; out-of-
// bounds offsets are clamped.
List<TextSpan> _composeSpans(
  String text,
  List<Annotation> rangeHighlights,
  TextStyle baseStyle,
) {
  if (rangeHighlights.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }
  final ranges = rangeHighlights
      .map((a) {
        final s = math.max(0, math.min(a.quoteStart!, text.length));
        final e = math.max(0, math.min(a.quoteEnd!, text.length));
        return (start: s, end: e, color: a.color.fill);
      })
      .where((r) => r.start < r.end)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  final spans = <TextSpan>[];
  var cursor = 0;
  for (final r in ranges) {
    if (r.end <= cursor) continue;
    final start = math.max(r.start, cursor);
    if (start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, start), style: baseStyle));
    }
    spans.add(TextSpan(
      text: text.substring(start, r.end),
      style: baseStyle.copyWith(backgroundColor: r.color),
    ));
    cursor = r.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return spans;
}

/// Slim attach-audiobook strip shown at the bottom of the reader when no
/// audio is attached. Mirrors `attachAudiobookBar` in
/// `App/ReaderView.swift`: speaker icon + "No audiobook attached" + saddle
/// `+ Attach…` pill.
class _AttachAudiobookBar extends StatelessWidget {
  final VoidCallback onTap;
  final PalimpsestColors colors;
  const _AttachAudiobookBar({required this.onTap, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.canvasDeep,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        children: [
          Icon(Icons.volume_up_outlined, size: 18, color: colors.inkMuted),
          const SizedBox(width: 12),
          Text(
            'No audiobook attached',
            style: TextStyle(color: colors.inkMuted, fontSize: 14),
          ),
          const Spacer(),
          Material(
            color: colors.accent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: colors.onAccent),
                    const SizedBox(width: 4),
                    Text(
                      'Attach…',
                      style: TextStyle(
                        color: colors.onAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactAudioBar extends StatelessWidget {
  final PalimpsestAudioPlayer player;
  final bool hasAlignment;
  final VoidCallback onTap;
  final PalimpsestColors colors;
  const _CompactAudioBar({
    required this.player,
    required this.hasAlignment,
    required this.onTap,
    required this.colors,
  });

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) onTap();
      },
      child: ListenableBuilder(
        listenable: player,
        builder: (_, _) => Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: colors.canvasCool,
            border:
                Border(top: BorderSide(color: colors.hairline)),
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.hairlineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _MiniPlayBtn(player: player, colors: colors),
                  const SizedBox(width: 10),
                  Text(_fmt(player.position),
                      style: _mono(colors.inkMuted)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: colors.accent,
                        inactiveTrackColor: colors.hairlineStrong,
                        thumbColor: colors.accent,
                        overlayColor:
                            colors.accent.withValues(alpha: 0.18),
                        trackHeight: 2,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 5),
                      ),
                      child: Slider(
                        min: 0,
                        max: (player.duration?.inMilliseconds ?? 1).toDouble(),
                        value: player.position.inMilliseconds
                            .clamp(0,
                                (player.duration?.inMilliseconds ?? 1))
                            .toDouble(),
                        onChanged: (v) => player.seekSeconds(v / 1000.0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_fmt(player.duration ?? Duration.zero),
                      style: _mono(colors.inkMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static TextStyle _mono(Color c) => TextStyle(
        color: c,
        fontSize: 10,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontFamilyFallback: const [
          'JetBrains Mono',
          'Cascadia Code',
          'Roboto Mono',
          'monospace',
        ],
      );
}

class _MiniPlayBtn extends StatelessWidget {
  final PalimpsestAudioPlayer player;
  final PalimpsestColors colors;
  const _MiniPlayBtn({required this.player, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.accent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: player.isReady ? player.togglePlay : null,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            player.isPlaying ? Icons.pause : Icons.play_arrow,
            color: colors.onAccent,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _AlignBanner extends StatefulWidget {
  final AlignStage stage;
  final PalimpsestColors colors;
  const _AlignBanner({required this.stage, required this.colors});

  @override
  State<_AlignBanner> createState() => _AlignBannerState();
}

class _AlignBannerState extends State<_AlignBanner> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _resetForLabel(widget.stage.label);
  }

  @override
  void didUpdateWidget(covariant _AlignBanner old) {
    super.didUpdateWidget(old);
    if (widget.stage.label != old.stage.label) {
      _resetForLabel(widget.stage.label);
    }
  }

  /// Restart the elapsed counter at every phase boundary — transcribe is
  /// the long one, and the user only cares about elapsed time inside
  /// whichever phase is currently running. Re-aligns from chapter changes
  /// also start fresh.
  void _resetForLabel(String label) {
    _ticker?.cancel();
    _ticker = null;
    _elapsed = Duration.zero;
    if (_isLongRunning(label)) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
      });
    }
  }

  bool _isLongRunning(String label) {
    final s = label.toLowerCase();
    return s.contains('transcrib') || s.contains('align');
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final showElapsed = _ticker != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.canvasCool,
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: widget.stage.fraction,
              valueColor: AlwaysStoppedAnimation(c.accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(widget.stage.label,
                style: TextStyle(color: c.inkSoft, fontSize: 13)),
          ),
          if (showElapsed)
            Text(_formatElapsed(_elapsed),
                style: TextStyle(
                  color: c.inkMuted,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
        ],
      ),
    );
  }
}

String _formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class _ChapterDrawer extends StatelessWidget {
  final StoredBook book;
  final AnnotationStore annotations;
  final int currentSegmentIndex;
  final ValueChanged<int> onPickChapter;

  const _ChapterDrawer({
    required this.book,
    required this.annotations,
    required this.currentSegmentIndex,
    required this.onPickChapter,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: colors.canvas,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.hairlineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Row(
                children: [
                  Text('CHAPTERS',
                      style: TextStyle(
                          color: colors.inkMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5)),
                  const Spacer(),
                  Text('${book.segments.length}',
                      style: TextStyle(
                          color: colors.inkMuted,
                          fontSize: 11,
                          fontFamilyFallback: const [
                            'JetBrains Mono',
                            'Cascadia Code',
                            'Roboto Mono',
                            'monospace',
                          ])),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                itemCount: book.segments.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: colors.hairline),
                itemBuilder: (_, i) {
                  final s = book.segments[i];
                  final selected = i == currentSegmentIndex;
                  final title =
                      s.title?.trim().isNotEmpty == true ? s.title!.trim() : 'Section ${i + 1}';
                  return Material(
                    color: selected ? colors.canvasCool : Colors.transparent,
                    child: InkWell(
                      onTap: () => onPickChapter(i),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                        child: Row(
                          children: [
                            if (selected)
                              Container(
                                width: 3,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: colors.accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              )
                            else
                              const SizedBox(width: 3),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  color:
                                      selected ? colors.accent : colors.ink,
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: colors.inkMuted,
                                fontSize: 11,
                                fontFamilyFallback: const [
                                  'JetBrains Mono',
                                  'Cascadia Code',
                                  'Roboto Mono',
                                  'monospace',
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ParaActionType { highlight, bookmark, note, play, playNeedsAlign, remove }

class _ParaAction {
  final _ParaActionType type;
  final HighlightColor? color;
  /// Set for `remove` actions — the specific annotation to drop. Null for
  /// every other action type.
  final String? annotationId;
  const _ParaAction.highlight(HighlightColor c)
      : type = _ParaActionType.highlight,
        color = c,
        annotationId = null;
  const _ParaAction.bookmark()
      : type = _ParaActionType.bookmark,
        color = null,
        annotationId = null;
  const _ParaAction.note()
      : type = _ParaActionType.note,
        color = null,
        annotationId = null;
  const _ParaAction.play()
      : type = _ParaActionType.play,
        color = null,
        annotationId = null;
  const _ParaAction.playNeedsAlign()
      : type = _ParaActionType.playNeedsAlign,
        color = null,
        annotationId = null;
  const _ParaAction.removeOne(String id)
      : type = _ParaActionType.remove,
        color = null,
        annotationId = id;
}

/// iOS-style selection menu with the saddle "Highlight" primary plus secondary
/// actions in a single rounded pill. Anchored near the touch point.
Future<_ParaAction?> _showSelectionMenu({
  required BuildContext context,
  required Offset anchor,
  required bool hasAlignment,
  required List<Annotation> existing,
}) {
  final colors = context.colors;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final size = overlay.size;
  final menuWidth = (size.width - 32).clamp(220.0, 360.0);
  final left = (anchor.dx - menuWidth / 2)
      .clamp(16.0, size.width - menuWidth - 16.0);
  final tipDx = (anchor.dx - left).clamp(20.0, menuWidth - 20.0);
  final showAbove = anchor.dy > size.height / 2;
  // Approximate height grows with the number of removable rows we render.
  // Without this the menu clips off-screen when a paragraph has several
  // annotations stacked.
  final approxHeight = 178.0 + existing.length * 44.0;
  final menuTop = showAbove ? anchor.dy - approxHeight : anchor.dy + 12;

  return showGeneralDialog<_ParaAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Selection menu',
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (_, _, _) => Stack(
      children: [
        Positioned(
          left: left,
          top: menuTop,
          width: menuWidth,
          child: _SelectionMenu(
            hasAlignment: hasAlignment,
            existing: existing,
            tipDx: tipDx,
            tipUp: !showAbove,
            colors: colors,
          ),
        ),
      ],
    ),
  );
}

class _SelectionMenu extends StatelessWidget {
  final bool hasAlignment;
  final List<Annotation> existing;
  final double tipDx;
  final bool tipUp;
  final PalimpsestColors colors;

  const _SelectionMenu({
    required this.hasAlignment,
    required this.existing,
    required this.tipDx,
    required this.tipUp,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final menu = Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: colors.canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final c in HighlightColor.values)
                  GestureDetector(
                    onTap: () => Navigator.of(context)
                        .pop(_ParaAction.highlight(c)),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c.swatch,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.hairline),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: colors.hairline),
            _MenuRow(
              icon: Icons.bookmark_outline,
              label: 'Bookmark',
              onTap: () =>
                  Navigator.of(context).pop(const _ParaAction.bookmark()),
              colors: colors,
            ),
            _MenuRow(
              icon: Icons.sticky_note_2_outlined,
              label: 'Add note',
              onTap: () =>
                  Navigator.of(context).pop(const _ParaAction.note()),
              colors: colors,
            ),
            // Always-visible discovery hook. When alignment hasn't run
            // yet, the row stays in the menu but tapping it pops a
            // `playNeedsAlign` action so the reader can surface an
            // "align audio first" snackbar instead of silently doing
            // nothing. Same rationale as iOS `ParagraphRow` keeping the
            // disabled Button visible.
            _MenuRow(
              icon: Icons.play_arrow_outlined,
              label: hasAlignment
                  ? 'Play audiobook from here'
                  : 'Play from here · align audio first',
              accent: hasAlignment,
              disabled: !hasAlignment,
              onTap: () => Navigator.of(context).pop(
                hasAlignment
                    ? const _ParaAction.play()
                    : const _ParaAction.playNeedsAlign(),
              ),
              colors: colors,
            ),
            for (final a in existing)
              _MenuRow(
                icon: _removalIcon(a.kind),
                label: _removalLabel(a),
                destructive: true,
                onTap: () => Navigator.of(context)
                    .pop(_ParaAction.removeOne(a.id)),
                colors: colors,
              ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tipUp)
          CustomPaint(
            size: Size(tipDx + 12, 8),
            painter: _TipPainter(colors: colors, dx: tipDx, up: true),
          ),
        menu,
        if (!tipUp)
          CustomPaint(
            size: Size(tipDx + 12, 8),
            painter: _TipPainter(colors: colors, dx: tipDx, up: false),
          ),
      ],
    );
  }
}

IconData _removalIcon(AnnotationKind kind) {
  switch (kind) {
    case AnnotationKind.highlight:
      return Icons.format_color_reset_outlined;
    case AnnotationKind.bookmark:
      return Icons.bookmark_remove_outlined;
    case AnnotationKind.note:
      return Icons.speaker_notes_off_outlined;
  }
}

String _removalLabel(Annotation a) {
  switch (a.kind) {
    case AnnotationKind.highlight:
      return 'Remove highlight';
    case AnnotationKind.bookmark:
      return 'Remove bookmark';
    case AnnotationKind.note:
      final preview = (a.note ?? '').trim();
      if (preview.isEmpty) return 'Remove note';
      final short = preview.length > 28
          ? '${preview.substring(0, 28)}…'
          : preview;
      return 'Remove note: $short';
  }
}

class _TipPainter extends CustomPainter {
  final PalimpsestColors colors;
  final double dx;
  final bool up;
  _TipPainter({required this.colors, required this.dx, required this.up});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = colors.canvas;
    final stroke = Paint()
      ..color = colors.hairline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path();
    if (up) {
      path.moveTo(dx - 6, size.height);
      path.lineTo(dx, 0);
      path.lineTo(dx + 6, size.height);
    } else {
      path.moveTo(dx - 6, 0);
      path.lineTo(dx, size.height);
      path.lineTo(dx + 6, 0);
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _TipPainter old) =>
      old.dx != dx || old.up != up;
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final bool destructive;
  final bool disabled;
  final VoidCallback onTap;
  final PalimpsestColors colors;
  const _MenuRow({
    required this.icon,
    required this.label,
    this.accent = false,
    this.destructive = false,
    this.disabled = false,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final color = disabled
        ? colors.inkMuted
        : destructive
            ? Colors.redAccent
            : accent
                ? colors.accent
                : colors.ink;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: accent
                              ? FontWeight.w600
                              : FontWeight.w400))),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnotationsSheet extends StatelessWidget {
  final AnnotationStore annotations;
  final StoredBook book;
  final ValueChanged<Annotation> onJumpTo;
  const _AnnotationsSheet({
    required this.annotations,
    required this.book,
    required this.onJumpTo,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.30,
      maxChildSize: 0.90,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: colors.canvas,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ListenableBuilder(
          listenable: annotations,
          builder: (_, _) {
            final items = [...annotations.items]
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.hairlineStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                  child: Row(
                    children: [
                      Text('ANNOTATIONS',
                          style: TextStyle(
                              color: colors.inkMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5)),
                      const Spacer(),
                      Text('${items.length}',
                          style: TextStyle(
                              color: colors.inkMuted, fontSize: 11)),
                    ],
                  ),
                ),
                if (items.isEmpty)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 36),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmarks_outlined,
                                size: 44, color: colors.inkMuted),
                            const SizedBox(height: 12),
                            Text('No annotations yet.',
                                style: TextStyle(
                                    color: colors.ink, fontSize: 16)),
                            const SizedBox(height: 6),
                            Text(
                              'Long-press a paragraph to highlight, bookmark, or note it.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: colors.inkMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      controller: scroll,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => Divider(
                          height: 1, color: colors.hairline),
                      itemBuilder: (_, i) {
                        final a = items[i];
                        final segTitle = book.segments
                                .firstWhere((s) => s.id == a.segmentId,
                                    orElse: () => book.segments.first)
                                .title ??
                            'Section';
                        return ListTile(
                          leading: _IconForKind(a: a, colors: colors),
                          title: Text(
                            a.quote,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.ink),
                          ),
                          subtitle: Text(
                            a.note?.isNotEmpty == true
                                ? '$segTitle  ·  ${a.note}'
                                : segTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.inkMuted),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: colors.inkMuted),
                            onPressed: () => annotations.remove(a.id),
                          ),
                          onTap: () => onJumpTo(a),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IconForKind extends StatelessWidget {
  final Annotation a;
  final PalimpsestColors colors;
  const _IconForKind({required this.a, required this.colors});

  @override
  Widget build(BuildContext context) {
    switch (a.kind) {
      case AnnotationKind.highlight:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: a.color.swatch,
            shape: BoxShape.circle,
          ),
        );
      case AnnotationKind.bookmark:
        return Icon(Icons.bookmark, color: colors.accent);
      case AnnotationKind.note:
        return Icon(Icons.sticky_note_2_outlined, color: colors.inkSoft);
    }
  }
}

// ---------------------------------------------------------------------------
// Tablet layout — collapsible rail + expanded sidebar + full audio footer.
// Mirrors `iosCollapsedRail` / `iosExpandedSidebar` / `iosAudioFooter` from
// the iPad path in `App/ReaderView+iOS.swift`.
// ---------------------------------------------------------------------------

enum _SidebarTab { chapters, bookmarks, notes }

enum _FooterAction { replace }

/// Thin toolbar above the reader page on tablet / desktop. Same shape as
/// the iPhone header (back, title, overflow) but slimmer — used to make
/// "return to library" and the overflow menu discoverable on a layout
/// that doesn't have the phone's chevron-back.
class _TabletTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onOverflow;
  final PalimpsestColors colors;
  const _TabletTopBar({
    required this.title,
    required this.onOverflow,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // No back button here — the collapsed sidebar rail on the
            // left already exposes a Back-to-Library affordance.
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.inkSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            _CircleHeaderBtn(
              icon: const Icon(Icons.more_horiz, size: 18),
              colors: colors,
              onTap: onOverflow,
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapsedRail extends StatelessWidget {
  final _SidebarTab currentTab;
  final ValueChanged<_SidebarTab> onTab;
  final VoidCallback onToggleExpand;
  final VoidCallback onSettings;
  final VoidCallback onBackToLibrary;
  final PalimpsestColors colors;
  const _CollapsedRail({
    required this.currentTab,
    required this.onTab,
    required this.onToggleExpand,
    required this.onSettings,
    required this.onBackToLibrary,
    required this.colors,
  });

  IconData _iconFor(_SidebarTab t) {
    switch (t) {
      case _SidebarTab.chapters:
        return Icons.list;
      case _SidebarTab.bookmarks:
        return Icons.bookmark_outline;
      case _SidebarTab.notes:
        return Icons.text_snippet_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      color: colors.canvasCool,
      child: Column(
        children: [
          const SizedBox(height: 14),
          // Top button used to also be "expand sidebar", which made it look
          // identical to the chapters tab beneath. Replaced with a return-
          // to-library affordance so there's a clear way out of the reader
          // on tablet / desktop where the phone's back chevron isn't shown.
          _RailButton(
            icon: CupertinoIcons.chevron_back,
            colors: colors,
            isSelected: false,
            onTap: onBackToLibrary,
          ),
          const SizedBox(height: 14),
          for (final t in _SidebarTab.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _RailButton(
                icon: _iconFor(t),
                colors: colors,
                isSelected: t == currentTab,
                onTap: () => onTab(t),
              ),
            ),
          const Spacer(),
          _RailButton(
            icon: Icons.settings_outlined,
            colors: colors,
            isSelected: false,
            onTap: onSettings,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final PalimpsestColors colors;
  const _RailButton({
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isSelected
                ? colors.accent.withValues(alpha: 0.14)
                : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected ? colors.accent : colors.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _ExpandedSidebar extends StatelessWidget {
  final StoredBook book;
  final AnnotationStore annotations;
  final int currentSegmentIndex;
  final _SidebarTab tab;
  final ValueChanged<_SidebarTab> onTab;
  final ValueChanged<int> onPickChapter;
  final ValueChanged<Annotation> onJumpToAnnotation;
  final VoidCallback onCollapse;
  final PalimpsestColors colors;

  const _ExpandedSidebar({
    required this.book,
    required this.annotations,
    required this.currentSegmentIndex,
    required this.tab,
    required this.onTab,
    required this.onPickChapter,
    required this.onJumpToAnnotation,
    required this.onCollapse,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      color: colors.canvasCool,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.inkMuted,
                            fontSize: 12,
                            fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onCollapse,
                  icon: Icon(Icons.menu_open,
                      size: 18, color: colors.inkMuted),
                ),
              ],
            ),
          ),
          Container(height: 1, color: colors.hairline),
          _SidebarTabBar(
            current: tab,
            onTab: onTab,
            colors: colors,
          ),
          Container(height: 1, color: colors.hairline),
          Expanded(
            child: ListenableBuilder(
              listenable: annotations,
              builder: (_, _) {
                switch (tab) {
                  case _SidebarTab.chapters:
                    return _ChapterList(
                      book: book,
                      currentSegmentIndex: currentSegmentIndex,
                      onPickChapter: onPickChapter,
                      colors: colors,
                    );
                  case _SidebarTab.bookmarks:
                    return _AnnotationList(
                      annotations: annotations.items
                          .where((a) =>
                              a.kind == AnnotationKind.bookmark ||
                              a.kind == AnnotationKind.highlight)
                          .toList(),
                      book: book,
                      onJumpTo: onJumpToAnnotation,
                      colors: colors,
                      emptyLabel:
                          'Long-press a paragraph to bookmark or highlight it.',
                    );
                  case _SidebarTab.notes:
                    return _AnnotationList(
                      annotations: annotations.items
                          .where((a) => a.kind == AnnotationKind.note)
                          .toList(),
                      book: book,
                      onJumpTo: onJumpToAnnotation,
                      colors: colors,
                      emptyLabel: 'Long-press a paragraph to add a note.',
                    );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTabBar extends StatelessWidget {
  final _SidebarTab current;
  final ValueChanged<_SidebarTab> onTab;
  final PalimpsestColors colors;
  const _SidebarTabBar({
    required this.current,
    required this.onTab,
    required this.colors,
  });

  String _labelFor(_SidebarTab t) {
    switch (t) {
      case _SidebarTab.chapters:
        return 'Chapters';
      case _SidebarTab.bookmarks:
        return 'Bookmarks';
      case _SidebarTab.notes:
        return 'Notes';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          for (final t in _SidebarTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onTab(t),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: t == current
                        ? colors.accent.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: t == current ? colors.accent : colors.hairline,
                    ),
                  ),
                  child: Text(
                    _labelFor(t),
                    style: TextStyle(
                      color: t == current ? colors.accent : colors.inkMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterList extends StatelessWidget {
  final StoredBook book;
  final int currentSegmentIndex;
  final ValueChanged<int> onPickChapter;
  final PalimpsestColors colors;
  const _ChapterList({
    required this.book,
    required this.currentSegmentIndex,
    required this.onPickChapter,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: book.segments.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: colors.hairline),
      itemBuilder: (_, i) {
        final s = book.segments[i];
        final selected = i == currentSegmentIndex;
        final title = s.title?.trim().isNotEmpty == true
            ? s.title!.trim()
            : 'Section ${i + 1}';
        return Material(
          color: selected ? colors.canvas : Colors.transparent,
          child: InkWell(
            onTap: () => onPickChapter(i),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    color: selected ? colors.accent : Colors.transparent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: selected ? colors.accent : colors.ink,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: colors.inkMuted,
                      fontSize: 10,
                      fontFamilyFallback: const [
                        'JetBrains Mono',
                        'Cascadia Code',
                        'Roboto Mono',
                        'monospace',
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnnotationList extends StatelessWidget {
  final List<Annotation> annotations;
  final StoredBook book;
  final ValueChanged<Annotation> onJumpTo;
  final String emptyLabel;
  final PalimpsestColors colors;
  const _AnnotationList({
    required this.annotations,
    required this.book,
    required this.onJumpTo,
    required this.emptyLabel,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (annotations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            emptyLabel,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.inkMuted, fontSize: 12),
          ),
        ),
      );
    }
    final sorted = [...annotations]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: sorted.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: colors.hairline),
      itemBuilder: (_, i) {
        final a = sorted[i];
        final segTitle = book.segments
                .firstWhere((s) => s.id == a.segmentId,
                    orElse: () => book.segments.first)
                .title ??
            'Section';
        return InkWell(
          onTap: () => onJumpTo(a),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  segTitle.toUpperCase(),
                  style: TextStyle(
                    color: colors.inkMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  a.quote,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.ink, fontSize: 12),
                ),
                if (a.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    a.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.inkSoft,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TabletAudioFooter extends StatelessWidget {
  final PalimpsestAudioPlayer player;
  final StoredBook book;
  final bool hasAlignment;
  final bool isAligning;
  final VoidCallback onAttach;
  final VoidCallback onAlign;
  final VoidCallback onReplaceAudio;
  final PalimpsestColors colors;
  const _TabletAudioFooter({
    required this.player,
    required this.book,
    required this.hasAlignment,
    required this.isAligning,
    required this.onAttach,
    required this.onAlign,
    required this.onReplaceAudio,
    required this.colors,
  });

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (_, _) {
        final hasAudio = book.audioPath != null;
        if (!hasAudio) {
          return Container(
            height: 64,
            decoration: BoxDecoration(
              color: colors.canvasCool,
              border: Border(top: BorderSide(color: colors.hairline)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Icon(Icons.headphones,
                    size: 18, color: colors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Attach an audiobook to begin sync.',
                    style: TextStyle(color: colors.inkSoft, fontSize: 13),
                  ),
                ),
                Material(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onAttach,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: Text(
                        'Attach',
                        style: TextStyle(
                          color: colors.onAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: colors.canvasCool,
            border: Border(top: BorderSide(color: colors.hairline)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(CupertinoIcons.gobackward_15),
                color: colors.inkSoft,
                iconSize: 22,
                onPressed: player.isReady
                    ? () => player.skip(const Duration(seconds: -15))
                    : null,
              ),
              Material(
                color: colors.accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: player.isReady ? player.togglePlay : null,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      player.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: colors.onAccent,
                      size: 24,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.goforward_15),
                color: colors.inkSoft,
                iconSize: 22,
                onPressed: player.isReady
                    ? () => player.skip(const Duration(seconds: 15))
                    : null,
              ),
              const SizedBox(width: 12),
              Text(_fmt(player.position),
                  style: _mono(colors.inkMuted)),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: colors.accent,
                    inactiveTrackColor: colors.hairlineStrong,
                    thumbColor: colors.accent,
                    overlayColor:
                        colors.accent.withValues(alpha: 0.18),
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    min: 0,
                    max: (player.duration?.inMilliseconds ?? 1).toDouble(),
                    value: player.position.inMilliseconds
                        .clamp(
                            0, (player.duration?.inMilliseconds ?? 1))
                        .toDouble(),
                    onChanged: (v) => player.seekSeconds(v / 1000.0),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(_fmt(player.duration ?? Duration.zero),
                  style: _mono(colors.inkMuted)),
              const SizedBox(width: 12),
              _FooterRatePill(player: player, colors: colors),
              const SizedBox(width: 8),
              _FooterSleepPill(player: player, colors: colors),
              const SizedBox(width: 8),
              _FooterAlignPill(
                hasAlignment: hasAlignment,
                isAligning: isAligning,
                onTap: onAlign,
                colors: colors,
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_FooterAction>(
                tooltip: 'More',
                icon: Icon(Icons.more_horiz,
                    size: 18, color: colors.inkSoft),
                color: colors.canvas,
                onSelected: (a) {
                  switch (a) {
                    case _FooterAction.replace:
                      onReplaceAudio();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem<_FooterAction>(
                    value: _FooterAction.replace,
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz,
                            size: 18, color: colors.inkSoft),
                        const SizedBox(width: 10),
                        Text('Replace audiobook…',
                            style: TextStyle(color: colors.ink)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static TextStyle _mono(Color c) => TextStyle(
        color: c,
        fontSize: 11,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontFamilyFallback: const [
          'JetBrains Mono',
          'Cascadia Code',
          'Roboto Mono',
          'monospace',
        ],
      );
}

class _FooterRatePill extends StatelessWidget {
  final PalimpsestAudioPlayer player;
  final PalimpsestColors colors;
  const _FooterRatePill({required this.player, required this.colors});

  @override
  Widget build(BuildContext context) {
    const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    return PopupMenuButton<double>(
      tooltip: 'Playback rate',
      onSelected: player.setRate,
      itemBuilder: (_) => [
        for (final r in rates)
          PopupMenuItem(
            value: r,
            child: Text(
              '${r.toStringAsFixed(r == r.toInt() ? 1 : 2)}x',
              style: TextStyle(
                color: r == player.rate ? colors.accent : colors.ink,
                fontWeight:
                    r == player.rate ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
      ],
      child: _FooterPill(
        text:
            '${player.rate.toStringAsFixed(player.rate == player.rate.toInt() ? 1 : 2)}x',
        icon: Icons.speed,
        colors: colors,
      ),
    );
  }
}

class _FooterSleepPill extends StatelessWidget {
  final PalimpsestAudioPlayer player;
  final PalimpsestColors colors;
  const _FooterSleepPill({required this.player, required this.colors});

  @override
  Widget build(BuildContext context) {
    const options = <(String, Duration?)>[
      ('Off', null),
      ('5 min', Duration(minutes: 5)),
      ('15 min', Duration(minutes: 15)),
      ('30 min', Duration(minutes: 30)),
      ('60 min', Duration(minutes: 60)),
    ];
    final left = player.sleepRemaining;
    final label = left == null
        ? 'Sleep'
        : (left.inSeconds >= 60
            ? '${(left.inSeconds / 60).ceil()}m'
            : '${left.inSeconds}s');
    return PopupMenuButton<Duration?>(
      tooltip: 'Sleep timer',
      onSelected: player.setSleepTimer,
      itemBuilder: (_) => [
        for (final (l, d) in options) PopupMenuItem(value: d, child: Text(l)),
      ],
      child: _FooterPill(
        text: label,
        icon: Icons.bedtime_outlined,
        colors: colors,
        active: player.hasSleepTimer,
      ),
    );
  }
}

class _FooterAlignPill extends StatelessWidget {
  final bool hasAlignment;
  final bool isAligning;
  final VoidCallback onTap;
  final PalimpsestColors colors;
  const _FooterAlignPill({
    required this.hasAlignment,
    required this.isAligning,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: hasAlignment ? colors.canvas : colors.accent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: isAligning ? null : onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: hasAlignment
                ? Border.all(color: colors.hairline)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAligning)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                        hasAlignment ? colors.accent : colors.onAccent),
                  ),
                )
              else
                Icon(
                  hasAlignment ? Icons.refresh : Icons.auto_awesome,
                  size: 14,
                  color: hasAlignment ? colors.accent : colors.onAccent,
                ),
              const SizedBox(width: 6),
              Text(
                hasAlignment ? 'Re-align' : 'Align',
                style: TextStyle(
                  color: hasAlignment ? colors.accent : colors.onAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alignment fullscreen — first-run overlay matching iOS `alignmentFullscreen`.
// ---------------------------------------------------------------------------

class _AlignmentFullscreen extends StatefulWidget {
  final StoredBook book;
  final AlignStage stage;
  final PalimpsestColors colors;
  final VoidCallback onContinueInBackground;
  const _AlignmentFullscreen({
    required this.book,
    required this.stage,
    required this.colors,
    required this.onContinueInBackground,
  });

  @override
  State<_AlignmentFullscreen> createState() => _AlignmentFullscreenState();
}

class _AlignmentFullscreenState extends State<_AlignmentFullscreen> {
  static const _phases = ['Downloading', 'Transcribing', 'Aligning'];

  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _resetForLabel(widget.stage.label);
  }

  @override
  void didUpdateWidget(covariant _AlignmentFullscreen old) {
    super.didUpdateWidget(old);
    if (widget.stage.label != old.stage.label) {
      _resetForLabel(widget.stage.label);
    }
  }

  /// `transcribeChunked` falls back to a single-call transcribe for audio
  /// short enough to fit in one whisper pass, and that path can't emit a
  /// real fraction. The elapsed timer kicks in only in those cases — it
  /// proves the work is alive while the indeterminate `LinearProgressIndicator`
  /// runs. Long audiobooks always have a real `i / N` fraction from the
  /// chunked path and skip this.
  void _resetForLabel(String label) {
    _ticker?.cancel();
    _ticker = null;
    _elapsed = Duration.zero;
    if (_isLongRunning(label)) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
      });
    }
  }

  bool _isLongRunning(String label) {
    final s = label.toLowerCase();
    return s.contains('transcrib') || s.contains('align');
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int get _phaseIdx {
    final s = widget.stage.label.toLowerCase();
    if (s.startsWith('downloading') || s.startsWith('preparing')) return 0;
    if (s.contains('transcrib')) return 1;
    if (s.contains('align') || s.contains('done')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage;
    final book = widget.book;
    final colors = widget.colors;
    final onContinueInBackground = widget.onContinueInBackground;
    final pct = stage.fraction == null
        ? null
        : (stage.fraction!.clamp(0.0, 1.0) * 100).round();
    return Container(
      color: colors.canvas,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              _CoverThumb(book: book, colors: colors),
              const SizedBox(height: 32),
              Text(
                'ALIGNING · DO NOT QUIT',
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                stage.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  'Whisper is transcribing the audiobook on this device and anchoring each paragraph to where it lands in the audio. You can leave this screen open or read while it runs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.inkSoft,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: stage.fraction,
                      backgroundColor: colors.hairlineStrong,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(colors.accent),
                      minHeight: 4,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            pct != null
                                ? '$pct%'
                                : (_ticker != null
                                    ? _formatElapsed(_elapsed)
                                    : ''),
                            style: TextStyle(
                                color: colors.inkMuted,
                                fontSize: 11,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ]),
                          ),
                          Text(_phases[_phaseIdx],
                              style: TextStyle(
                                  color: colors.inkMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _phases.length; i++) ...[
                    if (i > 0)
                      Container(
                        width: 32,
                        height: 1,
                        color: colors.hairline,
                      ),
                    _PhaseTick(
                      label: _phases[i],
                      isActive: i == _phaseIdx,
                      isDone: i < _phaseIdx,
                      colors: colors,
                    ),
                  ],
                ],
              ),
              const Spacer(),
              TextButton(
                onPressed: onContinueInBackground,
                child: Text(
                  'Continue in background',
                  style: TextStyle(
                    color: colors.inkSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  final StoredBook book;
  final PalimpsestColors colors;
  const _CoverThumb({required this.book, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 180,
      decoration: BoxDecoration(
        color: colors.canvasDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: book.coverPath != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.file(
                File(book.coverPath!),
                fit: BoxFit.cover,
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  book.title,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.inkSoft,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ),
            ),
    );
  }
}

class _PhaseTick extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isDone;
  final PalimpsestColors colors;
  const _PhaseTick({
    required this.label,
    required this.isActive,
    required this.isDone,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = isActive
        ? colors.accent
        : isDone
            ? colors.accent.withValues(alpha: 0.55)
            : colors.hairlineStrong;
    final textColor = isActive ? colors.ink : colors.inkMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _FooterPill extends StatelessWidget {
  final String text;
  final IconData icon;
  final PalimpsestColors colors;
  final bool active;
  const _FooterPill({
    required this.text,
    required this.icon,
    required this.colors,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? colors.accent : colors.inkSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color:
            active ? colors.accent.withValues(alpha: 0.18) : colors.canvas,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: active ? colors.accent : colors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
