import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../main.dart' show AppThemeChoice;
import '../persistence/library_storage.dart';
import '../reader/reader_screen.dart';
import '../settings/settings_screen.dart';
import '../state/library_store.dart';
import '../theme.dart';

class LibraryScreen extends StatefulWidget {
  final LibraryStore store;
  final AppThemeChoice currentTheme;
  final ValueChanged<AppThemeChoice> onThemeChanged;
  final bool animationsEnabled;
  final ValueChanged<bool> onAnimationsChanged;
  final ValueChanged<String?> onOpenBook;

  const LibraryScreen({
    super.key,
    required this.store,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.animationsEnabled,
    required this.onAnimationsChanged,
    required this.onOpenBook,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.store.isLoaded) widget.store.load();
  }

  Future<void> _pickAndImport(BuildContext context) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['epub', 'mobi', 'pdf'],
        withData: false,
      );
    } catch (e) {
      if (!context.mounted) return;
      // file_picker on Linux throws UnimplementedError when none of
      // zenity/qarma/kdialog is installed; tell the user how to fix it.
      final msg = Platform.isLinux
          ? 'File picker failed: install zenity (`sudo apt install zenity`) '
              'or kdialog and try again.'
          : 'File picker failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    if (result == null || result.files.single.path == null) return;
    final picked = File(result.files.single.path!);
    final book = await widget.store.importBook(picked);
    if (!context.mounted) return;
    if (book == null && widget.store.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.store.lastError!)),
      );
    } else if (book != null) {
      _openReader(context, book);
    }
  }

  String get _importLabel => Platform.isAndroid ? 'Import EPUB' : 'Import book';

  void _openReader(BuildContext context, StoredBook book) {
    widget.onOpenBook(book.id);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderScreen(
        store: widget.store,
        book: book,
        animationsEnabled: widget.animationsEnabled,
        onOpened: widget.onOpenBook,
      ),
    ));
  }

  Future<void> _confirmDelete(BuildContext context, StoredBook book) async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: colors.canvas,
        title: Text('Remove "${book.title}"?',
            style: TextStyle(color: colors.ink, fontSize: 16)),
        content: Text(
          'Removes the EPUB, audio, alignment, and annotations for this book from this device.',
          style: TextStyle(color: colors.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text('Cancel',
                style: TextStyle(color: colors.inkSoft)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Remove',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.store.delete(book);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        title: const Text('Palimpsest'),
        backgroundColor: colors.canvas,
        leading: IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SettingsScreen(
              currentTheme: widget.currentTheme,
              onThemeChanged: widget.onThemeChanged,
              animationsEnabled: widget.animationsEnabled,
              onAnimationsChanged: widget.onAnimationsChanged,
            ),
          )),
        ),
      ),
      floatingActionButton: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => FloatingActionButton.extended(
          onPressed:
              widget.store.isImporting ? null : () => _pickAndImport(context),
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          icon: widget.store.isImporting
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(colors.onAccent),
                  ),
                )
              : const Icon(Icons.add),
          label: Text(
              widget.store.isImporting ? 'Importing…' : _importLabel),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          if (!widget.store.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (widget.store.books.isEmpty) {
            return _EmptyState(colors: colors);
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              childAspectRatio: 0.52,
            ),
            itemCount: widget.store.books.length,
            itemBuilder: (context, i) => _BookTile(
              book: widget.store.books[i],
              colors: colors,
              onTap: () => _openReader(context, widget.store.books[i]),
              onLongPress: () => _confirmDelete(context, widget.store.books[i]),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final PalimpsestColors colors;
  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 64, color: colors.inkMuted),
            const SizedBox(height: 18),
            Text(
              'Your library is quiet.',
              style: TextStyle(
                color: colors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Import an EPUB to begin. Attach an audiobook from the reader.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: colors.inkMuted, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final StoredBook book;
  final PalimpsestColors colors;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _BookTile({
    required this.book,
    required this.colors,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      onLongPress: onLongPress,
      // Right-click → "Remove from library". Long-press already triggers
      // the same confirmation; this just makes deletion discoverable on
      // desktop where touch-and-hold is not the natural affordance.
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.66,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.canvasDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.hairline),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: book.coverPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Image.file(
                        File(book.coverPath!),
                        fit: BoxFit.cover,
                      ),
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          book.title,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.inkSoft,
                            fontSize: 14,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
          Text(
            book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.inkMuted, fontSize: 12),
          ),
          if (book.audioPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.headphones,
                      size: 12, color: colors.accent),
                  const SizedBox(width: 4),
                  Text(
                    book.alignmentPath != null ? 'aligned' : 'audio',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final colors = context.colors;
    final picked = await showMenu<_BookContextAction>(
      context: context,
      color: colors.canvas,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _BookContextAction.remove,
          child: Row(
            children: [
              const Icon(Icons.delete_outline,
                  size: 18, color: Colors.redAccent),
              const SizedBox(width: 10),
              Text('Remove from library',
                  style: TextStyle(color: colors.ink)),
            ],
          ),
        ),
      ],
    );
    if (picked == _BookContextAction.remove) onLongPress();
  }
}

enum _BookContextAction { remove }
