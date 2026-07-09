// TimePass M0 shell: query in → generated visual answer out.
//
// Deliberately plain chrome (M0). The answer surfaces themselves are rendered
// by genui from the server's A2UI stream against the TimePass catalog.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/orchestrator_client.dart';
import 'catalog/schemas.g.dart' as generated;
import 'catalog/timepass_catalog.dart';

void main() {
  runApp(const TimePassApp());
}

class TimePassApp extends StatelessWidget {
  const TimePassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TimePass',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const AnswerScreen(),
    );
  }
}

class _Answer {
  _Answer({required this.query, required this.surfaceId});

  final String query;
  final String surfaceId;
  String caption = '';
  String? error;
  bool loading = true;
  bool live = false;

  /// Raw NDJSON lines from the server — replayed on app restart so surfaces
  /// survive without re-querying.
  final List<String> lines = [];

  Map<String, Object?> toJson() => {
        'query': query,
        'surfaceId': surfaceId,
        'caption': caption,
        'lines': lines,
      };

  static _Answer fromJson(Map<String, Object?> json) {
    final answer = _Answer(
      query: json['query'] as String,
      surfaceId: json['surfaceId'] as String,
    )
      ..caption = (json['caption'] as String?) ?? ''
      ..loading = false;
    answer.lines.addAll((json['lines'] as List).cast<String>());
    return answer;
  }
}

class AnswerScreen extends StatefulWidget {
  const AnswerScreen({super.key});

  @override
  State<AnswerScreen> createState() => _AnswerScreenState();
}

class _AnswerScreenState extends State<AnswerScreen> {
  static const _historyKey = 'answers_v1';
  static const _maxStoredAnswers = 20;

  late final SurfaceController _controller;
  late final OrchestratorClient _client;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Answer> _answers = [];
  final Map<String, StreamSubscription<A2uiMessage>> _liveSubs = {};
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  String _lang = 'en';
  bool _recording = false;
  bool _transcribing = false;

  @override
  void initState() {
    super.initState();
    // The surface's catalogId (from createSurface) must match this catalog's
    // id, so the merged catalog is re-keyed to the TimePass id.
    final catalog = BasicCatalogItems.asCatalog().copyWith(
      newItems: timepassCatalogItems(),
      catalogId: generated.catalogId,
    );
    _controller = SurfaceController(catalogs: [catalog]);
    _client = OrchestratorClient();

    // User actions (e.g. FollowUpChips) come back as interaction messages.
    _controller.onSubmit.listen(_handleInteraction);

    _restoreAnswers();
  }

  @override
  void dispose() {
    for (final sub in _liveSubs.values) {
      sub.cancel();
    }
    _controller.dispose();
    _client.dispose();
    _input.dispose();
    _scroll.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── voice ────────────────────────────────────────────────────────────────

  /// Tap to record, tap again to stop → transcribe → send. The spoken
  /// language is auto-detected server-side, so a Telugu question gets a
  /// Telugu answer regardless of the language picker.
  Future<void> _toggleMic() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() {
        _recording = false;
        _transcribing = true;
      });
      try {
        if (path != null) {
          // XFile reads both file paths (mobile/desktop) and blob URLs (web).
          final bytes = await XFile(path).readAsBytes();
          final result = await _client.transcribe(bytes);
          if (result.transcript.isNotEmpty) {
            setState(() => _lang = result.lang);
            await _send(result.transcript, speak: true);
          }
        }
      } catch (e) {
        debugPrint('voice query failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't hear that — try again.")),
          );
        }
      } finally {
        if (mounted) setState(() => _transcribing = false);
      }
      return;
    }
    if (!await _recorder.hasPermission()) return;
    // On web the path is ignored (record returns a blob URL from stop()).
    final path = kIsWeb
        ? ''
        : '${(await getTemporaryDirectory()).path}/timepass_query.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    setState(() => _recording = true);
  }

  /// Speaks a caption via server-side TTS. Best-effort: voice output must
  /// never break the visual answer.
  Future<void> _speakCaption(String caption) async {
    if (caption.isEmpty) return;
    try {
      final bytes = await _client.synthesize(caption, _lang);
      await _player.stop();
      await _player.play(BytesSource(Uint8List.fromList(bytes)));
    } catch (e) {
      debugPrint('tts failed: $e');
    }
  }

  // ── persistence ──────────────────────────────────────────────────────────

  Future<void> _restoreAnswers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return;
    try {
      final stored = (jsonDecode(raw) as List).cast<Map>();
      for (final item in stored) {
        final answer = _Answer.fromJson(item.cast<String, Object?>());
        for (final line in answer.lines) {
          final decoded = jsonDecode(line) as Map<String, Object?>;
          if (decoded.containsKey('timepass')) continue;
          _controller.handleMessage(A2uiMessage.fromJson(decoded));
        }
        _answers.add(answer);
      }
      if (mounted) setState(() {});
    } catch (e) {
      // Corrupt or incompatible history (e.g. catalog changed) — start fresh.
      debugPrint('history restore failed: $e');
      await prefs.remove(_historyKey);
    }
  }

  Future<void> _persistAnswers() async {
    final prefs = await SharedPreferences.getInstance();
    final keep = _answers
        .where((a) => a.error == null && a.lines.isNotEmpty)
        .toList()
        .reversed
        .take(_maxStoredAnswers)
        .toList()
        .reversed
        .toList();
    await prefs.setString(
      _historyKey,
      jsonEncode([for (final a in keep) a.toJson()]),
    );
  }

  // ── conversation ─────────────────────────────────────────────────────────

  List<Map<String, String>> _recentHistory() {
    final turns = <Map<String, String>>[];
    for (final answer in _answers.where((a) => a.error == null)) {
      turns.add({'role': 'user', 'text': answer.query});
      if (answer.caption.isNotEmpty) {
        turns.add({'role': 'assistant', 'text': answer.caption});
      }
    }
    return turns.length > 12 ? turns.sublist(turns.length - 12) : turns;
  }

  void _handleInteraction(ChatMessage message) {
    for (final part in message.parts.uiInteractionParts) {
      final decoded = jsonDecode(part.interaction) as Map<String, Object?>;
      final action = (decoded['action'] as Map?)?.cast<String, Object?>();
      if (action == null) continue;
      if (action['name'] == 'follow_up_selected') {
        final context = (action['context'] as Map?)?.cast<String, Object?>();
        final query = context?['query'] as String?;
        if (query != null && query.isNotEmpty) _send(query);
      }
    }
  }

  void _subscribeLive(_Answer answer) {
    // Only the newest live surface stays subscribed.
    for (final sub in _liveSubs.values) {
      sub.cancel();
    }
    _liveSubs.clear();
    answer.live = true;
    _liveSubs[answer.surfaceId] = _client
        .liveMessages(answer.surfaceId)
        .listen(_controller.handleMessage, onError: (_) {}, onDone: () {
      if (mounted) setState(() => answer.live = false);
      _liveSubs.remove(answer.surfaceId);
    });
  }

  Future<void> _send(String query, {bool speak = false}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _input.clear();
    final answer = _Answer(
      query: trimmed,
      surfaceId: 's_${DateTime.now().millisecondsSinceEpoch}',
    );
    final history = _recentHistory();
    setState(() => _answers.add(answer));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
    try {
      final result = await _client.send(
        query: trimmed,
        lang: _lang,
        surfaceId: answer.surfaceId,
        history: history,
        onMessage: _controller.handleMessage,
        // Caption streams in before the final surface on generic answers.
        onCaption: (caption) => setState(() => answer.caption = caption),
        onLine: answer.lines.add,
      );
      setState(() {
        answer.caption = result.caption;
        answer.loading = false;
      });
      if (result.live) _subscribeLive(answer);
      unawaited(_persistAnswers());
      // Spoken question → spoken answer.
      if (speak) unawaited(_speakCaption(result.caption));
    } catch (e) {
      setState(() {
        answer.error = '$e';
        answer.loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TimePass'),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _lang,
              items: const [
                DropdownMenuItem(value: 'en', child: Text('EN')),
                DropdownMenuItem(value: 'hi', child: Text('हिं')),
                DropdownMenuItem(value: 'te', child: Text('తె')),
              ],
              onChanged: (value) => setState(() => _lang = value ?? 'en'),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _answers.isEmpty
                ? Center(
                    child: Text(
                      'Ask anything —\ncricket score, panchang, weather, AQI…',
                      textAlign: TextAlign.center,
                      style: theme.bodyLarge,
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _answers.length,
                    itemBuilder: (context, index) => _AnswerTile(
                      answer: _answers[index],
                      controller: _controller,
                      onRetry: _send,
                      onSpeak: _speakCaption,
                    ),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      onSubmitted: _send,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: _recording
                            ? 'Listening…'
                            : _transcribing
                                ? 'Transcribing…'
                                : 'Ask anything…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _transcribing
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton.filled(
                          style: _recording
                              ? IconButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.error,
                                )
                              : null,
                          icon: Icon(_recording ? Icons.stop : Icons.mic),
                          onPressed: _toggleMic,
                        ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: () => _send(_input.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({
    required this.answer,
    required this.controller,
    required this.onRetry,
    required this.onSpeak,
  });

  final _Answer answer;
  final SurfaceController controller;
  final void Function(String query) onRetry;
  final void Function(String caption) onSpeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(answer.query, style: theme.bodyMedium),
            ),
          ),
          const SizedBox(height: 12),
          if (answer.error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 18, color: colors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Couldn't reach TimePass — check the connection.",
                      style: theme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                    onPressed: () => onRetry(answer.query),
                  ),
                ],
              ),
            )
          else ...[
            if (answer.loading) const LinearProgressIndicator(minHeight: 2),
            Surface(surfaceContext: controller.contextFor(answer.surfaceId)),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (answer.live) ...[
                    Icon(Icons.sensors, size: 14, color: colors.error),
                    const SizedBox(width: 4),
                    Text('LIVE',
                        style: theme.labelSmall?.copyWith(color: colors.error)),
                    const SizedBox(width: 10),
                  ],
                  if (answer.caption.isNotEmpty) ...[
                    InkWell(
                      onTap: () => onSpeak(answer.caption),
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.volume_up_outlined, size: 16),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(answer.caption, style: theme.bodySmall),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
