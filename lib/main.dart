import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app/assistant_controller.dart';
import 'app/favorites.dart';
import 'app/life_controller.dart';
import 'app/share_link.dart';
import 'engine/life_engine.dart';
import 'render/shaders.dart';
import 'ui/breakpoints.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    await bootstrap(
      launchUri: Uri.base,
      engine: const String.fromEnvironment('ENGINE') == 'cpu' ? EngineKind.cpu : EngineKind.gpu,
      // The board plays on load: a still board reads as broken, a moving one sells the glow.
      // --dart-define=NO_AUTOPLAY=true starts paused. (bootstrap() itself defaults to paused,
      // so tests stay deterministic.)
      autoplay: !const bool.fromEnvironment('NO_AUTOPLAY'),
    ),
  );
}

/// Builds the whole app. Integration tests call this directly with a fake
/// network and a chosen launch URL, so they exercise the real wiring.
Future<LifeApp> bootstrap({Uri? launchUri, http.Client? httpClient, EngineKind engine = EngineKind.gpu, bool autoplay = false}) async {
  final life = LifeController(await Shaders.load());
  // Phones start on a portrait board sized for them: at 512 cells across, a phone gets under a pixel per cell.
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view != null && Breakpoints.isMobile(view.physicalSize / view.devicePixelRatio)) life.boardSize = BoardSize.portrait;
  await life.init(engine: engine);
  final favorites = FavoritesStore();
  await favorites.load();
  final assistant = AssistantController(life, favorites, httpClient: httpClient);
  await assistant.loadSettings();

  // A share link (…/#seed=…) opens straight onto that seed, playing.
  final shared = launchUri == null ? null : ShareLink.parse(launchUri);
  if (shared != null) {
    await life.playSeed(shared.seed, title: shared.title);
    assistant.addShared(shared);
  } else if (autoplay) {
    life.toggleRunning();
  }
  return LifeApp(controller: life, assistant: assistant, notice: shared != null ? 'Loaded a shared seed. Press space to pause.' : null);
}

class LifeApp extends StatelessWidget {
  const LifeApp({super.key, required this.controller, required this.assistant, this.notice});

  final LifeController controller;
  final AssistantController assistant;

  /// Shown once after launch, e.g. when a share link was opened.
  final String? notice;

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
    builder: (_) => HomePage(controller: controller, notice: notice, favorites: assistant.favorites, assistant: assistant),
  );
}
