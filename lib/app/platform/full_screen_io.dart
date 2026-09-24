import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'full_screen.dart';

FullScreen platformFullScreen() => Platform.isMacOS ? _MacFullScreen() : NoFullScreen();

/// The macOS window's full screen, over a channel to MainFlutterWindow.swift.
class _MacFullScreen extends FullScreen {
  _MacFullScreen() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') active.value = call.arguments as bool;
    });
    _readInitial();
  }

  Future<void> _readInitial() async {
    try {
      active.value = await _channel.invokeMethod<bool>('isFullScreen') ?? false;
    } on MissingPluginException {
      // A test host without the window's channel: not full screen.
    }
  }

  static const _channel = MethodChannel('life_with_ai/full_screen');

  @override
  bool get supported => true;

  @override
  final ValueNotifier<bool> active = ValueNotifier(false);

  @override
  Future<void> set(bool on) async {
    try {
      await _channel.invokeMethod<void>('setFullScreen', on);
    } on MissingPluginException {
      // A test host without the window's channel: stay as we are.
    }
  }

  @override
  void dispose() => _channel.setMethodCallHandler(null);
}
