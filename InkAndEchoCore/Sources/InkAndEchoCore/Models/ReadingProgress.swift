import Foundation
import SwiftData

@Model
public final class ReadingProgress {
    @Attribute(.unique) public var id: UUID
    public var book: Book?
    /// Last visible position in the ebook, expressed as an EPUB CFI.
    public var currentCFI: String
    /// Last audio position in seconds. Stays in sync with currentCFI through
    /// the AlignmentMap so resuming on either side picks up the other side.
    public var currentAudioSeconds: TimeInterval
    /// Page index inside the chapter at last view. In spread mode this is
    /// the left-page index; the reader rounds it to the spread on restore.
    /// Defaulted so existing rows migrate to 0 transparently.
    public var currentPageIndex: Int = 0
    public var lastReadAt: Date

    public init(
        id: UUID = UUID(),
        book: Book? = nil,
        currentCFI: String = "",
        currentAudioSeconds: TimeInterval = 0,
        currentPageIndex: Int = 0,
        lastReadAt: Date = .now
    ) {
        self.id = id
        self.book = book
        self.currentCFI = currentCFI
        self.currentAudioSeconds = currentAudioSeconds
        self.currentPageIndex = currentPageIndex
        self.lastReadAt = lastReadAt
    }
}
