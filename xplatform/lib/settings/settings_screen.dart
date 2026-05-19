import 'dart:io';

import 'package:flutter/material.dart';

import '../annotations/annotation_types.dart';
import '../main.dart' show AppThemeChoice;
import '../theme.dart';
import '../whisper/whisper_config.dart';
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
  final TranscriptionPerformance transcriptionPerformance;
  final ValueChanged<TranscriptionPerformance>
      onTranscriptionPerformanceChanged;

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
    required this.transcriptionPerformance,
    required this.onTranscriptionPerformanceChanged,
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

  static String _perfLabel(TranscriptionPerformance p) {
    switch (p) {
      case TranscriptionPerformance.max:
        return 'Max';
      case TranscriptionPerformance.balanced:
        return 'Balanced';
      case TranscriptionPerformance.light:
        return 'Light';
    }
  }

  static String _deviceSummary() {
    final cores = Platform.numberOfProcessors;
    final ram = WhisperConfig.totalRamMb;
    if (ram == null) return 'Detected: $cores cores.';
    final gb = (ram / 1024).toStringAsFixed(ram >= 4000 ? 0 : 1);
    return 'Detected: $cores cores, $gb GB RAM.';
  }

  static String _perfSubtitle(TranscriptionPerformance p) {
    final cfg = WhisperConfig.forLevel(p);
    final totalThreads = cfg.workerCount * cfg.threadsPerWorker;
    final ramMb = cfg.workerCount * 270;
    switch (p) {
      case TranscriptionPerformance.max:
        return 'Fastest. ${cfg.workerCount} workers × '
            '${cfg.threadsPerWorker} threads (~$ramMb MB RAM).';
      case TranscriptionPerformance.balanced:
        return 'Default. $totalThreads threads, single worker '
            '(~$ramMb MB RAM). Phone stays responsive.';
      case TranscriptionPerformance.light:
        return 'Smallest footprint. 2 threads. Pick when running other '
            'apps in the foreground.';
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
          const AppSectionHeader('Transcription'),
          AppListTile(
            title: const Text('Performance'),
            subtitle: Text(
              '${_deviceSummary()} '
              'Audiobook transcription uses Whisper on the CPU. Higher '
              'levels run more threads in parallel — faster, but the '
              'device runs hotter and other apps slow down.',
              style: TextStyle(color: colors.inkMuted),
            ),
          ),
          RadioGroup<TranscriptionPerformance>(
            groupValue: transcriptionPerformance,
            onChanged: (v) {
              if (v != null) onTranscriptionPerformanceChanged(v);
            },
            child: Column(
              children: [
                for (final p in TranscriptionPerformance.values)
                  AppListTile(
                    leading: Radio<TranscriptionPerformance>(
                      value: p,
                      activeColor: colors.accent,
                    ),
                    title: Text(_perfLabel(p)),
                    subtitle: Text(
                      _perfSubtitle(p),
                      style: TextStyle(color: colors.inkMuted),
                    ),
                    onTap: () => onTranscriptionPerformanceChanged(p),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const AppSectionHeader('About'),
          const AppListTile(
            title: Text('Ink and Echo'),
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
  final InkAndEchoColors colors;

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
