import 'package:flutter/material.dart';

/// Color tokens ported from App/Theme.swift on the Apple build. Hex values
/// are the brand. Saddle accent (#8B5A2B light / #C99A6A dark), parchment
/// canvas (#F4EFE6 light / #1B1815 dark). Adaptive light + dark pairs for
/// every token.
class InkAndEchoColors {
  final Color canvas;
  final Color canvasCool;
  final Color canvasDeep;
  final Color ink;
  final Color inkSoft;
  final Color inkMuted;
  final Color hairline;
  final Color hairlineStrong;
  final Color accent;
  final Color accentDeep;
  final Color onAccent;

  const InkAndEchoColors({
    required this.canvas,
    required this.canvasCool,
    required this.canvasDeep,
    required this.ink,
    required this.inkSoft,
    required this.inkMuted,
    required this.hairline,
    required this.hairlineStrong,
    required this.accent,
    required this.accentDeep,
    required this.onAccent,
  });

  static const light = InkAndEchoColors(
    canvas: Color.fromARGB(255, 244, 239, 230),
    canvasCool: Color.fromARGB(255, 237, 232, 221),
    canvasDeep: Color.fromARGB(255, 226, 219, 203),
    ink: Color.fromARGB(255, 31, 26, 20),
    inkSoft: Color.fromARGB(255, 61, 53, 42),
    inkMuted: Color.fromARGB(255, 107, 98, 83),
    hairline: Color.fromARGB(255, 217, 208, 189),
    hairlineStrong: Color.fromARGB(255, 191, 179, 154),
    accent: Color.fromARGB(255, 139, 90, 43),
    accentDeep: Color.fromARGB(255, 110, 69, 32),
    onAccent: Color.fromARGB(255, 251, 247, 238),
  );

  static const dark = InkAndEchoColors(
    canvas: Color.fromARGB(255, 27, 24, 21),
    canvasCool: Color.fromARGB(255, 21, 18, 15),
    canvasDeep: Color.fromARGB(255, 14, 12, 10),
    ink: Color.fromARGB(255, 233, 226, 212),
    inkSoft: Color.fromARGB(255, 198, 190, 174),
    inkMuted: Color.fromARGB(255, 140, 133, 121),
    hairline: Color.fromARGB(255, 58, 51, 43),
    hairlineStrong: Color.fromARGB(255, 75, 68, 58),
    accent: Color.fromARGB(255, 201, 154, 106),
    accentDeep: Color.fromARGB(255, 164, 124, 80),
    onAccent: Color.fromARGB(255, 27, 24, 21),
  );
}

extension InkAndEchoThemeExt on BuildContext {
  InkAndEchoColors get colors {
    final brightness = Theme.of(this).brightness;
    return brightness == Brightness.dark
        ? InkAndEchoColors.dark
        : InkAndEchoColors.light;
  }
}

/// Body type prefers Charter / Iowan Old Style / Georgia (the same fall-back
/// chain the design handoff calls for on non-Apple platforms). On Android
/// none of those ship by default, so we land on the system serif.
const _bodySerifFallback = ['Charter', 'Iowan Old Style', 'Georgia', 'serif'];

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? InkAndEchoColors.dark
      : InkAndEchoColors.light;
  final base = brightness == Brightness.dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    colorScheme: base.colorScheme.copyWith(
      primary: c.accent,
      onPrimary: c.onAccent,
      surface: c.canvas,
      onSurface: c.ink,
      surfaceTint: c.canvas,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      foregroundColor: c.ink,
      elevation: 0,
      surfaceTintColor: c.canvas,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: c.ink,
        fontFamilyFallback: _bodySerifFallback,
        fontSize: 17,
        fontWeight: FontWeight.w500,
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: c.ink,
      displayColor: c.ink,
      fontFamilyFallback: _bodySerifFallback,
    ),
    dividerColor: c.hairline,
    iconTheme: IconThemeData(color: c.inkSoft),
  );
}
