import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/grid.dart';
import '../core/seed_codec.dart';

/// A hearted seed. Stored as its [SeedCodec] code, so a favourite and a share
/// link are the same data.
class Favorite {
  Favorite({required this.code, required this.title, required this.summary, required this.savedAt});

  final String code;

  /// The prompt that produced it, e.g. "A symmetric bloom that slowly settles…".
  final String title;

  /// Claude's finish summary.
  final String summary;
  final DateTime savedAt;

  /// Decoded once: a saved board can be ~100 KB of code, and the list
  /// rebuilds far more often than favourites change.
  late final Grid seed = SeedCodec.decode(code);

  Map<String, Object> toJson() => {'code': code, 'title': title, 'summary': summary, 'savedAt': savedAt.toIso8601String()};

  static Favorite? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = json['code'], title = json['title'], summary = json['summary'], at = json['savedAt'];
    if (code is! String || SeedCodec.tryDecode(code) == null) return null;
    return Favorite(
      code: code,
      title: title is String ? title : 'Untitled seed',
      summary: summary is String ? summary : '',
      savedAt: (at is String ? DateTime.tryParse(at) : null) ?? DateTime.now(),
    );
  }
}

/// Thrown when a seed can't be kept without risking the whole collection.
class FavoriteTooLarge implements Exception {
  FavoriteTooLarge(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Hearted seeds, newest first, persisted on this device (localStorage on the
/// web). Nothing leaves the browser unless the user copies a share link.
class FavoritesStore extends ChangeNotifier {
  static const _prefKey = 'favorites_v1';

  /// Plenty for a personal collection, and keeps localStorage well under quota.
  static const maxFavorites = 200;

  /// Browsers give a site ~5 MB of localStorage, and a write that exceeds it
  /// fails outright, so an oversized favourite would silently lose every save
  /// after it. A designed seed is a few hundred characters; a whole random
  /// 512x384 board is ~110 KB; stay well inside the quota.
  static const maxCodeLength = 250 * 1024;
  static const maxTotalLength = 3 * 1024 * 1024;

  int get _totalLength => _items.fold(0, (n, f) => n + f.code.length + f.title.length + f.summary.length);

  final _items = <Favorite>[];
  List<Favorite> get items => List.unmodifiable(_items);

  bool contains(String code) => _items.any((f) => f.code == code);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List) {
          _items
            ..clear()
            ..addAll(list.map(Favorite.fromJson).whereType<Favorite>());
        }
      }
    } catch (_) {
      // Corrupt or unavailable storage (e.g. private browsing): start empty rather than fail to boot.
    }
    notifyListeners();
  }

  /// Hearts [seed], or un-hearts it if it is already a favourite. Returns
  /// whether it is a favourite afterwards.
  Future<bool> toggle(Grid seed, {required String title, required String summary}) async {
    final code = SeedCodec.encode(seed);
    if (contains(code)) {
      _items.removeWhere((f) => f.code == code);
      notifyListeners();
      await _save();
      return false;
    }
    await add(seed, title: title, summary: summary);
    return true;
  }

  /// Saves [seed] unless an identical one is already saved. Returns whether it
  /// was added. Throws [FavoriteTooLarge] rather than risk the collection.
  Future<bool> add(Grid seed, {required String title, required String summary}) async {
    final code = SeedCodec.encode(seed);
    if (contains(code)) return false;
    if (code.length > maxCodeLength) {
      throw FavoriteTooLarge('This board is too busy to save (${code.length ~/ 1024} KB). Try a calmer moment or a smaller board.');
    }
    if (_totalLength + code.length > maxTotalLength) {
      throw FavoriteTooLarge('Favourites are full. Delete a few large ones to make room.');
    }
    _items.insert(0, Favorite(code: code, title: title, summary: summary, savedAt: DateTime.now()));
    if (_items.length > maxFavorites) _items.removeRange(maxFavorites, _items.length);
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> remove(Favorite f) async {
    _items.removeWhere((x) => x.code == f.code);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(_items.map((f) => f.toJson()).toList()));
    } catch (_) {}
  }
}
