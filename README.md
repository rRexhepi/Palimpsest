# Palimpsest

macOS + iOS reading app that pairs an audiobook with its ebook and plays them in sync. Toggle word-level or sentence-level highlighting, control playback speed without pitch drift, annotate freely.

## Structure

- `App/` — Mac app target sources (SwiftUI). iOS target will live alongside.
- `PalimpsestCore/` — Swift Package with the cross-platform core (alignment, audio, models, import).
- `project.yml` — XcodeGen spec, source of truth for the Xcode project.
- `Palimpsest.xcodeproj` — generated from `project.yml` via `xcodegen generate`. Do not edit project settings directly in Xcode; edit `project.yml` and regenerate.

## Core modules

- `Alignment/` — whisper.cpp transcription + DTW alignment of audio to ebook text. Caches both word- and sentence-level maps per book.
- `Audio/` — AVAudioEngine wrapper for time-stretch playback without pitch shift.
- `Import/` — EPUB parsing, PDF → EPUB via Calibre `ebook-convert` (Mac only, runs at import time).
- `Models/` — SwiftData models for books, annotations, reading progress. CloudKit sync optional.

## Stack

- SwiftUI multi-platform, SwiftData, AVAudioEngine.
- whisper.cpp (local) for word-level timestamps; DTW for text alignment.
- Calibre `ebook-convert` for PDF → EPUB at import time.
- Custom EPUB renderer (not Readium). Annotations anchored to EPUB CFI ranges.
- Page transitions: 2D slide with shadow + parallax for v1; Metal page-curl as a v2 polish pass.

## Build

```bash
open Palimpsest.xcodeproj
```

Select the **Palimpsest** scheme + **My Mac**, then ⌘R. Sandboxed, ad-hoc signed, runs locally without an Apple Developer team.

## Regenerate project

Project file is generated from `project.yml`:

```bash
brew install xcodegen   # one-time
xcodegen generate
```

## Regenerate app icon

The icon is rendered programmatically — a deep ink serif "P" over a faded ghost "P" on parchment, the literal meaning of *palimpsest*. Edit `Scripts/generate_icon.swift` and run:

```bash
swift Scripts/generate_icon.swift App/Assets.xcassets/AppIcon.appiconset
```

## Test

Core library tests run via SwiftPM:

```bash
cd PalimpsestCore && swift test
```

## Status

- ✅ Mac app target builds, runs, sandboxed.
- ✅ AudioEngine: pitch-preserving 0.5x–2x playback, exercised via the in-app testbed.
- 🚧 Ingest pipeline (EPUB import, PDF→EPUB, Whisper alignment) — stubbed as protocols.
- 🚧 Reader UI — not started. Current UI is the testbed.
- 🚧 iOS target — not added.
