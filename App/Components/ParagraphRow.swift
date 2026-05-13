import SwiftUI
import PalimpsestCore
#if os(iOS)
import UIKit
#endif

/// Active-word highlighting mode for `ParagraphRow`. Set to `.none` to
/// disable; word/sentence variants tint the audible word or its sentence
/// while the audiobook plays at 1× rate.
enum HighlightMode {
    case word
    case sentence
    case none
}

/// One paragraph as it appears on the reader page.
///
/// Layout: a 16pt margin column on the left (bookmark / note indicators),
/// the selectable serif text in the middle, and a 22pt actions column on
/// the right (`⋯` menu — highlight, bookmark, add note, play-from-here).
/// The paragraph itself uses 17pt system serif at `lineSpacing(8)`, and
/// gets a tinted background pill when a highlight annotation is attached.
struct ParagraphRow: View {
    let text: String
    let paragraphIndex: Int
    let wordOffset: Int
    let seekEnabled: Bool
    let activeLocalWordIndex: Int?
    let highlightMode: HighlightMode
    let annotations: [Annotation]
    let onPlayFromWord: (Int) -> Void
    let onHighlight: (AnnotationColor) -> Void
    let onBookmark: () -> Void
    let onAddNote: () -> Void
    let onTapNote: (Annotation) -> Void
    let onDelete: (Annotation) -> Void

    private var highlight: Annotation? { annotations.first(where: { $0.kind == .highlight }) }
    private var bookmark: Annotation? { annotations.first(where: { $0.kind == .bookmark }) }
    private var notes: [Annotation] { annotations.filter { $0.kind == .note } }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            margin
            paragraphText
            actionsButton
        }
    }

    private var actionsButton: some View {
        Menu {
            contextMenuContent
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.callout)
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 22)
    }

    private var margin: some View {
        VStack(spacing: 4) {
            if bookmark != nil {
                Image(systemName: "bookmark.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
            }
            ForEach(notes) { note in
                Button {
                    onTapNote(note)
                } label: {
                    Image(systemName: "text.bubble.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 16, alignment: .center)
        .padding(.top, 4)
    }

    private var paragraphText: some View {
        Text(buildAttributedString())
            .font(.system(size: 17, design: .serif))
            .lineSpacing(8)
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, highlight != nil ? 8 : 0)
            .padding(.vertical, highlight != nil ? 4 : 0)
            .background(highlightBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contextMenu { contextMenuContent }
    }

    private func buildAttributedString() -> AttributedString {
        var result = AttributedString()
        var inWord = false
        var wordStart = text.startIndex
        var localWordIdx = 0
        var ranges: [(local: Int, range: Range<AttributedString.Index>)] = []

        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch.isWhitespace || ch.isNewline {
                if inWord {
                    let wordSlice = String(text[wordStart..<i])
                    appendWord(wordSlice, localIndex: localWordIdx, into: &result, ranges: &ranges)
                    localWordIdx += 1
                    inWord = false
                }
                result.append(AttributedString(String(ch)))
            } else {
                if !inWord {
                    wordStart = i
                    inWord = true
                }
            }
            i = text.index(after: i)
        }
        if inWord {
            let wordSlice = String(text[wordStart..<text.endIndex])
            appendWord(wordSlice, localIndex: localWordIdx, into: &result, ranges: &ranges)
        }

        if let active = activeLocalWordIndex {
            switch highlightMode {
            case .word:
                if let entry = ranges.first(where: { $0.local == active }) {
                    result[entry.range].backgroundColor = Theme.highlightWordSoft
                }
            case .sentence:
                if let sentenceRange = sentenceCharRange(containingWordAt: active),
                   let attrSubrange = attributedRange(for: sentenceRange, in: result) {
                    result[attrSubrange].backgroundColor = Theme.highlightSentence.opacity(0.20)
                }
            case .none:
                break
            }
        }

        return result
    }

    private func sentenceCharRange(containingWordAt localIdx: Int) -> NSRange? {
        let nsText = text as NSString
        var wordRanges: [NSRange] = []
        var inWord = false
        var wordStart = 0
        for i in 0..<nsText.length {
            let scalar = Unicode.Scalar(nsText.character(at: i))
            let isWS = scalar.map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
            if isWS {
                if inWord {
                    wordRanges.append(NSRange(location: wordStart, length: i - wordStart))
                    inWord = false
                }
            } else if !inWord {
                wordStart = i
                inWord = true
            }
        }
        if inWord {
            wordRanges.append(NSRange(location: wordStart, length: nsText.length - wordStart))
        }
        guard localIdx >= 0, localIdx < wordRanges.count else { return nil }

        let wordCenter = wordRanges[localIdx].location + wordRanges[localIdx].length / 2

        var match: NSRange?
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: .bySentences
        ) { _, range, _, stop in
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            if wordCenter >= start && wordCenter < end {
                match = NSRange(location: start, length: end - start)
                stop = true
            }
        }
        return match
    }

    private func attributedRange(for nsRange: NSRange, in attributed: AttributedString) -> Range<AttributedString.Index>? {
        guard let stringRange = Range(nsRange, in: text) else { return nil }
        let sentenceText = String(text[stringRange])
        return attributed.range(of: sentenceText)
    }

    private func appendWord(_ word: String, localIndex: Int, into result: inout AttributedString, ranges: inout [(local: Int, range: Range<AttributedString.Index>)]) {
        var attr = AttributedString(word)
        attr.foregroundColor = Theme.ink
        // Word-level highlight: tinted background on just this word. The
        // paragraph-level highlight (the wider pill) is rendered separately
        // by `highlightBackground` so both can coexist visually.
        if let wordColor = wordHighlights[localIndex] {
            attr.backgroundColor = colorView(for: wordColor).opacity(0.30)
        }
        #if !os(macOS)
        // Tap target. Routed to the parent via OpenURL → handleHighlightURL
        // → toggleWordHighlight. Long-press still falls through to the
        // system text-selection menu because `.link` only claims a tap.
        if let url = URL(string: "palimpsest://highlight/\(paragraphIndex)/\(localIndex)") {
            attr.link = url
        }
        #endif
        let start = result.endIndex
        result.append(attr)
        let end = result.endIndex
        ranges.append((localIndex, start..<end))
    }

    /// Word index → highlight color for every word-level highlight on this
    /// paragraph. Built once per body evaluation (cheap; bookmarks and
    /// notes are filtered out, so the dictionary is small in practice).
    private var wordHighlights: [Int: AnnotationColor] {
        var map: [Int: AnnotationColor] = [:]
        for a in annotations where a.kind == .highlight {
            if let loc = a.wordLocation,
               loc.paragraphIndex == paragraphIndex {
                map[loc.wordIndex] = a.color
            }
        }
        return map
    }

    @ViewBuilder
    private var highlightBackground: some View {
        if let highlight {
            colorView(for: highlight.color).opacity(0.22)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        // Always-visible entry point. Disabled when no AlignmentMap exists
        // yet so users discover the feature even before running alignment;
        // the button label switches to an instruction in that case.
        Button {
            onPlayFromWord(0)
        } label: {
            Label(
                seekEnabled ? "Play audiobook from here" : "Play from here (align audio first)",
                systemImage: "play.fill"
            )
        }
        .disabled(!seekEnabled)
        Divider()
        if highlight == nil {
            Menu("Highlight") {
                ForEach(AnnotationColor.allCases, id: \.self) { color in
                    colorPickerButton(for: color)
                }
            }
        } else {
            Button("Remove Highlight") {
                if let h = highlight { onDelete(h) }
            }
            Menu("Change Color") {
                ForEach(AnnotationColor.allCases, id: \.self) { color in
                    colorPickerButton(for: color)
                }
            }
        }

        Divider()

        Button(bookmark == nil ? "Add Bookmark" : "Remove Bookmark") {
            onBookmark()
        }
        Button("Add Note…") {
            onAddNote()
        }

        if !notes.isEmpty {
            Divider()
            ForEach(notes) { note in
                Menu(notePreview(note)) {
                    Button("View") { onTapNote(note) }
                    Button(role: .destructive) {
                        onDelete(note)
                    } label: {
                        Text("Delete")
                    }
                }
            }
        }
    }

    private func colorView(for color: AnnotationColor) -> Color {
        switch color {
        case .amber: return Color(red: 199/255, green: 151/255, blue: 63/255)
        case .sage:  return Color(red: 155/255, green: 171/255, blue: 142/255)
        case .rose:  return Color(red: 192/255, green: 149/255, blue: 147/255)
        case .slate: return Color(red: 122/255, green: 135/255, blue: 148/255)
        case .plum:  return Color(red: 155/255, green: 126/255, blue: 146/255)
        }
    }

    @ViewBuilder
    private func colorPickerButton(for color: AnnotationColor) -> some View {
        Button {
            onHighlight(color)
        } label: {
            // iOS Menu items strip `foregroundStyle` from a Label's
            // systemImage, leaving the circle the menu's default tint
            // (black/ink). Pre-tinting a UIImage with .alwaysOriginal
            // preserves the color when UIKit renders the UIMenuElement.
            #if os(iOS)
            Label {
                Text(color.rawValue.capitalized)
            } icon: {
                Image(uiImage: tintedCircle(for: color))
            }
            #else
            Label(color.rawValue.capitalized, systemImage: "circle.fill")
                .foregroundStyle(colorView(for: color))
            #endif
        }
    }

    #if os(iOS)
    private func tintedCircle(for color: AnnotationColor) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let base = UIImage(systemName: "circle.fill", withConfiguration: config) ?? UIImage()
        return base.withTintColor(UIColor(colorView(for: color)), renderingMode: .alwaysOriginal)
    }
    #endif

    private func notePreview(_ note: Annotation) -> String {
        let snippet = note.note.prefix(40)
        return "Note: \(snippet)\(note.note.count > 40 ? "…" : "")"
    }
}
