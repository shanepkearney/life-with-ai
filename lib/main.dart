import 'package:flutter/material.dart';

import 'app/life_controller.dart';
import 'engine/life_engine.dart';
import 'render/shaders.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = LifeController(await Shaders.load());
  await controller.init(engine: const String.fromEnvironment('ENGINE') == 'cpu' ? EngineKind.cpu : EngineKind.gpu);
  // Dev/demo convenience: --dart-define=AUTOPLAY=true starts the simulation running.
  if (const bool.fromEnvironment('AUTOPLAY')) controller.toggleRunning();
  runApp(LifeApp(controller: controller));
}

class LifeApp extends StatelessWidget {
  const LifeApp({super.key, required this.controller});

  final LifeController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Life with AI',
        debugShowCheckedModeBanner: false,
        theme: Neon.theme(),
        home: HomePage(controller: controller),
      );
}
