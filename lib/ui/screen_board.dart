import 'package:flutter/widgets.dart';

import '../app/life_controller.dart';

/// A board shaped like the screen this window is on (the whole display, not
/// the window), for Board only to fill edge to edge.
BoardSize screenBoardFor(BuildContext context) {
  final display = View.of(context).display;
  final logical = display.size / display.devicePixelRatio;
  return BoardSize.fitScreen(logical.width, logical.height);
}

/// The board sizes a size menu offers: the layout's presets, Fit screen, and
/// whatever size is on the board now (a shared seed's, say).
List<BoardSize> boardSizeChoices(BuildContext context, BoardSize current, {required bool phone}) =>
    {...(phone ? BoardSize.mobile : BoardSize.desktop), screenBoardFor(context), current}.toList();
