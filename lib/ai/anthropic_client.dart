import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Models offered in settings, with list prices (USD per million tokens) for
/// the cost meter.
enum ClaudeModel {
  opus5('claude-opus-5', 'Claude Opus 5', 5, 25, serverFallbacks: true),
  sonnet5('claude-sonnet-5', 'Claude Sonnet 5', 2, 10);

  const ClaudeModel(this.id, this.label, this.inputPerMTok, this.outputPerMTok, {this.serverFallbacks = false});

  final String id;
  final String label;
  final double inputPerMTok;
  final double outputPerMTok;

  /// Opus 5 can decline some requests via safety classifiers; with server-side
  /// fallbacks the API reroutes those within the same call instead of stopping.
  final bool serverFallbacks;

  static ClaudeModel byId(String? id) => values.firstWhere((m) => m.id == id, orElse: () => opus5);
}

/// Running token totals and their approximate cost.
class Usage {
  int input = 0, output = 0, cacheWrite = 0, cacheRead = 0;

  void add(Map<String, dynamic>? u) {
    if (u == null) return;
    input += (u['input_tokens'] as num?)?.toInt() ?? 0;
    output += (u['output_tokens'] as num?)?.toInt() ?? 0;
    cacheWrite += (u['cache_creation_input_tokens'] as num?)?.toInt() ?? 0;
    cacheRead += (u['cache_read_input_tokens'] as num?)?.toInt() ?? 0;
  }

  /// Cache writes bill at 1.25x input, cache reads at 0.1x.
  double costUsd(ClaudeModel m) =>
      (input + cacheWrite * 1.25 + cacheRead * 0.1) * m.inputPerMTok / 1e6 + output * m.outputPerMTok / 1e6;
}

class AnthropicApiException implements Exception {
  AnthropicApiException(this.status, this.type, this.message);

  final int status;
  final String type;
  final String message;

  bool get retryable => status == 429 || status == 408 || status == 409 || status >= 500;

  @override
  String toString() => switch (status) {
        _ when message.contains('usage limits') =>
          '$message\n\nThis is a spend limit on your Anthropic workspace, not an app error. '
              'Raise it at platform.claude.com/settings/limits (and check Billing has credit).',
        _ when message.contains('credit balance') =>
          '$message\n\nAdd credit at platform.claude.com/settings/billing.',
        401 => 'The API key was rejected (401). Check it in settings.',
        403 => 'This key is not allowed to use that model (403).',
        429 => 'Rate limited by the API (429). Try again in a moment.',
        529 => 'The API is overloaded (529). Try again shortly.',
        _ => 'API error $status ($type): $message',
      };
}

/// Minimal Messages API client over raw HTTP (Dart has no official SDK).
/// Runs from the browser too: the user supplies their own key, so it is sent
/// with the header Anthropic requires to acknowledge client-side key use.
class AnthropicClient {
  AnthropicClient({required this.apiKey, required this.model, http.Client? httpClient, this.maxRetries = 2})
      : _http = httpClient ?? http.Client();

  static final endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  final String apiKey;
  final ClaudeModel model;
  final int maxRetries;
  final http.Client _http;

  Map<String, String> get headers => {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true',
        if (model.serverFallbacks) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      };

  Future<Map<String, dynamic>> createMessage(Map<String, dynamic> body) async {
    final payload = jsonEncode({
      'model': model.id,
      if (model.serverFallbacks) 'fallbacks': 'default',
      ...body,
    });
    for (var attempt = 0;; attempt++) {
      try {
        final res = await _http.post(endpoint, headers: headers, body: payload).timeout(const Duration(minutes: 5));
        final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        if (res.statusCode == 200) return json;
        final err = (json['error'] as Map?) ?? const {};
        throw AnthropicApiException(res.statusCode, '${err['type'] ?? 'error'}', '${err['message'] ?? res.reasonPhrase}');
      } on AnthropicApiException catch (e) {
        if (!e.retryable || attempt >= maxRetries) rethrow;
      } on TimeoutException {
        if (attempt >= maxRetries) rethrow;
      } on http.ClientException {
        if (attempt >= maxRetries) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 800 * (1 << attempt)));
    }
  }

  void close() => _http.close();
}
