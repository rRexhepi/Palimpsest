#!/usr/bin/env bash
# Bootstrap a Ubuntu 22.04+ / Debian 12+ VM for building Palimpsest (Flutter
# Linux desktop). Idempotent — safe to re-run. Run from inside the VM.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/.../setup-linux-vm.sh | bash
#   # or, if the repo is already cloned:
#   bash xplatform/scripts/setup-linux-vm.sh
set -euo pipefail

FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_INSTALL_DIR="${FLUTTER_INSTALL_DIR:-$HOME/flutter}"

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

say "Installing apt dependencies (Flutter toolchain + media_kit + ffmpeg)"
sudo apt-get update
sudo apt-get install -y \
  curl git unzip xz-utils zip \
  clang lld cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev \
  libmpv-dev mpv \
  ffmpeg

if [ ! -d "$FLUTTER_INSTALL_DIR" ]; then
  say "Cloning Flutter ($FLUTTER_CHANNEL) into $FLUTTER_INSTALL_DIR"
  git clone --depth 1 -b "$FLUTTER_CHANNEL" \
    https://github.com/flutter/flutter.git "$FLUTTER_INSTALL_DIR"
else
  say "Flutter already present at $FLUTTER_INSTALL_DIR — pulling latest"
  git -C "$FLUTTER_INSTALL_DIR" pull --ff-only || true
fi

if ! grep -q "$FLUTTER_INSTALL_DIR/bin" "$HOME/.bashrc" 2>/dev/null; then
  say "Adding Flutter to PATH in ~/.bashrc"
  echo "export PATH=\"\$PATH:$FLUTTER_INSTALL_DIR/bin\"" >> "$HOME/.bashrc"
fi
export PATH="$PATH:$FLUTTER_INSTALL_DIR/bin"

say "Enabling Linux desktop"
flutter config --enable-linux-desktop --no-analytics

say "Verifying toolchain (flutter doctor)"
flutter doctor -v || true

cat <<'EOF'

Setup complete. Next:
  1) Get the source into the VM. Either:
       git clone <repo>            (if pushed)
     or use the UTM shared-folder feature to mount /Users/rexhep/Projects
  2) cd into the xplatform/ directory
  3) flutter pub get
  4) flutter run -d linux            # interactive
       or
     flutter build linux             # produces build/linux/.../bundle/

If `flutter doctor` flags missing dev tools, follow its prompts.

EOF
