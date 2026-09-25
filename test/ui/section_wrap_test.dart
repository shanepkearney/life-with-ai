import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/ui/section_wrap.dart';

void main() {
  Future<RenderSectionWrap> lay(WidgetTester tester, double width, List<double> sections) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Align(
              alignment: Alignment.topLeft,
              child: SectionWrap(dividerColor: Colors.white, children: [for (final w in sections) SizedBox(width: w, height: 40)]),
            ),
          ),
        ),
      ),
    );
    return tester.renderObject<RenderSectionWrap>(find.byType(SectionWrap));
  }

  testWidgets('everything on one line when it fits, a divider between each section', (tester) async {
    final r = await lay(tester, 1000, [100, 100, 100]);
    expect((r.lineCount, r.dividerCount), (1, 2));
    expect(r.size.width, 100 * 3 + 21 * 2, reason: 'as wide as the sections need, not the space offered');
  });

  testWidgets('it breaks between whole sections, with no divider at the end of a line', (tester) async {
    // 100 + 21 + 100 fits in 250; the third section doesn't, so it starts the next line.
    final r = await lay(tester, 250, [100, 100, 100]);
    expect(r.lineCount, 2);
    expect(r.dividerCount, 1, reason: 'only between the two sections sharing the first line');
    final third = tester.getTopLeft(find.byType(SizedBox).last);
    expect(third.dx, 0, reason: 'the next line starts at the left, with nothing before it');
  });

  testWidgets('one section to a line: no dividers at all', (tester) async {
    final r = await lay(tester, 120, [100, 100, 100]);
    expect((r.lineCount, r.dividerCount), (3, 0));
  });
}
