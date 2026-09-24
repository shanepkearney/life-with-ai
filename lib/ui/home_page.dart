import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/assistant_controller.dart';
import '../app/favorites.dart';
import '../app/life_controller.dart';
import '../app/screenshot/screenshot.dart';
import '../core/seed_codec.dart';
import 'about_modal.dart';
import 'assistant_panel.dart';
import 'breakpoints.dart';
import 'broken_link_dialog.dart';
import 'control_bar.dart';
import 'experiment_overlay.dart';
import 'hud.dart';
import 'life_canvas.dart';
import 'mobile_controls.dart';
import 'mobile_sheet.dart';
import 'theme.dart';
import 'toasts.dart';

/// A message shown once after launch.
class LaunchNotice {
  const LaunchNotice(this.text, {this.offerCommunity = false});

  static const sharedSeed = LaunchNotice('Loaded a shared seed. Press space to pause.');

  /// A link that meant to share a seed, but whose seed couldn't be read or
  /// loaded. With the assistant panel present it's a dialog offering the
  /// Community tab; this text is the fallback.
  static const brokenLink = LaunchNotice(
    "That seed link is broken or incomplete, so it couldn't be loaded. Find another seed in the Community tab.",
    offerCommunity: true,
  );

  final String text;

  /// Offers the Community tab (in a dialog) instead of a plain toast.
  final bool offerCommunity;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller, this.assistant, this.notice, this.favorites, this.saveScreenshot = savePng});

  final LifeController controller;
  final FavoritesStore? favorites;

  /// Shown as a side panel on desktop and a bottom sheet on phones.
  final AssistantController? assistant;
  final LaunchNotice? notice;
  final ScreenshotSaver saveScreenshot;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final _focus = FocusNode();
  final _toasts = ToastController();
  final _shot = GlobalKey();
  bool _shooting = false;
  bool _erase = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _clock.value = elapsed.inMicroseconds / 1e6;
      widget.controller.tick(_clock.value);
    })..start();
    final notice = widget.notice;
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final assistant = widget.assistant;
        if (notice.offerCommunity && assistant != null) {
          // A dialog, not a toast: it's the first thing this visitor sees, and they came for a seed.
          showBrokenLinkDialog(context, onExplore: assistant.showCommunity);
        } else {
          _toasts.show(notice.text);
        }
      });
    }
  }

  /// Hearts the board as it is right now, titled after where it came from.
  Future<void> _saveMoment() async {
    final favorites = widget.favorites!;
    void say(String text, {String? actionLabel, VoidCallback? onAction}) =>
        _toasts.show(text, actionLabel: actionLabel, onAction: onAction);

    final moment = await widget.controller.captureMoment();
    if (moment.seed.population == 0) return say('The board is empty, so there is nothing to save.');
    try {
      final added = await favorites.add(moment.seed, title: moment.title, summary: Favorite.momentSummary);
      if (!added) return say('That exact board is already in your favourites.');
      final code = SeedCodec.encode(moment.seed);
      say(
        'Saved "${moment.title}" to favourites',
        actionLabel: 'Undo',
        onAction: () => favorites.remove(favorites.items.firstWhere((f) => f.code == code)),
      );
    } on FavoriteTooLarge catch (e) {
      say(e.message);
    }
  }

  /// Saves the whole window (board, controls and panel) as a PNG, for sharing
  /// or marketing. Cropping to just the board is left to whoever uses it.
  Future<void> _saveScreenshot() async {
    if (_shooting) return;
    setState(() => _shooting = true);
    try {
      // The rebuild for _shooting leaves any toast out of the picture.
      await WidgetsBinding.instance.endOfFrame;
      final png = await capturePng(_shot);
      final saved = await widget.saveScreenshot(png, screenshotFileName(DateTime.now()));
      final file = saved?.file;
      if (saved == null) {
        _toasts.show("Screenshots can't be saved on this device yet.");
      } else if (file != null) {
        _toasts.show('Screenshot saved to ${saved.label}', actionLabel: 'Open', onAction: () => openExternal(file));
      } else {
        _toasts.show('Screenshot saved to ${saved.label}');
      }
    } catch (e) {
      _toasts.show("Couldn't save the screenshot: $e");
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  Widget _screenshotButton({double size = 18}) => IconButton(
    tooltip: 'Save a screenshot',
    visualDensity: VisualDensity.compact,
    onPressed: _shooting ? null : _saveScreenshot,
    icon: Icon(Icons.photo_camera_outlined, size: size, color: Neon.muted),
  );

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _focus.dispose();
    _toasts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Toasts(
      controller: _toasts,
      child: RepaintBoundary(
        key: _shot,
        child: Scaffold(
          body: KeyboardListener(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: (e) {
              final key = e.logicalKey;
              if (e is! KeyDownEvent && e is! KeyRepeatEvent) return;
              if (key != LogicalKeyboardKey.space && key != LogicalKeyboardKey.arrowLeft && key != LogicalKeyboardKey.arrowRight) return;
              // Key events bubble up from the chat box; a space typed there is text, not play/pause.
              final focused = FocusManager.instance.primaryFocus?.context;
              final typing =
                  focused != null && (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null);
              if (typing) return;
              // Holding an arrow repeats, scrubbing through generations; space doesn't repeat.
              if (key == LogicalKeyboardKey.space) {
                if (e is KeyDownEvent) c.toggleRunning();
              } else if (!c.running) {
                key == LogicalKeyboardKey.arrowLeft ? c.stepBack() : c.stepOnce();
              }
            },
            child: ListenableBuilder(
              listenable: c,
              // The phone layout only below the breakpoint; everything wider is the desktop layout, unchanged.
              builder: (context, _) =>
                  LayoutBuilder(builder: (context, box) => Breakpoints.isMobile(box.biggest) ? _mobile(c) : _desktop(c)),
            ),
          ),
        ),
      ),
    );
  }

  /// The desktop layout: board and controls beside the assistant panel.
  Widget _desktop(LifeController c) => Row(
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  // The logo and ⓘ open the about panel: who made this, and Conway's rules.
                  const LogoButton(),
                  _screenshotButton(),
                  const SizedBox(width: 12),
                  // Scale the stats down rather than overflow on narrow windows.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Hud(controller: c),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: _board(c)),
              const SizedBox(height: 12),
              ControlBar(
                controller: c,
                erase: _erase,
                onEraseChanged: (v) => setState(() => _erase = v),
                onSaveMoment: widget.favorites == null ? null : _saveMoment,
              ),
            ],
          ),
        ),
      ),
      if (widget.assistant != null) AssistantPanel(assistant: widget.assistant!),
    ],
  );

  /// The board with its overlays, shared by both layouts.
  Widget _board(LifeController c) => Stack(
    children: [
      Positioned.fill(
        child: LifeCanvas(controller: c, clock: _clock, erase: _erase),
      ),
      Positioned(top: 12, left: 12, child: ExperimentOverlay(controller: c)),
      // Bottom of the board area: always above the controls, however they wrap.
      if (!_shooting)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Center(child: ToastView(controller: _toasts)),
        ),
    ],
  );

  /// The phone layout: board on top, a one-row control strip, and the
  /// assistant in a bottom sheet that peeks and swipes up over the board.
  Widget _mobile(LifeController c) {
    const peek = 100.0; // handle + the panel's title bar
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 0),
                child: Row(
                  children: [
                    const LogoButton(size: 15, letterSpacing: 4),
                    _screenshotButton(size: 15),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Hud(controller: c, compact: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _board(c)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: MobileControls(
                  controller: c,
                  erase: _erase,
                  onEraseChanged: (v) => setState(() => _erase = v),
                  onSaveMoment: widget.favorites == null ? null : _saveMoment,
                ),
              ),
              // Room for the sheet's resting height, so it never hides the controls.
              SizedBox(height: widget.assistant == null ? 8 : peek + 8),
            ],
          ),
          if (widget.assistant != null)
            MobileSheet(
              peekHeight: peek,
              // Opened from a share link: show its card (on Favourites) rather than hide it in a closed sheet.
              startOpen: widget.assistant!.shared != null,
              builder: (context, expanded, open) =>
                  AssistantPanel(assistant: widget.assistant!, embedded: true, showActions: expanded, onOpen: open),
            ),
        ],
      ),
    );
  }
}
