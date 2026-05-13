#if os(macOS)
import SwiftUI
import AppKit
import PalimpsestCore

/// NSTextView-backed paragraph renderer. Native text selection (drag, ⌘C,
/// double-click for word) works as expected, and a single contextual menu —
/// AppKit's, augmented via the delegate — exposes "Play audiobook from here"
/// plus annotation actions (Highlight / Bookmark / Add Note).
struct ClickableTextView: NSViewRepresentable {
    let attributedString: NSAttributedString
    let onPlayFromCharIndex: (Int) -> Void
    let onHighlight: (AnnotationColor) -> Void
    let onBookmark: () -> Void
    let onAddNote: () -> Void

    func makeNSView(context: Context) -> InternalTextView {
        let textView = InternalTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.allowsUndo = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ view: InternalTextView, context: Context) {
        context.coordinator.onPlayFromCharIndex = onPlayFromCharIndex
        context.coordinator.onHighlight = onHighlight
        context.coordinator.onBookmark = onBookmark
        context.coordinator.onAddNote = onAddNote

        guard let storage = view.textStorage else { return }
        let textChanged = storage.string != attributedString.string

        if textChanged {
            storage.setAttributedString(attributedString)
            view.invalidateIntrinsicContentSize()
        } else {
            // Same text — only refresh background attributes (active word
            // highlight) so we don't blow away an in-progress text selection.
            storage.beginEditing()
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: fullRange)
            attributedString.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: attributedString.length)) { value, range, _ in
                if let color = value {
                    storage.addAttribute(.backgroundColor, value: color, range: range)
                }
            }
            storage.endEditing()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPlayFromCharIndex: onPlayFromCharIndex,
            onHighlight: onHighlight,
            onBookmark: onBookmark,
            onAddNote: onAddNote
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onPlayFromCharIndex: (Int) -> Void
        var onHighlight: (AnnotationColor) -> Void
        var onBookmark: () -> Void
        var onAddNote: () -> Void

        private var pendingCharIndex: Int = 0

        init(
            onPlayFromCharIndex: @escaping (Int) -> Void,
            onHighlight: @escaping (AnnotationColor) -> Void,
            onBookmark: @escaping () -> Void,
            onAddNote: @escaping () -> Void
        ) {
            self.onPlayFromCharIndex = onPlayFromCharIndex
            self.onHighlight = onHighlight
            self.onBookmark = onBookmark
            self.onAddNote = onAddNote
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            pendingCharIndex = charIndex

            var insertionIndex = 0

            let playItem = NSMenuItem(
                title: "Play audiobook from here",
                action: #selector(handlePlay(_:)),
                keyEquivalent: ""
            )
            playItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
            playItem.target = self
            menu.insertItem(playItem, at: insertionIndex); insertionIndex += 1

            let highlightSubmenu = NSMenu()
            for color in AnnotationColor.allCases {
                let item = NSMenuItem(
                    title: color.rawValue.capitalized,
                    action: #selector(handleHighlight(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = color.rawValue
                highlightSubmenu.addItem(item)
            }
            let highlightItem = NSMenuItem(title: "Highlight Paragraph", action: nil, keyEquivalent: "")
            highlightItem.submenu = highlightSubmenu
            highlightItem.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)
            menu.insertItem(highlightItem, at: insertionIndex); insertionIndex += 1

            let bookmarkItem = NSMenuItem(
                title: "Bookmark Paragraph",
                action: #selector(handleBookmark(_:)),
                keyEquivalent: ""
            )
            bookmarkItem.image = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: nil)
            bookmarkItem.target = self
            menu.insertItem(bookmarkItem, at: insertionIndex); insertionIndex += 1

            let noteItem = NSMenuItem(
                title: "Add Note…",
                action: #selector(handleAddNote(_:)),
                keyEquivalent: ""
            )
            noteItem.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: nil)
            noteItem.target = self
            menu.insertItem(noteItem, at: insertionIndex); insertionIndex += 1

            menu.insertItem(NSMenuItem.separator(), at: insertionIndex)
            return menu
        }

        @objc func handlePlay(_ sender: NSMenuItem) {
            onPlayFromCharIndex(pendingCharIndex)
        }

        @objc func handleHighlight(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String,
                  let color = AnnotationColor(rawValue: raw) else { return }
            onHighlight(color)
        }

        @objc func handleBookmark(_ sender: NSMenuItem) {
            onBookmark()
        }

        @objc func handleAddNote(_ sender: NSMenuItem) {
            onAddNote()
        }
    }
}

/// NSTextView subclass that reports its laid-out height as intrinsic content size
/// so SwiftUI can size the row correctly inside a VStack, and that explicitly
/// participates in the responder chain so double-click word selection and ⌘C
/// work as expected.
final class InternalTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override var intrinsicContentSize: NSSize {
        guard let textContainer, let layoutManager else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override var frame: NSRect {
        didSet {
            if frame.size.width != oldValue.size.width {
                invalidateIntrinsicContentSize()
            }
        }
    }
}
#endif
