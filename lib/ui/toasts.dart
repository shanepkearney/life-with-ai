import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Short confirmations ("Link copied", "Removed … · Undo"), shown at the
/// bottom of the board area rather than as window-wide snackbars. The board
/// area ends above the control bar, so a toast can never cover the controls,
/// however many rows they wrap onto. A new toast replaces the current one at
/// once, so an Undo is never stuck behind an older message.
class ToastController extends ChangeNotifier {
  static const duration = Duration(seconds: 4);

  ToastMessage? current;
  Timer? _timer;
  int _nextId = 0;

  void show(String text, {String? actionLabel, VoidCallback? onAction}) {
    _timer?.cancel();
    current = ToastMessage(_nextId++, text, actionLabel, onAction);
    _timer = Timer(duration, dismiss);
    notifyListeners();
  }

  void dismiss() {
    _timer?.cancel();
    current = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

@immutable
class ToastMessage {
  const ToastMessage(this.id, this.text, this.actionLabel, this.onAction);
  final int id;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Makes a [ToastController] reachable from anywhere below it.
class Toasts extends InheritedWidget {
  const Toasts({super.key, required this.controller, required super.child});

  final ToastController controller;

  /// Shows a toast, or a themed snackbar when there's no [Toasts] above
  /// [context] (widgets tested on their own).
  static void show(BuildContext context, String text, {String? actionLabel, VoidCallback? onAction}) {
    final toasts = context.getInheritedWidgetOfExactType<Toasts>();
    if (toasts != null) {
      toasts.controller.show(text, actionLabel: actionLabel, onAction: onAction);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
        ),
      );
  }

  @override
  bool updateShouldNotify(Toasts old) => old.controller != controller;
}

/// Draws the current toast; place it in the board area's stack.
class ToastView extends StatelessWidget {
  const ToastView({super.key, required this.controller});

  final ToastController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final t = controller.current;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          child: t == null ? const SizedBox.shrink() : _Toast(key: ValueKey(t.id), toast: t, controller: controller),
        );
      },
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({super.key, required this.toast, required this.controller});

  final ToastMessage toast;
  final ToastController controller;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true, // announced by screen readers
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          decoration: Neon.panelDecoration(radius: 12).copyWith(
            color: const Color(0xF20B0E17),
            border: Border.all(color: Neon.magenta.withValues(alpha: 0.55)),
            boxShadow: [BoxShadow(color: Neon.magenta.withValues(alpha: 0.18), blurRadius: 24)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(toast.text, style: Neon.mono.copyWith(fontSize: 12, height: 1.4)),
                ),
              ),
              if (toast.actionLabel != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    controller.dismiss();
                    toast.onAction?.call();
                  },
                  style: TextButton.styleFrom(foregroundColor: Neon.magenta),
                  child: Text(
                    toast.actionLabel!,
                    style: Neon.mono.copyWith(color: Neon.magenta, fontWeight: FontWeight.bold),
                  ),
                ),
              ] else
                const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}
