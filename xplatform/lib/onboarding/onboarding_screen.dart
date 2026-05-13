import 'package:flutter/material.dart';

import '../theme.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = <_Slide>[
    _Slide(
      kicker: 'Welcome',
      title: 'Palimpsest',
      body: 'An ebook + audiobook reader that keeps the page and the voice in sync.',
      icon: Icons.menu_book_outlined,
    ),
    _Slide(
      kicker: 'How it works',
      title: 'Three steps',
      body: 'Import an EPUB. Attach an audiobook. Run alignment once and the reader marries page to narration.',
      icon: Icons.auto_awesome,
    ),
    _Slide(
      kicker: 'Local first',
      title: 'Your library stays on this device',
      body: 'Audio, text, and Whisper transcription all run on-device. Nothing leaves the phone unless you share it.',
      icon: Icons.shield_outlined,
    ),
    _Slide(
      kicker: "You're set",
      title: 'Begin reading',
      body: 'Tap Start to open your library and import your first book.',
      icon: Icons.east,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _SlideView(
                  slide: _slides[i],
                  colors: colors,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index ? colors.accent : colors.hairlineStrong,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: SizedBox(
                width: double.infinity,
                child: Material(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      if (_index < _slides.length - 1) {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOut,
                        );
                      } else {
                        widget.onDone();
                      }
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text(
                          _index < _slides.length - 1 ? 'Continue' : 'Start',
                          style: TextStyle(
                            color: colors.onAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: widget.onDone,
              child: Text('Skip',
                  style: TextStyle(color: colors.inkMuted)),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final String kicker;
  final String title;
  final String body;
  final IconData icon;
  const _Slide({
    required this.kicker,
    required this.title,
    required this.body,
    required this.icon,
  });
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  final PalimpsestColors colors;
  const _SlideView({required this.slide, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: colors.canvasCool,
              shape: BoxShape.circle,
              border: Border.all(color: colors.hairline),
            ),
            child: Icon(slide.icon, size: 44, color: colors.accent),
          ),
          const SizedBox(height: 32),
          Text(
            slide.kicker.toUpperCase(),
            style: TextStyle(
              color: colors.inkMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.ink,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.inkMuted,
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
