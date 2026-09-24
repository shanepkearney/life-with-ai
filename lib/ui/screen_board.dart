import 'package:flutter/widgets.dart';

import '../app/life_controller.dart';

/// A board shaped like the screen this window is on (the whole display, not
/// the window), for Board only to fill edge to edge.
BoardSize screenBoardFor(BuildContext context) {
  final display = View.of(context).display;
  final logical = display.size / display.devicePixelRatio;
  return BoardSize.fitScreen(logical.width, logical.height);
}
