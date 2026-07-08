// HTTP client for the TimePass orchestrator.
//
// POST /v1/query streams NDJSON: one caption extension line
// ({"timepass": ...}) followed by A2UI v0.9.1 messages, which are parsed
// with genui's A2uiMessage and handed to the SurfaceController.

import 'dart:async';
import 'dart:convert';

import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;

/// localhost:8000 everywhere. On Android (device OR emulator) bridge the
/// port first: `adb reverse tcp:8000 tcp:8000`. Override with
/// `--dart-define=TIMEPASS_API=http://<host>:8000` (e.g. laptop LAN IP).
String defaultBaseUrl() {
  return const String.fromEnvironment(
    'TIMEPASS_API',
    defaultValue: 'http://localhost:8000',
  );
}

class OrchestratorClient {
  OrchestratorClient({String? baseUrl, http.Client? httpClient})
      : _baseUrl = baseUrl ?? defaultBaseUrl(),
        _http = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _http;

  /// Sends [query] and feeds resulting A2UI messages to [onMessage].
  /// [onCaption] fires as soon as the caption line arrives in the stream
  /// (for the generic tier that's well before the final surface).
  /// Returns the TTS caption (empty if the server sent none).
  Future<String> send({
    required String query,
    required String lang,
    required String surfaceId,
    required void Function(A2uiMessage message) onMessage,
    void Function(String caption)? onCaption,
  }) async {
    final request = http.Request('POST', Uri.parse('$_baseUrl/v1/query'))
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode({'query': query, 'lang': lang, 'surfaceId': surfaceId});

    final response = await _http.send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw http.ClientException(
        'query failed (${response.statusCode}): $body',
        request.url,
      );
    }

    var caption = '';
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line) as Map<String, Object?>;
      if (decoded.containsKey('timepass')) {
        final ext = decoded['timepass'] as Map<String, Object?>;
        caption = (ext['caption'] as String?) ?? '';
        if (caption.isNotEmpty) onCaption?.call(caption);
        continue;
      }
      onMessage(A2uiMessage.fromJson(decoded));
    }
    return caption;
  }

  void dispose() => _http.close();
}
