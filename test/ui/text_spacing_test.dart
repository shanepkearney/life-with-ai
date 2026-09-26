import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/assistant_controller.dart';
import 'package:life_with_ai/app/favorites.dart';
import 'package:life_with_ai/app/life_controller.dart';
import 'package:life_with_ai/main.dart';
import 'package:life_with_ai/render/shaders.dart';
import 'package:life_with_ai/ui/text_spacing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('saneTextSpacing', () {
    test("drops what Android's text zoom makes of Flutter web's 9999px sentinel", () {
      // Measured in Android's WebView at a 115% font size: 11498.9px of line height on 18.4px text.
      const zoomed = MediaQueryData(
        size: Size(411, 841),
        textScaler: TextScaler.linear(1.15),
        lineHeightScaleFactorOverride: 11498.9 / 18.4,
        letterSpacingOverride: 11498.9,
        wordSpacingOverride: 11498.9,
        paragraphSpacingOverride: 11498.9,
      );
      final d = saneTextSpacing(zoomed);
      expect(d.lineHeightScaleFactorOverride, isNull);
      expect(d.letterSpacingOverride, isNull);
      expect(d.wordSpacingOverride, isNull);
      expect(d.paragraphSpacingOverride, isNull);
      expect(d.textScaler, const TextScaler.linear(1.15), reason: 'the font size is real, and kept');
      expect(d.size, const Size(411, 841));
    });

    test("keeps a reader's real text-spacing settings, and leaves plain data alone", () {
      const wcag = MediaQueryData(
        lineHeightScaleFactorOverride: 1.5,
        letterSpacingOverride: 2,
        wordSpacingOverride: 3,
        paragraphSpacingOverride: 32,
      );
      expect(saneTextSpacing(wcag), same(wcag));
      const plain = MediaQueryData();
      expect(saneTextSpacing(plain), same(plain));
    });
  });

  testWidgets('the app shows its text under a zoomed sentinel', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2209);
    tester.view.devicePixelRatio = 2.625;
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    tester.platformDispatcher.lineHeightScaleFactorOverrideTestValue = 11498.9 / 18.4;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    late LifeController life;
    late AssistantController assistant;
    await tester.runAsync(() async {
      life = LifeController(await Shaders.load());
      await life.init();
      assistant = AssistantController(life, FavoritesStore());
      await assistant.loadSettings();
    });
    await tester.pumpWidget(LifeApp(controller: life, assistant: assistant));
    await tester.pump();

    final context = tester.element(find.text('Assistant'));
    expect(MediaQuery.of(context).lineHeightScaleFactorOverride, isNull);
    expect(MediaQuery.textScalerOf(context).scale(10), closeTo(11.5, 1e-9), reason: "the reader's font size stays");
    expect(tester.getSize(find.text('Assistant')).height, lessThan(60), reason: 'a line of text, not 600 of them');

    await tester.pumpWidget(const SizedBox());
    life.dispose();
  });
}
