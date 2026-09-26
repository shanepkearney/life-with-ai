import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app/assistant_controller.dart';
import 'app/favorites.dart';
import 'app/life_controller.dart';
import 'app/palette_store.dart';
import 'app/platform/error_report.dart';
import 'app/platform/full_screen.dart';
import 'app/share_link.dart';
import 'app/telemetry.dart';
import 'engine/life_engine.dart';
import 'render/shaders.dart';
import 'ui/breakpoints.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On the web, errors reach the page (web/index.html): a framework error (building, laying out,
  // drawing) shows its friendly notice, since the screen is likely broken; any other is only
  // counted. Both are still printed as usual.
  final present = FlutterError.onError;
  FlutterError.onError = (details) {
    present?.call(details);
    reportAppError('flutter', details.exceptionAsString(), visible: true);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reportAppError('flutter', '$error', visible: false);
    return false; // not handled: the default reporting still happens
  };
  final LifeApp app;
  try {
    app = await bootstrap(
      launchUri: Uri.base,
      engine: EngineKind.values.asNameMap()[const String.fromEnvironment('ENGINE')] ?? EngineKind.gpu,
      // The board plays on load: a still board reads as broken, a moving one sells the glow.
      // --dart-define=NO_AUTOPLAY=true starts paused. (bootstrap() itself defaults to paused,
      // so tests stay deterministic.)
      autoplay: !const bool.fromEnvironment('NO_AUTOPLAY'),
    );
  } catch (e) {
    // It never starts (shaders that won't load, say): say so now, not after the page's 25-second wait.
    reportAppError('load', '$e', visible: true);
    rethrow;
  }
  runApp(app);
}

/// Builds the whole app. Integration tests call this directly with a fake
/// network and a chosen launch URL, so they exercise the real wiring.
Future<LifeApp> bootstrap({
  Uri? launchUri,
  http.Client? httpClient,
  EngineKind engine = EngineKind.gpu,
  bool autoplay = false,
  bool? offerMacDownload,
  FullScreen? fullScreen,
}) async {
  final life = LifeController(await Shaders.load());
  // Released builds count which seeds get opened (see lib/app/telemetry.dart); local builds don't.
  final telemetry = Telemetry.fromEnvironment(client: httpClient);
  life.onSeedOpened = telemetry.seedOpened;
  // Phones start on a portrait board sized for them: at 512 cells across, a phone gets under a pixel per cell.
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view != null && Breakpoints.isMobile(view.physicalSize / view.devicePixelRatio)) life.boardSize = BoardSize.portrait;
  await life.init(engine: engine);
  life.choosePalette(await PaletteStore.load());
  life.onPaletteChosen = PaletteStore.save;
  final favorites = FavoritesStore();
  await favorites.load();
  final assistant = AssistantController(life, favorites, httpClient: httpClient);
  await assistant.loadSettings();

  // A share link (…/#seed=…) opens straight onto that seed, playing. One that
  // can't be read, or fails to load, falls back to a normal start and says so,
  // pointing to the Community tab instead.
  LaunchNotice? notice;
  if (launchUri != null && ShareLink.carriesSeed(launchUri)) {
    notice = LaunchNotice.brokenLink;
    final shared = ShareLink.parse(launchUri);
    if (shared != null) {
      try {
        await life.playSeed(shared.seed, title: shared.title, source: SeedSource.shareLink, rule: shared.rule);
        assistant.addShared(shared);
        // The sender's colors, for this visit: the Shared with you card offers to keep them.
        final colors = shared.palette;
        if (colors != null && colors != life.ownPalette) life.showSharedPalette(colors, seed: shared.seed);
        notice = LaunchNotice.sharedSeed;
      } catch (e) {
        debugPrint('Could not load the shared seed: $e');
        if (life.running) life.toggleRunning();
        await life.randomize();
      }
    }
  }
  if (autoplay && !life.running) life.toggleRunning();
  return LifeApp(controller: life, assistant: assistant, notice: notice, offerMacDownload: offerMacDownload, fullScreen: fullScreen);
}

class LifeApp extends StatelessWidget {
  const LifeApp({super.key, required this.controller, required this.assistant, this.notice, this.offerMacDownload, this.fullScreen});

  final LifeController controller;
  final AssistantController assistant;

  /// Shown once after launch, e.g. when a share link was opened.
  final LaunchNotice? notice;

  /// Overrides where the ⬇ for the macOS app shows (by default: web, on a Mac).
  final bool? offerMacDownload;

  /// Full screen for this platform, unless a test passes its own.
  final FullScreen? fullScreen;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Life with AI',
    debugShowCheckedModeBanner: false,
    theme: Neon.theme(),
    // There is one screen. The web URL's fragment holds share-link data
    // (#seed=…), not a route, so every route name, including the initial
    // one the web engine derives from the URL, resolves to it. (A route
    // generator is also what makes MaterialApp create a Navigator at all.)
    onGenerateInitialRoutes: (_) => [_home()],
    onGenerateRoute: (_) => _home(),
  );

  Route<void> _home() => MaterialPageRoute<void>(
    builder: (_) => HomePage(
      controller: controller,
      notice: notice,
      favorites: assistant.favorites,
      assistant: assistant,
      offerMacDownload: offerMacDownload,
      fullScreen: fullScreen,
    ),
  );
}
