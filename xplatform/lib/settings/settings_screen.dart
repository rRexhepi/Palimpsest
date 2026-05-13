import 'package:flutter/material.dart';

import '../main.dart' show AppThemeChoice;
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  final AppThemeChoice currentTheme;
  final ValueChanged<AppThemeChoice> onThemeChanged;
  final bool animationsEnabled;
  final ValueChanged<bool> onAnimationsChanged;

  const SettingsScreen({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
    required this.animationsEnabled,
    required this.onAnimationsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _SectionHeader('Appearance', colors: colors),
          RadioGroup<AppThemeChoice>(
            groupValue: currentTheme,
            onChanged: (v) {
              if (v != null) onThemeChanged(v);
            },
            child: Column(
              children: [
                for (final choice in AppThemeChoice.values)
                  ListTile(
                    leading: Radio<AppThemeChoice>(
                      value: choice,
                      activeColor: colors.accent,
                    ),
                    title: Text(_themeLabel(choice),
                        style: TextStyle(color: colors.ink)),
                    onTap: () => onThemeChanged(choice),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _SectionHeader('Reading', colors: colors),
          SwitchListTile(
            title: Text('Page-turn animations',
                style: TextStyle(color: colors.ink)),
            subtitle: Text(
              'Curl on tap and arrow keys. Drag always shows the curl.',
              style: TextStyle(color: colors.inkMuted),
            ),
            value: animationsEnabled,
            activeThumbColor: colors.accent,
            onChanged: onAnimationsChanged,
          ),
          const SizedBox(height: 8),
          _SectionHeader('About', colors: colors),
          ListTile(
            title: Text('Palimpsest', style: TextStyle(color: colors.ink)),
            subtitle: Text(
              'Audiobook + ebook sync reader. Cross-platform port from the Apple build.',
              style: TextStyle(color: colors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

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
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final PalimpsestColors colors;
  const _SectionHeader(this.label, {required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: colors.inkMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
