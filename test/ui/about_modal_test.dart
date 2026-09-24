import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/build_info.dart';
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

  testWidgets('shows which build this is beside the logo; a local build is "dev"', (tester) async {
    final opened = await open(tester);
    expect(find.text('dev'), findsOneWidget);
    await tester.tap(find.text('dev'));
    await tester.pump();
    expect(opened, isEmpty, reason: 'a local build has no release to link to');
  });

  group('BuildInfo', () {
    test('labels a release with its version and short commit', () {
      expect(BuildInfo.labelFor('1.2.0', 'a1b2c3d4e5f6'), 'v1.2.0 · a1b2c3d');
      expect(BuildInfo.labelFor('1.2.0', ''), 'v1.2.0');
      expect(BuildInfo.labelFor('', 'a1b2c3d'), 'dev');
    });

    test('links a release to its GitHub Release page', () {
      expect(BuildInfo.releaseUrlFor('1.2.0').toString(), 'https://github.com/shanepkearney/life-with-ai/releases/tag/v1.2.0');
      expect(BuildInfo.releaseUrlFor(''), isNull);
    });
  });

  testWidgets('says what it is for, credits the author and Conway, with the rules', (tester) async {
    await open(tester);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.textContaining('makes those experiments easy to share'), findsOneWidget);
    expect(find.textContaining('Every seed becomes a link'), findsOneWidget);
    expect(find.textContaining('lets AI take a turn at the seeds'), findsOneWidget);
    expect(find.textContaining('Claude designs a starting pattern'), findsOneWidget);
    expect(find.textContaining('Created By Shane Kearney', findRichText: true), findsOneWidget);
    expect(find.textContaining('co-author'), findsNothing, reason: 'sole credit in the app');
    expect(find.textContaining('John Horton Conway in 1970'), findsOneWidget);
    expect(find.textContaining('B3/S23'), findsOneWidget);
    for (final lesson in ['Simple rules, complex worlds.', 'Beginnings matter.', 'Chaos settles into order.']) {
      expect(find.textContaining(lesson, findRichText: true), findsOneWidget, reason: lesson);
    }
  });

  testWidgets('the byline comes first, then About, Conway, Key lessons and Origins', (tester) async {
    await open(tester);
    expect(find.text('CREATED BY'), findsNothing, reason: 'a byline, not a section');
    final byline = tester.getTopLeft(find.textContaining('Created By Shane Kearney', findRichText: true)).dy;
    final tops = [
      byline,
      for (final h in ['ABOUT', "CONWAY'S GAME OF LIFE", 'KEY LESSONS TO TAKE FROM IT', 'ORIGINS']) tester.getTopLeft(find.text(h)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
  });

  testWidgets('links go to the right places', (tester) async {
    final opened = await open(tester);
    for (final label in ['Wikipedia', 'LifeWiki', 'The original', 'GitHub', 'LinkedIn']) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
    }
    expect(opened, [
      About.wikipedia,
      About.lifeWiki,
      About.original,
      About.authorGitHub,
      Uri.parse('https://www.linkedin.com/in/shanepkearney/'),
    ]);
    // The source is reached from the version tag's release page instead.
    expect(find.text('Source code'), findsNothing);
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
