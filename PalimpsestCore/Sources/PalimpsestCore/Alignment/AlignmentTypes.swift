import Foundation

/// Input to an aligner: the ebook's text broken into addressable segments
/// (typically chapters or paragraphs). The `id` is a stable identifier
/// — for EPUB-sourced text this is an EPUB CFI; for plaintext it can be
/// any deterministic string.
public struct AlignmentInput: Sendable {
    public let segments: [TextSegment]
    public init(segments: [TextSegment]) { self.segments = segments }
}

public struct TextSegment: Sendable, Hashable {
    public let id: String
    public let title: String?
    public let text: String
    public init(id: String, title: String? = nil, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

/// The output of alignment: timestamps anchored back to the source text.
/// Both word- and sentence-level maps are produced from one alignment pass
/// so the reader can toggle granularity without re-running Whisper.
public struct AlignmentMap: Codable, Sendable {
    public let words: [WordAnchor]
    public let sentences: [SentenceAnchor]
    /// Per-audio-word start timestamps from Whisper, in order. Each entry's
    /// index matches the `audioIndex` used by `WordAnchor` so the reader can
    /// project audio time onto book word position at the narrator's actual
    /// pace instead of uniform time-to-word linear interpolation.
    public let audioWordStarts: [Double]
    public let createdAt: Date
    public let modelIdentifier: String

    public init(
        words: [WordAnchor],
        sentences: [SentenceAnchor],
        audioWordStarts: [Double] = [],
        createdAt: Date,
        modelIdentifier: String
    ) {
        self.words = words
        self.sentences = sentences
        self.audioWordStarts = audioWordStarts
        self.createdAt = createdAt
        self.modelIdentifier = modelIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case words, sentences, audioWordStarts, createdAt, modelIdentifier
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.words = try c.decode([WordAnchor].self, forKey: .words)
        self.sentences = try c.decode([SentenceAnchor].self, forKey: .sentences)
        self.audioWordStarts = (try? c.decode([Double].self, forKey: .audioWordStarts)) ?? []
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.modelIdentifier = try c.decode(String.self, forKey: .modelIdentifier)
    }
}

public struct WordAnchor: Codable, Sendable, Hashable {
    public let segmentId: String
    public let wordIndex: Int
    public let startSeconds: Double
    public let endSeconds: Double
    /// Index into `AlignmentMap.audioWordStarts` where this anchor was matched.
    /// Lets the reader project audio time onto book wordIndex at narrator pace.
    public let audioIndex: Int
    /// 0.0 – 1.0. Below ~0.5, the reader should fall back to sentence highlighting.
    public let confidence: Float

    public init(
        segmentId: String,
        wordIndex: Int,
        startSeconds: Double,
        endSeconds: Double,
        audioIndex: Int = -1,
        confidence: Float
    ) {
        self.segmentId = segmentId
        self.wordIndex = wordIndex
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.audioIndex = audioIndex
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case segmentId, wordIndex, startSeconds, endSeconds, audioIndex, confidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.segmentId = try c.decode(String.self, forKey: .segmentId)
        self.wordIndex = try c.decode(Int.self, forKey: .wordIndex)
        self.startSeconds = try c.decode(Double.self, forKey: .startSeconds)
        self.endSeconds = try c.decode(Double.self, forKey: .endSeconds)
        self.audioIndex = (try? c.decode(Int.self, forKey: .audioIndex)) ?? -1
        self.confidence = try c.decode(Float.self, forKey: .confidence)
    }
}

public struct SentenceAnchor: Codable, Sendable, Hashable {
    public let segmentId: String
    public let sentenceIndex: Int
    public let startSeconds: Double
    public let endSeconds: Double

    public init(segmentId: String, sentenceIndex: Int, startSeconds: Double, endSeconds: Double) {
        self.segmentId = segmentId
        self.sentenceIndex = sentenceIndex
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}
