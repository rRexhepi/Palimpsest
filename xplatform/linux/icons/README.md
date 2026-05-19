# Linux icons

Hicolor-theme PNGs plus a scalable SVG and a `.desktop` entry. Drop them in during packaging so the Linux launcher picks up the Ink and Echo mark.

```
install -Dm644 com.rexhep.inkandecho.svg \
  $DESTDIR/usr/share/icons/hicolor/scalable/apps/com.rexhep.inkandecho.svg
for size in 16 22 24 32 48 64 96 128 192 256 512; do
  install -Dm644 com.rexhep.inkandecho-${size}.png \
    $DESTDIR/usr/share/icons/hicolor/${size}x${size}/apps/com.rexhep.inkandecho.png
done
install -Dm644 com.rexhep.inkandecho.desktop \
  $DESTDIR/usr/share/applications/com.rexhep.inkandecho.desktop
```

The runner (`linux/runner/my_application.cc`) calls `gtk_window_set_icon_name(window, "com.rexhep.inkandecho")` so the icon-name has to match what's installed under hicolor.
