import 'package:flutter/material.dart';

import 'app/assistant_controller.dart';
import 'app/life_controller.dart';
import 'engine/life_engine.dart';
import 'render/shaders.dart';
import 'ui/assistant_panel.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = LifeController(await Shaders.load());
  await controller.init(engine: const String.fromEnvironment('ENGINE') == 'cpu' ? EngineKind.cpu : EngineKind.gpu);
  // Dev/demo convenience: --dart-define=AUTOPLAY=true starts the simulation running.
  if (const bool.fromEnvironment('AUTOPLAY')) controller.toggleRunning();
  final assistant = AssistantController(controller);
  await assistant.loadSettings();
  runApp(LifeApp(controller: controller, assistant: assistant));
}

class LifeApp extends StatelessWidget {
  const LifeApp({super.key, required this.controller, required this.assistant});

  final LifeController controller;
  final AssistantController assistant;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Life with AI',
        debugShowCheckedModeBanner: false,
        theme: Neon.theme(),
        home: HomePage(controller: controller, sidePanel: AssistantPanel(assistant: assistant)),
      );
}
