import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ink_and_echo/main.dart';

void main() {
  testWidgets('app boots without throwing', (tester) async {
    await tester.pumpWidget(const InkAndEchoApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
