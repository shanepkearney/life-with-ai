import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/ui/about_modal.dart';
import 'package:life_with_ai/ui/theme.dart';

/// The about panel credits the author and Conway, links to the right places,
/// and closes every usual way.
void main() {
  Future<List<Uri>> open(WidgetTester tester, {Size size = const Size(1440, 920)}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: Neon.theme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAboutModal(context, openUrl: (u) async => opened.add(u)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('says what it is for, credits the author and Conway, with the rules', (tester) async {
    await open(tester);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.textContaining('improve an earlier Java version'), findsOneWidget);
    expect(find.textContaining('accessible, sharable and open to AI'), findsOneWidget);
    expect(find.textContaining('bring it and experiment'), findsOneWidget);
    expect(find.text('Shane Kearney'), findsOneWidget);
    expect(find.textContaining('co-author'), findsNothing, reason: 'sole credit in the app');
    expect(find.textContaining('John Horton Conway in 1970'), findsOneWidget);
    expect(find.textContaining('B3/S23'), findsOneWidget);
  });

  testWidgets('sections run About, Conway, Origins, then Created by last', (tester) async {
    await open(tester);
    final tops = [for (final h in ['ABOUT', "CONWAY'S GAME OF LIFE", 'ORIGINS', 'CREATED BY']) tester.getTopLeft(find.text(h)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
  });

  testWidgets('links go to the right places', (tester) async {
    final opened = await open(tester);
    for (final label in ['Wikipedia', 'LifeWiki', 'The original', 'GitHub', 'LinkedIn', 'Source code']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
    }
    expect(opened, [
      About.wikipedia,
      About.lifeWiki,
      About.original,
      About.authorGitHub,
      Uri.parse('https://www.linkedin.com/in/shanepkearney/'),
      About.repo,
    ]);
  });

  testWidgets('closes with the ✕, Esc, and a tap outside', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.textContaining('B3/S23'), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('B3/S23'), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.textContaining('B3/S23'), findsNothing);
  });

  testWidgets('fits a small phone without overflowing (it scrolls if needed)', (tester) async {
    await open(tester, size: const Size(375, 667));
    expect(find.textContaining('B3/S23'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
