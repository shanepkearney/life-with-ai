import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/grid.dart';
import '../core/seed_codec.dart';
import 'build_info.dart';

/// Where an opened seed came from.
enum SeedSource {
  shareLink('share_link'),
  community('community'),
  favorite('favorite'),
  assistant('assistant');

  const SeedSource(this.wire);
  final String wire;
}

/// Counts which seeds get opened, through the event collector in analytics/.
///
/// What it sends: a 12-character fingerprint of the seed (never its cells),
/// where it was opened from, the community seed's name (those are public;
/// other titles are people's prompts, so never), the app version, and web or
/// macOS. Only released builds send anything: CI compiles in the collector's
/// address (TELEMETRY_URL) and the version; a local build has neither.
class Telemetry {
  Telemetry({required this.endpoint, required this.version, required this.platform, http.Client? client}) : _client = client;

  factory Telemetry.fromEnvironment({http.Client? client}) => Telemetry(
    endpoint: const String.fromEnvironment('TELEMETRY_URL'),
    version: BuildInfo.version,
    platform: kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.macOS ? 'macos' : ''),
    client: client,
  );

  final String endpoint;
  final String version;
  final String platform;
  final http.Client? _client;

  bool get enabled => endpoint.isNotEmpty && version.isNotEmpty && platform.isNotEmpty;

  /// The same seed always gets the same fingerprint, wherever it's opened,
  /// and it can't be turned back into the seed: 48 bits of an FNV-1a hash of
  /// the seed's code.
  static String fingerprint(Grid seed) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final unit in utf8.encode(SeedCodec.encode(seed))) {
      h = ((h ^ BigInt.from(unit)) * prime) & mask;
    }
    return h.toRadixString(16).padLeft(16, '0').substring(0, 12);
  }

  /// The event's body, or null when this build doesn't send.
  String? seedOpenedBody(Grid seed, SeedSource source, {String? communityName}) {
    if (!enabled) return null;
    return jsonEncode({
      'event': 'seed_opened',
      'seed': fingerprint(seed),
      'source': source.wire,
      if (source == SeedSource.community && communityName != null) 'name': communityName,
      'version': version,
      'platform': platform,
    });
  }

  /// Fire and forget: a failure to count never gets in the way of playing.
  Future<void> seedOpened(Grid seed, SeedSource source, {String? communityName}) async {
    final body = seedOpenedBody(seed, source, communityName: communityName);
    if (body == null) return;
    final client = _client ?? http.Client();
    try {
      // text/plain keeps it a "simple" request in browsers: no CORS preflight.
      await client
          .post(Uri.parse(endpoint), headers: {'Content-Type': 'text/plain'}, body: body)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline, blocked, or the collector is down: not the player's problem.
    } finally {
      if (_client == null) client.close();
    }
  }
}
