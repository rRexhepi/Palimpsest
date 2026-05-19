# Ink and Echo — cross-platform Flutter port

Flutter target shell for Ink and Echo. iOS is the reference surface (Swift app
lives in the parent directory); this tree carries Android, Windows, and Linux.

## Targets

| Platform | Status  | Backend notes |
|----------|---------|---------------|
| Android  | working | just_audio (ExoPlayer), ffmpeg_kit, sherpa_onnx (NNAPI) |
| Windows  | working | just_audio_media_kit (libmpv), system ffmpeg, sherpa_onnx (CPU) |
| Linux    | working | just_audio_media_kit (libmpv), system ffmpeg, sherpa_onnx (CPU) |

The iOS build lives in `../App` / `../InkAndEcho.xcodeproj` and is not part
of this Flutter tree.

## Desktop prerequisites

The transcription pipeline shells out to `ffmpeg` + `ffprobe` on desktop (no
native plugin ships those binaries for Windows or Linux — mobile gets them
through `ffmpeg_kit_flutter`). Install both before running:

- **Windows**: `winget install Gyan.FFmpeg` (or `choco install ffmpeg`)
- **Linux**: `sudo apt install ffmpeg` (Debian/Ubuntu) / `sudo dnf install
  ffmpeg` (Fedora)

If the binaries aren't on `PATH`, point at them with environment vars:

```
export INK_AND_ECHO_FFMPEG=/opt/ffmpeg/bin/ffmpeg
export INK_AND_ECHO_FFPROBE=/opt/ffmpeg/bin/ffprobe
```

Linux also needs libmpv at runtime (media_kit_libs_linux pulls in the build
deps, but the host needs the shared lib too):

```
sudo apt install libmpv-dev mpv
```

Windows ships libmpv inside the build output, no host install needed.

Import formats:

| Format | Android | Windows | Linux |
|--------|---------|---------|-------|
| EPUB   | yes (pure Dart) | yes (pure Dart) | yes (pure Dart) |
| MOBI / .prc / .azw | yes (pure Dart) | yes (pure Dart) | yes (pure Dart) |
| AZW3 / KF8 | no — convert with Calibre | no — convert with Calibre | no — convert with Calibre |
| PDF (reflowable) | yes (PDFBox via `read_pdf_text`) | yes (Calibre) | yes (Calibre) |
| PDF (scanned / fixed-layout) | poor | poor | poor |

PDF on desktop uses Calibre's `ebook-convert`. Install it to enable PDF
import on Windows / Linux:

- **Windows**: `winget install calibre` (or download from calibre-ebook.com)
- **Linux**: `sudo apt install calibre` (Debian/Ubuntu) / `sudo dnf install
  calibre` (Fedora)

If `ebook-convert` isn't on `PATH`, point at it explicitly:

```
export INK_AND_ECHO_EBOOK_CONVERT=/opt/calibre/ebook-convert
```

MOBI is parsed by the bundled pure-Dart importer
(`lib/import/mobi_importer.dart`); no Calibre needed. KF8 / .azw3 files
(Amazon's newer Kindle format) are not yet supported by that parser —
convert them with Calibre first.

## Build / run

```
flutter pub get
flutter run -d windows    # or: -d linux, -d android
flutter build windows
flutter build linux
```

## Packaging

Windows: `scripts\package-windows.ps1` builds the release and produces
`dist\ink_and_echo-<version>-windows-x64.exe` via Inno Setup (`winget install
JRSoftware.InnoSetup`). Version is read from `pubspec.yaml`; override with
`-Version 1.2.0`.

## Layout

- `lib/audio/` — `InkAndEchoAudioPlayer`. Mobile `audio_session` and
  `just_audio_background` init are gated behind
  `Platform.isAndroid || Platform.isIOS`.
- `lib/whisper/` — `WhisperTranscriber` plus `FfmpegRunner` (dispatches to
  `ffmpeg_kit` on mobile, `Process.run` on desktop).
- `lib/import/` — EPUB parsing
- `lib/alignment/` — anchor alignment between EPUB text and Whisper words
- `lib/reader/`, `lib/library/`, `lib/onboarding/`, `lib/settings/` — UI

## Simulating desktop builds on macOS

Flutter doesn't cross-compile, so verifying Windows / Linux from a Mac means
running a VM. Apple Silicon path:

1. **Install UTM** (already installed if you ran `brew install --cask utm`).
2. **Get an OS image into UTM:**
   - **Ubuntu Desktop ARM64** — open UTM → "Browse UTM Gallery" → pick the
     Ubuntu 24.04 entry. One-click download + prebuilt VM, no manual install.
   - **Windows 11 ARM** — UTM has a setup wizard that downloads the official
     Microsoft ARM ISO. Requires a free Microsoft account at first boot.
3. **Boot the VM, open a terminal/PowerShell inside, run the setup script:**
   - Linux: `bash xplatform/scripts/setup-linux-vm.sh`
   - Windows (elevated PowerShell):
     `Set-ExecutionPolicy -Scope Process Bypass -Force; .\xplatform\scripts\setup-windows-vm.ps1`
4. **Get the source in.** Either `git clone` inside the VM, or use UTM's
   shared-folder feature (VM settings → Sharing → add `/Users/rexhep/Projects`)
   and mount it inside the VM (`spice-vdagent` is preinstalled on the UTM
   gallery Ubuntu image).
5. **Build:** `cd xplatform && flutter pub get && flutter run -d linux`
   (or `-d windows`).

Headless build-only check (Linux, no GUI required). Lima is the right tool
on Apple Silicon + macOS 26+; Multipass's bundled QEMU has a SME-property
bug on this combo.

```
brew install lima                                    # one-time
limactl start --name=palimp --vm-type=vz --tty=false template://ubuntu-24.04 \
  --cpus 4 --memory 8 --disk 40
limactl shell palimp -- bash $HOME/Projects/InkAndEcho/xplatform/scripts/setup-linux-vm.sh

# Lima mounts $HOME read-only. Copy the source into the VM's writable
# disk before running pub get / build:
limactl shell palimp -- bash -lc '
  rsync -a --delete --exclude=build --exclude=.dart_tool \
    $HOME/Projects/InkAndEcho/xplatform/ ~/xplatform/
  cd ~/xplatform
  ~/flutter/bin/flutter pub get
  ~/flutter/bin/flutter build linux --release
'
```

Output binary: `~/xplatform/build/linux/arm64/release/bundle/palimpsest`.
Headless build is fine for proving the toolchain + linker resolve every
plugin; for clicking around the UI use a full Ubuntu Desktop VM in UTM.

## Why media_kit on desktop

`just_audio` has no native Windows or Linux backend. The community
`just_audio_media_kit` package transparently routes playback through
[media_kit](https://pub.dev/packages/media_kit) (libmpv) on desktop targets
while staying a no-op on Android and iOS, so the same `InkAndEchoAudioPlayer`
runs everywhere.
