#!/usr/bin/env bash
# Render every icon variant from icons/ink-and-echo-1024.svg (Concept D —
# fountain-pen nib touching paper, amber ink point, three echo rings).
#
# Requires: rsvg-convert (`brew install librsvg`), python3 with PIL for the
# Windows .ico. Re-run after editing the SVG.

set -euo pipefail

cd "$(dirname "$0")/.."

SVG=icons/ink-and-echo-1024.svg
SVG_FG=icons/ink-and-echo-foreground.svg

# iOS app icon set (per AppIconIOS.appiconset/Contents.json).
IOS=App/Assets.xcassets/AppIconIOS.appiconset
for size in 1024 180 167 152 120 87 80 76 60 58 40; do
  rsvg-convert -w "$size" -h "$size" "$SVG" -o "$IOS/icon_${size}.png"
done

# In-app onboarding logomark (light + dark, @1x/2x/3x at 96pt frame).
MARK=App/Assets.xcassets/InkAndEchoMark.imageset
rsvg-convert -w 288 -h 288 "$SVG" -o "$MARK/mark.png"
rsvg-convert -w 576 -h 576 "$SVG" -o "$MARK/mark@2x.png"
rsvg-convert -w 864 -h 864 "$SVG" -o "$MARK/mark@3x.png"
rsvg-convert -w 288 -h 288 icons/ink-and-echo-dark-1024.svg -o "$MARK/mark-dark.png"
rsvg-convert -w 576 -h 576 icons/ink-and-echo-dark-1024.svg -o "$MARK/mark-dark@2x.png"
rsvg-convert -w 864 -h 864 icons/ink-and-echo-dark-1024.svg -o "$MARK/mark-dark@3x.png"

# macOS AppKit icon set (kept around for a possible non-Catalyst build).
MAC=App/Assets.xcassets/AppIcon.appiconset
rsvg-convert -w 16   -h 16   "$SVG" -o "$MAC/icon_16x16.png"
rsvg-convert -w 32   -h 32   "$SVG" -o "$MAC/icon_16x16@2x.png"
rsvg-convert -w 32   -h 32   "$SVG" -o "$MAC/icon_32x32.png"
rsvg-convert -w 64   -h 64   "$SVG" -o "$MAC/icon_32x32@2x.png"
rsvg-convert -w 128  -h 128  "$SVG" -o "$MAC/icon_128x128.png"
rsvg-convert -w 256  -h 256  "$SVG" -o "$MAC/icon_128x128@2x.png"
rsvg-convert -w 256  -h 256  "$SVG" -o "$MAC/icon_256x256.png"
rsvg-convert -w 512  -h 512  "$SVG" -o "$MAC/icon_256x256@2x.png"
rsvg-convert -w 512  -h 512  "$SVG" -o "$MAC/icon_512x512.png"
rsvg-convert -w 1024 -h 1024 "$SVG" -o "$MAC/icon_512x512@2x.png"

# Android adaptive (foreground) + legacy launcher PNGs, per density.
ANDROID=xplatform/android/app/src/main/res
declare -a DENS=(mdpi hdpi xhdpi xxhdpi xxxhdpi)
declare -a FG=(108 162 216 324 432)
declare -a LEG=(48 72 96 144 192)
for i in 0 1 2 3 4; do
  rsvg-convert -w "${FG[$i]}"  -h "${FG[$i]}"  "$SVG_FG" -o "$ANDROID/mipmap-${DENS[$i]}/ic_launcher_foreground.png"
  rsvg-convert -w "${LEG[$i]}" -h "${LEG[$i]}" "$SVG"    -o "$ANDROID/mipmap-${DENS[$i]}/ic_launcher.png"
done

# Linux hicolor PNGs + scalable SVG.
LINUX=xplatform/linux/icons
mkdir -p "$LINUX"
for size in 16 22 24 32 48 64 96 128 192 256 512; do
  rsvg-convert -w "$size" -h "$size" "$SVG" -o "$LINUX/com.rexhep.inkandecho-${size}.png"
done
cp "$SVG" "$LINUX/com.rexhep.inkandecho.svg"

# Windows multi-size .ico (16/24/32/48/64/128/256).
python3 - <<PY
from PIL import Image
import subprocess, os
src = "icons/_ico_src.png"
subprocess.run(["rsvg-convert", "-w", "256", "-h", "256", "$SVG", "-o", src], check=True)
img = Image.open(src).convert("RGBA")
img.save(
    "xplatform/windows/runner/resources/app_icon.ico",
    format="ICO",
    sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)],
)
os.remove(src)
PY

echo "Done. Run xcodegen if project.yml changed."
