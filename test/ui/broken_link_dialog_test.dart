import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/ui/broken_link_dialog.dart';
import 'package:life_with_ai/ui/theme.dart';

void main() {
  Future<void> open(WidgetTester tester, VoidCallback onExplore) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: Neon.theme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showBrokenLinkDialog(context, onExplore: onExplore), child: const Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The loader animates forever, so pumpAndSettle would never return.
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('explains the broken link and offers both ways on', (tester) async {
    await open(tester, () {});
    expect(find.text("This seed didn't make it"), findsOneWidget);
    expect(find.textContaining('broken or incomplete'), findsOneWidget);
    expect(find.text('Just play'), findsOneWidget);
    expect(find.text('Explore community seeds'), findsOneWidget);
  });

  testWidgets('"Just play" closes it without going anywhere', (tester) async {
    var explored = 0;
    await open(tester, () => explored++);
    await tester.tap(find.text('Just play'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("This seed didn't make it"), findsNothing);
    expect(explored, 0);
  });

  testWidgets('"Explore community seeds" closes it and goes to the Community tab', (tester) async {
    var explored = 0;
    await open(tester, () => explored++);
    await tester.tap(find.text('Explore community seeds'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("This seed didn't make it"), findsNothing);
    expect(explored, 1);
  });

  testWidgets('a tap outside closes it too', (tester) async {
    var explored = 0;
    await open(tester, () => explored++);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("This seed didn't make it"), findsNothing);
    expect(explored, 0);
  });
}
