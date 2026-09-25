import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/assistant_controller.dart';
import '../app/favorites.dart';
import '../app/life_controller.dart';
import '../app/platform/browser.dart';
import '../app/platform/full_screen.dart';
import '../app/screenshot/screenshot.dart';
import '../core/seed_codec.dart';
import 'about_modal.dart';
import 'assistant_panel.dart';
import 'board_only.dart';
import 'breakpoints.dart';
import 'broken_link_dialog.dart';
import 'control_bar.dart';
import 'download_dialog.dart';
import 'experiment_overlay.dart';
import 'hud.dart';
import 'life_canvas.dart';
import 'mobile_controls.dart';
import 'mobile_sheet.dart';
import 'rle_dialog.dart';
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
  const HomePage({super.key, required this.controller, this.assistant, this.notice, this.favorites, this.saveScreenshot = savePng, this.offerMacDownload, this.fullScreen});

  final LifeController controller;
  final FavoritesStore? favorites;

  /// Shown as a side panel on desktop and a bottom sheet on phones.
  final AssistantController? assistant;
  final LaunchNotice? notice;
  final ScreenshotSaver saveScreenshot;

  /// Shows the ⬇ button for the macOS app. By default, only on the web on a Mac.
  final bool? offerMacDownload;

  /// Full screen for this platform; tests pass their own.
  final FullScreen? fullScreen;

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

  late final FullScreen _fullScreen = widget.fullScreen ?? FullScreen.platform();

  /// Just the board, edge to edge (see [BoardOnlyView]).
  bool _boardOnly = false;

  /// Board only went full screen by itself, so leaving one leaves the other.
  bool _boardOnlyFullScreen = false;

  @override
  void initState() {
    super.initState();
    _fullScreen.active.addListener(_onFullScreenChanged);
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
      final added = await favorites.add(moment.seed, title: moment.title, summary: Favorite.momentSummary, rule: widget.controller.rule);
      if (!added) return say('That exact board is already in your favorites.');
      final code = SeedCodec.encode(moment.seed);
      say(
        'Saved "${moment.title}" to favorites',
        actionLabel: 'Undo',
        onAction: () => favorites.remove(favorites.items.firstWhere((f) => f.code == code)),
      );
    } on FavoriteTooLarge catch (e) {
      say(e.message);
    }
  }

  /// The board as RLE; a pattern loaded there gets a toast naming it.
  Future<void> _openRle() async {
    final loaded = await showRleDialog(context, widget.controller);
    if (loaded != null && mounted) {
      _toasts.show(
        widget.controller.giant != null
            ? 'Loaded "$loaded" on an endless plane, run by HashLife. Drag to pan, scroll or pinch to zoom.'
            : 'Loaded "$loaded".',
      );
    }
    _focus.requestFocus(); // the dialog had the keyboard; hand it back to the board
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

  /// The ⬇ for the macOS app, beside the 📷; null where it isn't offered.
  Widget? _macDownloadButton({double size = 18}) => (widget.offerMacDownload ?? (kIsWeb && isMacBrowser))
      ? IconButton(
          tooltip: 'Get the macOS app',
          visualDensity: VisualDensity.compact,
          onPressed: () => showMacDownloadDialog(context),
          icon: Icon(Icons.download_rounded, size: size, color: Neon.muted),
        )
      : null;

  /// Beside the 📷: both take something out of the app, an image or the pattern.
  /// Not in the control bar, which has no room left at the default window size.
  Widget _rleButton({double size = 18}) => IconButton(
    tooltip: 'Import or export RLE',
    visualDensity: VisualDensity.compact,
    onPressed: _openRle,
    icon: Icon(Icons.import_export_rounded, size: size, color: Neon.muted),
  );

  Widget _screenshotButton({double size = 18}) => IconButton(
    tooltip: 'Save a screenshot',
    visualDensity: VisualDensity.compact,
    onPressed: _shooting ? null : _saveScreenshot,
    icon: Icon(Icons.photo_camera_outlined, size: size, color: Neon.muted),
  );

  /// Board only and full screen go together: entering one enters both, and
  /// leaving full screen by any route (Esc in a browser, the window's green
  /// button) leaves Board only too.
  void _onFullScreenChanged() {
    final on = _fullScreen.active.value;
    if (on && _boardOnly) _boardOnlyFullScreen = true;
    if (!on && _boardOnly && _boardOnlyFullScreen) _setBoardOnly(false);
    if (mounted) setState(() {});
  }

  Future<void> _setBoardOnly(bool on) async {
    if (on == _boardOnly) return;
    setState(() => _boardOnly = on);
    _focus.requestFocus(); // the button that was pressed is gone; keep the keys working
    if (on) {
      if (_fullScreen.supported && !_fullScreen.active.value) await _fullScreen.set(true);
    } else {
      if (_boardOnlyFullScreen && _fullScreen.active.value) await _fullScreen.set(false);
      _boardOnlyFullScreen = false;
    }
  }

  Widget? _fullScreenButton({double size = 18}) {
    if (!_fullScreen.supported) return null;
    final on = _fullScreen.active.value;
    return IconButton(
      tooltip: on ? 'Exit full screen (F)' : 'Full screen (F)',
      visualDensity: VisualDensity.compact,
      onPressed: () => _fullScreen.set(!on),
      icon: Icon(on ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, size: size + 2, color: Neon.muted),
    );
  }

  Widget _boardOnlyButton({double size = 18}) => IconButton(
    tooltip: 'Board only (B)',
    visualDensity: VisualDensity.compact,
    onPressed: () => _setBoardOnly(true),
    icon: Icon(Icons.grid_on_rounded, size: size, color: Neon.muted), // the board; ⛶ is full screen
  );

  @override
  void dispose() {
    _fullScreen.active.removeListener(_onFullScreenChanged);
    if (widget.fullScreen == null) _fullScreen.dispose();
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
              final handled = {
                LogicalKeyboardKey.space,
                LogicalKeyboardKey.arrowLeft,
                LogicalKeyboardKey.arrowRight,
                LogicalKeyboardKey.keyF,
                LogicalKeyboardKey.keyB,
                LogicalKeyboardKey.escape,
              };
              if (!handled.contains(key)) return;
              // Key events bubble up from the chat box; a space typed there is text, not play/pause.
              final focused = FocusManager.instance.primaryFocus?.context;
              final typing =
                  focused != null && (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null);
              if (typing) return;
              if (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.keyB || key == LogicalKeyboardKey.escape) {
                if (e is! KeyDownEvent) return;
                if (key == LogicalKeyboardKey.keyB) _setBoardOnly(!_boardOnly);
                if (key == LogicalKeyboardKey.escape && _boardOnly) _setBoardOnly(false);
                if (key == LogicalKeyboardKey.keyF && _fullScreen.supported) _fullScreen.set(!_fullScreen.active.value);
                return;
              }
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
              builder: (context, _) => _boardOnly
                  ? BoardOnlyView(controller: c, clock: _clock, onExit: () => _setBoardOnly(false))
                  : LayoutBuilder(builder: (context, box) => Breakpoints.isMobile(box.biggest) ? _mobile(c) : _desktop(c)),
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
              LayoutBuilder(
                builder: (context, header) => Row(
                  children: [
                    // The logo and ⓘ open the about panel: who made this, and Conway's rules.
                    // Capped at 30% of the header, it scales down before the buttons would
                    // overflow, just above the phone breakpoint. Not a Flexible: a flex share
                    // it didn't use was left empty at the row's end, pulling the view buttons
                    // off the board's right edge.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: header.maxWidth * 0.3),
                      child: const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: LogoButton()),
                    ),
                    // Beside the ⓘ: getting the app belongs with "about this app".
                    ?_macDownloadButton(),
                    _screenshotButton(),
                    _rleButton(),
                    const SizedBox(width: 12),
                    // All the rest of the room; the stats scale down rather than overflow.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Hud(controller: c),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Right of the stats, flush with the board's right edge: Board only and full screen.
                    // (Size is chosen in the stats; zoom is in the control bar.)
                    _boardOnlyButton(),
                    ?_fullScreenButton(),
                  ],
                ),
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
                    // The logo gives way (it scales down) before the buttons would overflow.
                    const Flexible(
                      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: LogoButton(size: 15, letterSpacing: 4)),
                    ),
                    ?_macDownloadButton(size: 15),
                    _screenshotButton(size: 15),
                    // No separate ⛶ here: space is tight, and Board only goes full screen by itself.
                    _boardOnlyButton(size: 15),
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
                  onRle: _openRle,
                ),
              ),
              // Room for the sheet's resting height, so it never hides the controls.
              SizedBox(height: widget.assistant == null ? 8 : peek + 8),
            ],
          ),
          if (widget.assistant != null)
            MobileSheet(
              peekHeight: peek,
              // Opened from a share link: show its card (on Favorites) rather than hide it in a closed sheet.
              startOpen: widget.assistant!.shared != null,
              builder: (context, expanded, open) =>
                  AssistantPanel(assistant: widget.assistant!, embedded: true, showActions: expanded, onOpen: open),
            ),
        ],
      ),
    );
  }
}
