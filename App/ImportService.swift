import Foundation
import AVFoundation
import SwiftData
import PalimpsestCore

@MainActor
struct ImportService {
    let modelContext: ModelContext

    /// Imports a book from a `.epub` URL. The resulting `Book` is persisted
    /// with file URLs pointing into the app's Application Support directory.
    ///
    /// PDF support was previously available on macOS via Calibre's
    /// `ebook-convert` Process spawn. That path is dormant — App Sandbox
    /// (required for App Store distribution) blocks subprocess execution
    /// of arbitrary binaries. The `CalibreConverter` source is kept in
    /// `PalimpsestCore` but no longer invoked.
    func importBook(from sourceURL: URL) async throws -> Book {
        let ext = sourceURL.pathExtension.lowercased()
        let epubURL: URL

        switch ext {
        case "epub":
            epubURL = sourceURL
        case "pdf":
            throw ImportServiceError.pdfNotSupported
        default:
            throw ImportServiceError.unsupportedFormat(ext)
        }

        // `.fileImporter` returns security-scoped URLs on iOS; reads
        // succeed only between start/stop calls. Without this, the
        // ZIP open + copy below fail with EPERM and the picker appears
        // to silently no-op.
        let needsScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if needsScope { sourceURL.stopAccessingSecurityScopedResource() } }

        let importer = EPUBImporter()
        let imported = try await importer.importBook(from: epubURL)

        let bookID = UUID()
        let bookDir = try appStorageURL()
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

        let storedEPUB = bookDir.appendingPathComponent("book.epub")
        try FileManager.default.copyItem(at: epubURL, to: storedEPUB)

        let book = Book(
            id: bookID,
            title: imported.title,
            author: imported.author,
            coverImageData: imported.coverImageData,
            ebookFileURL: storedEPUB,
            audiobookFileURL: nil,
            alignmentMapURL: nil,
            totalDurationSeconds: 0,
            totalPages: imported.totalPages,
            addedAt: .now
        )
        modelContext.insert(book)
        try modelContext.save()
        return book
    }

    /// Attaches an audiobook file to an existing book. Copies the file into the
    /// book's storage directory and reads its duration for display.
    func attachAudiobook(_ url: URL, to book: Book) async throws {
        guard let ebookURL = book.resolvedEbookURL else {
            throw ImportServiceError.missingEbook
        }
        let bookDir = ebookURL.deletingLastPathComponent()
        let stored = bookDir.appendingPathComponent("audiobook.\(url.pathExtension)")

        // See `importBook` — picker URLs are security-scoped on iOS and
        // the copy below fails silently without start/stop access.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        // Replace path: nuke every prior `audiobook.*` file (the new pick
        // may have a different extension than the previous one, so a
        // same-name remove isn't enough) and invalidate the alignment map
        // — it was computed against the old audio and the new one almost
        // certainly has different word timestamps.
        if let contents = try? FileManager.default.contentsOfDirectory(at: bookDir, includingPropertiesForKeys: nil) {
            for entry in contents where entry.lastPathComponent.hasPrefix("audiobook.") {
                try? FileManager.default.removeItem(at: entry)
            }
        }
        let alignmentPath = bookDir.appendingPathComponent("alignment.json")
        try? FileManager.default.removeItem(at: alignmentPath)
        book.alignmentMapURL = nil

        try FileManager.default.copyItem(at: url, to: stored)

        let asset = AVURLAsset(url: stored)
        let duration = (try? await asset.load(.duration)) ?? .zero

        book.audiobookFileURL = stored
        book.totalDurationSeconds = CMTimeGetSeconds(duration)
        try modelContext.save()
    }

    /// Removes a book and its on-disk files.
    func deleteBook(_ book: Book) throws {
        if let ebookURL = book.resolvedEbookURL {
            try? FileManager.default.removeItem(at: ebookURL.deletingLastPathComponent())
        }
        modelContext.delete(book)
        try modelContext.save()
    }

    private func appStorageURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("Palimpsest", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum ImportServiceError: LocalizedError {
    case unsupportedFormat(String)
    case missingEbook
    case pdfNotSupported

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported file type: .\(ext). Use .epub."
        case .missingEbook:
            return "Book has no associated ebook file."
        case .pdfNotSupported:
            return "PDF import isn't supported in this build. Convert your PDF to .epub first."
        }
    }
}
