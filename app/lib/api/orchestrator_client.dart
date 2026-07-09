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

class QueryResult {
  QueryResult({required this.caption, required this.live});

  /// The one-line TTS caption (empty if the server sent none).
  final String caption;

  /// Whether the surface supports live refresh via [liveMessages].
  final bool live;
}

class OrchestratorClient {
  OrchestratorClient({String? baseUrl, http.Client? httpClient})
      : _baseUrl = baseUrl ?? defaultBaseUrl(),
        _http = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _http;

  /// Sends [query] and feeds resulting A2UI messages to [onMessage].
  ///
  /// [history] carries recent conversation turns for follow-up context.
  /// [onCaption] fires as soon as the caption line arrives in the stream.
  /// [onLine] receives every raw NDJSON line (used to persist and replay
  /// surfaces across app restarts).
  Future<QueryResult> send({
    required String query,
    required String lang,
    required String surfaceId,
    required void Function(A2uiMessage message) onMessage,
    List<Map<String, String>> history = const [],
    void Function(String caption)? onCaption,
    void Function(String line)? onLine,
  }) async {
    final request = http.Request('POST', Uri.parse('$_baseUrl/v1/query'))
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode({
        'query': query,
        'lang': lang,
        'surfaceId': surfaceId,
        'history': history,
      });

    final response = await _http.send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw http.ClientException(
        'query failed (${response.statusCode}): $body',
        request.url,
      );
    }

    var caption = '';
    var live = false;
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      onLine?.call(line);
      final decoded = jsonDecode(line) as Map<String, Object?>;
      if (decoded.containsKey('timepass')) {
        final ext = decoded['timepass'] as Map<String, Object?>;
        caption = (ext['caption'] as String?) ?? '';
        live = ext['live'] == true;
        if (caption.isNotEmpty) onCaption?.call(caption);
        continue;
      }
      onMessage(A2uiMessage.fromJson(decoded));
    }
    return QueryResult(caption: caption, live: live);
  }

  /// Transcribes a spoken query (wav bytes, ≤30s). Returns the transcript
  /// and the auto-detected app language code (en/hi/te) — voice queries
  /// don't need the language picker.
  Future<({String transcript, String lang})> transcribe(List<int> wavBytes) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/v1/asr'))
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        wavBytes,
        filename: 'query.wav',
      ));
    final response = await http.Response.fromStream(await _http.send(request));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'asr failed (${response.statusCode}): ${response.body}',
        request.url,
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    return (
      transcript: (decoded['transcript'] as String?) ?? '',
      lang: (decoded['lang'] as String?) ?? 'en',
    );
  }

  /// Synthesizes [text] into spoken audio (WAV bytes) via the server's TTS.
  Future<List<int>> synthesize(String text, String lang) async {
    final response = await _http.post(
      Uri.parse('$_baseUrl/v1/tts'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'text': text, 'lang': lang}),
    );
    if (response.statusCode != 200) {
      throw http.ClientException('tts failed (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  /// Subscribes to live data-model refreshes for [surfaceId]. The stream
  /// closes when the server-side TTL expires. Cancel to unsubscribe.
  Stream<A2uiMessage> liveMessages(String surfaceId) async* {
    final request = http.Request('GET', Uri.parse('$_baseUrl/v1/live/$surfaceId'));
    final response = await _http.send(request);
    if (response.statusCode != 200) return; // expired or unknown — not an error
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      yield A2uiMessage.fromJson(jsonDecode(line) as Map<String, Object?>);
    }
  }

  void dispose() => _http.close();
}
