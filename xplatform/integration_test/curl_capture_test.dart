// Renders CurlPageView with mock pages and dumps PNGs at scripted
// progress values along a forward drag. Lets Claude open the PNGs to
// see what the curl actually looks like at each phase without needing
// OS-level screenshot access.
//
// Run from xplatform/:
//   flutter test integration_test/curl_capture_test.dart -d linux
//
// PNGs land in /tmp/curl-frames/forward-NN.png (and backward-NN.png).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ink_and_echo/reader/curl_page_view.dart';

const _outDir = '/tmp/curl-frames';

/// Sample positions along a drag. Spread out so we get to see the curl at
/// every stage: just-started, quarter, third, half, two-thirds, three-
/// quarters, near-complete.
const _progressValues = <double>[
  0.05,
  0.15,
  0.25,
  0.40,
  0.50,
  0.60,
  0.75,
  0.90,
  1.00,
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Directory(_outDir).createSync(recursive: true);
  });

  testWidgets('forward curl frames in spread mode', (tester) async {
    await _captureCurl(tester, spread: true, forward: true);
  });

  testWidgets('backward curl frames in spread mode', (tester) async {
    await _captureCurl(tester, spread: true, forward: false);
  });

  testWidgets('forward curl frames in single mode', (tester) async {
    await _captureCurl(tester, spread: false, forward: true);
  });
}

Future<void> _captureCurl(
  WidgetTester tester, {
  required bool spread,
  required bool forward,
}) async {
  final controller = CurlPageController(initialPage: forward ? 0 : 2);
  final captureKey = GlobalKey();

  await tester.pumpWidget(_CurlHarness(
    controller: controller,
    captureKey: captureKey,
    spread: spread,
  ));
  // Settle layout + shader load.
  await tester.pumpAndSettle();

  // Find the page view's local coordinates so we can synthesize drags
  // anchored to its center vertically.
  final pageViewFinder = find.byType(CurlPageView);
  final rect = tester.getRect(pageViewFinder);
  final centerY = rect.center.dy;

  // Synthesize a drag in stages, pausing at each progress value to dump
  // a frame. Forward drag: finger goes from right edge inward; backward:
  // from left edge inward.
  final start = Offset(
    forward ? rect.right - 4 : rect.left + 4,
    centerY,
  );
  final end = Offset(
    forward ? rect.left + 4 : rect.right - 4,
    centerY,
  );
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 16));

  for (var i = 0; i < _progressValues.length; i++) {
    final p = _progressValues[i];
    final target = Offset.lerp(start, end, p)!;
    await gesture.moveTo(target);
    // Three frame pumps to let any pending state-changes and snapshot
    // capture flush before we take the picture.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    final tag = '${spread ? 'spread' : 'single'}-'
        '${forward ? 'fwd' : 'bwd'}-${i.toString().padLeft(2, '0')}-p${(p * 100).toInt().toString().padLeft(3, '0')}';
    await _dumpBoundary(tester, captureKey, '$_outDir/$tag.png');
    // Also dump a tiny ASCII signal so the test log shows progress.
    debugPrint('captured $tag');
  }

  // Release the gesture without committing (still dump the final frame
  // before letting the spring-back run — at this point we've already
  // captured the 100 % frame above).
  await gesture.up();
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Future<void> _dumpBoundary(
    WidgetTester tester, GlobalKey key, String path) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.5);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) {
    throw StateError('toByteData returned null for $path');
  }
  File(path).writeAsBytesSync(bytes.buffer.asUint8List());
  image.dispose();
}

class _CurlHarness extends StatelessWidget {
  const _CurlHarness({
    required this.controller,
    required this.captureKey,
    required this.spread,
  });

  final CurlPageController controller;
  final GlobalKey captureKey;
  final bool spread;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFE9E2D2),
        body: SafeArea(
          child: SizedBox(
            // Fixed size so the captures are comparable run-to-run. Spread
            // gets a wider canvas so the half-page layout makes sense.
            width: spread ? 1280 : 640,
            height: 800,
            child: RepaintBoundary(
              key: captureKey,
              child: CurlPageView(
                controller: controller,
                pageCount: 8,
                spread: spread,
                spreadGutter: Container(color: const Color(0xFFB7AD96)),
                pageBuilder: (_, idx) => _MockPage(index: idx),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MockPage extends StatelessWidget {
  const _MockPage({required this.index});
  final int index;

  static const _palette = <Color>[
    Color(0xFFF4EFE6), // parchment
    Color(0xFFEDE2C8),
    Color(0xFFE3D5B6),
    Color(0xFFD6C29C),
    Color(0xFFC9AE82),
    Color(0xFFBC9A68),
    Color(0xFFAF864E),
    Color(0xFFA27234),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _palette[index % _palette.length],
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Page ${index + 1}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: Color(0xFF3A2F22),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Text(
              List.generate(
                40,
                (i) => 'Lorem ipsum dolor sit amet, consectetur '
                    'adipiscing elit. Sed do eiusmod tempor incididunt '
                    'ut labore et dolore magna aliqua. (${index + 1}.$i)',
              ).join('\n\n'),
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF2A2218),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
