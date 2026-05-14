import 'dart:io';

import 'package:flutter/material.dart';

import '../annotations/annotation_types.dart';
import '../main.dart' show AppThemeChoice;
import '../theme.dart';
import '../widgets/app_header.dart';
import '../widgets/app_list.dart';
import '../widgets/app_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  final AppThemeChoice currentTheme;
  final ValueChanged<AppThemeChoice> onThemeChanged;
  final bool animationsEnabled;
  final ValueChanged<bool> onAnimationsChanged;
  final HighlightColor defaultHighlightColor;
  final ValueChanged<HighlightColor> onDefaultHighlightColorChanged;
  final bool swipeToFlipEnabled;
  final ValueChanged<bool> onSwipeToFlipChanged;

  const SettingsScreen({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.animationsEnabled,
    required this.onAnimationsChanged,
    required this.defaultHighlightColor,
    required this.onDefaultHighlightColorChanged,
    required this.swipeToFlipEnabled,
    required this.onSwipeToFlipChanged,
  });

  static String _themeLabel(AppThemeChoice c) {
    switch (c) {
      case AppThemeChoice.system:
        return 'Match system';
      case AppThemeChoice.light:
        return 'Light';
      case AppThemeChoice.dark:
        return 'Dark';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return AppScaffold(
      header: AppHeader(
        title: 'Settings',
        leading: AppHeaderAction(
          icon: Icons.chevron_left,
          onTap: () => Navigator.of(context).pop(),
          tooltip: 'Back',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const AppSectionHeader('Appearance'),
          RadioGroup<AppThemeChoice>(
            groupValue: currentTheme,
            onChanged: (v) {
              if (v != null) onThemeChanged(v);
            },
            child: Column(
              children: [
                for (final choice in AppThemeChoice.values)
                  AppListTile(
                    leading: Radio<AppThemeChoice>(
                      value: choice,
                      activeColor: colors.accent,
                    ),
                    title: Text(_themeLabel(choice)),
                    onTap: () => onThemeChanged(choice),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const AppSectionHeader('Reading'),
          AppSwitchTile(
            title: const Text('Page-turn animations'),
            subtitle: const Text(
                'Curl on tap and arrow keys. Drag always shows the curl.'),
            value: animationsEnabled,
            onChanged: onAnimationsChanged,
          ),
          if (isDesktop)
            AppSwitchTile(
              title: const Text('Swipe to turn page'),
              subtitle: const Text(
                  'Off by default on desktop so text selection works. '
                  'Edge taps and arrow keys still flip the page.'),
              value: swipeToFlipEnabled,
              onChanged: onSwipeToFlipChanged,
            ),
          AppListTile(
            title: const Text('Default highlight color'),
            subtitle: Text(
              'Used when you highlight from the text-selection menu.',
              style: TextStyle(color: colors.inkMuted),
            ),
            trailing: _HighlightSwatchRow(
              selected: defaultHighlightColor,
              onChanged: onDefaultHighlightColorChanged,
              colors: colors,
            ),
          ),
          const SizedBox(height: 8),
          const AppSectionHeader('About'),
          const AppListTile(
            title: Text('Palimpsest'),
            subtitle: Text(
                'Audiobook + ebook sync reader. Cross-platform port from the Apple build.'),
          ),
        ],
      ),
    );
  }
}

class _HighlightSwatchRow extends StatelessWidget {
  final HighlightColor selected;
  final ValueChanged<HighlightColor> onChanged;
  final PalimpsestColors colors;

  const _HighlightSwatchRow({
    required this.selected,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in HighlightColor.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onChanged(c),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: c.swatch,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c == selected ? colors.ink : colors.hairline,
                    width: c == selected ? 2 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
