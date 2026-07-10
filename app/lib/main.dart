// TimePass shell — "Quiet Interface" design pass (see DESIGN.md).
//
// The answer surfaces themselves are rendered by genui from the server's
// A2UI stream against the TimePass catalog; the shell stays out of the way:
// white chrome, one black accent (the mic), gray query bubbles, thinking
// dots while the answer forms, soft-3D object tiles on the empty state.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

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
import 'theme/tp_theme.dart';
import 'theme/tp_widgets.dart';

void main() {
  runApp(const TimePassApp());
}

class TimePassApp extends StatelessWidget {
  const TimePassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TimePass',
      debugShowCheckedModeBanner: false,
      theme: tpTheme(Brightness.light),
      darkTheme: tpTheme(Brightness.dark),
      themeMode: ThemeMode.light,
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
    final answer =
        _Answer(
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
  final _inputFocus = FocusNode();
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
    _inputFocus.dispose();
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
        .listen(
          _controller.handleMessage,
          onError: (_) {},
          onDone: () {
            if (mounted) setState(() => answer.live = false);
            _liveSubs.remove(answer.surfaceId);
          },
        );
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
          duration: TpMotion.enter,
          curve: TpMotion.enterCurve,
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

  void _focusInput() {
    if (_scroll.hasClients && _answers.isEmpty) {
      _scroll.animateTo(
        0,
        duration: TpMotion.enter,
        curve: TpMotion.enterCurve,
      );
    }
    _inputFocus.requestFocus();
  }

  void _sendInput() => _send(_input.text);

  Future<void> _openLanguageMenu(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.tp.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Answer language', style: sectionHeader(sheetContext)),
              const SizedBox(height: 10),
              for (final option in const [
                ('en', 'English'),
                ('hi', 'हिंदी'),
                ('te', 'తెలుగు'),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option.$2),
                  trailing: option.$1 == _lang
                      ? Icon(Icons.check_rounded, color: sheetContext.tp.ink)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, option.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _lang = selected);
  }

  Future<void> _switchFromVoiceToKeyboard() async {
    if (_recording) {
      await _recorder.stop();
      if (mounted) setState(() => _recording = false);
    }
    _focusInput();
  }

  @override
  Widget build(BuildContext context) {
    final voiceActive = _recording || _transcribing;
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _MonogramHeader(
                            onMenuTap: () => _openLanguageMenu(context),
                            onCalendarTap: () => _send('aaj ka panchang'),
                          ),
                        ),
                      ),
                      if (_answers.isEmpty)
                        SliverToBoxAdapter(child: _MonogramHome(onAsk: _send))
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 28, 14, 8),
                          sliver: SliverList.builder(
                            itemCount: _answers.length,
                            itemBuilder: (context, index) => _AnswerTile(
                              answer: _answers[index],
                              controller: _controller,
                              onRetry: _send,
                              onSpeak: _speakCaption,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _MonogramDock(
                  controller: _input,
                  focusNode: _inputFocus,
                  recording: _recording,
                  transcribing: _transcribing,
                  onMicTap: _toggleMic,
                  onKeyboardTap: _focusInput,
                  onSubmit: _sendInput,
                ),
              ],
            ),
          ),
          if (voiceActive)
            _MonogramVoiceFocus(
              recording: _recording,
              transcribing: _transcribing,
              onMicTap: _toggleMic,
              onKeyboardTap: () => unawaited(_switchFromVoiceToKeyboard()),
            ),
        ],
      ),
    );
  }
}

class _MonogramHeader extends StatelessWidget {
  const _MonogramHeader({required this.onMenuTap, required this.onCalendarTap});

  final VoidCallback onMenuTap;
  final VoidCallback onCalendarTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _SoftCircleButton(
          icon: Icons.menu_rounded,
          tooltip: 'Menu and language',
          onPressed: onMenuTap,
        ),
        _SoftCircleButton(
          icon: Icons.calendar_today_outlined,
          tooltip: "Today's panchang",
          onPressed: onCalendarTap,
        ),
      ],
    );
  }
}

class _MonogramHome extends StatelessWidget {
  const _MonogramHome({required this.onAsk});

  final void Function(String query) onAsk;

  static const _continueItems = [
    (
      'Just now',
      'Follow the live cricket match',
      'Scores, wickets and the chase in one glance.',
      'assets/art/obj_ball.webp',
      'CSK vs MI live score',
    ),
    (
      'This morning',
      "See today's weather and air",
      'A quick read before you head outside.',
      'assets/art/obj_weather.webp',
      'Delhi weather and AQI today',
    ),
    (
      'Yesterday',
      'Plan the day with panchang',
      'Tithi, nakshatra and the best timings.',
      'assets/art/obj_diya.webp',
      'aaj ka panchang',
    ),
  ];

  static const _ideaItems = [
    (
      'assets/art/obj_air.webp',
      'Check the air quality before you head out.',
      'Delhi AQI right now',
    ),
    (
      'assets/art/obj_diya.webp',
      'Find the best time to start something today.',
      'today auspicious time and rahu kalam',
    ),
    (
      'assets/art/obj_weather.webp',
      "Compare this week's weather at a glance.",
      'Hyderabad weather this week',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return Padding(
      padding: const EdgeInsets.only(top: 34, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: display(
                      27,
                      weight: FontWeight.w400,
                      height: 1.28,
                      color: t.ink,
                    ),
                    children: const [
                      TextSpan(text: 'Good morning, '),
                      TextSpan(
                        text: 'Ravi.\n',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: 'Your '),
                      TextSpan(
                        text: 'morning update',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: ' is ready.'),
                    ],
                  ),
                ),
                const SizedBox(height: 17),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MonogramAction(
                      label: 'Play briefing',
                      onTap: () => onAsk('give me a morning briefing'),
                    ),
                    _MonogramAction(
                      label: 'See live cricket',
                      onTap: () => onAsk('CSK vs MI live score'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 19),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: _MonogramSectionTitle('Continue'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              itemCount: _continueItems.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _continueItems[index];
                return _ContinueCard(
                  eyebrow: item.$1,
                  title: item.$2,
                  summary: item.$3,
                  asset: item.$4,
                  onTap: () => onAsk(item.$5),
                );
              },
            ),
          ),
          const SizedBox(height: 26),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: _MonogramSectionTitle('New ideas'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              itemCount: _ideaItems.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _ideaItems[index];
                return _IdeaCard(
                  asset: item.$1,
                  label: item.$2,
                  onTap: () => onAsk(item.$3),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonogramSectionTitle extends StatelessWidget {
  const _MonogramSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: display(
        20,
        weight: FontWeight.w700,
        height: 1.2,
        color: context.tp.ink,
      ),
    );
  }
}

class _MonogramAction extends StatelessWidget {
  const _MonogramAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(13),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: t.ink.withValues(alpha: 0.09)),
            boxShadow: [
              BoxShadow(
                color: t.shadow,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: t.ink,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.eyebrow,
    required this.title,
    required this.summary,
    required this.asset,
    required this.onTap,
  });

  final String eyebrow;
  final String title;
  final String summary;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return SizedBox(
      width: 162,
      child: TpTapScale(
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: t.shadow,
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow,
                        style: TextStyle(
                          color: t.inkMuted,
                          fontSize: 10.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.18,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.inkMuted,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                height: 74,
                color: t.tile,
                alignment: Alignment.center,
                child: Image.asset(
                  asset,
                  height: 64,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    required this.asset,
    required this.label,
    required this.onTap,
  });

  final String asset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return SizedBox(
      width: 250,
      child: TpTapScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(17),
            boxShadow: [
              BoxShadow(
                color: t.shadow,
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: t.tile,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Image.asset(asset, height: 54),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonogramDock extends StatefulWidget {
  const _MonogramDock({
    required this.controller,
    required this.focusNode,
    required this.recording,
    required this.transcribing,
    required this.onMicTap,
    required this.onKeyboardTap,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool recording;
  final bool transcribing;
  final VoidCallback onMicTap;
  final VoidCallback onKeyboardTap;
  final VoidCallback onSubmit;

  @override
  State<_MonogramDock> createState() => _MonogramDockState();
}

class _MonogramDockState extends State<_MonogramDock> {
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_syncFocus);
  }

  @override
  void didUpdateWidget(covariant _MonogramDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_syncFocus);
      widget.focusNode.addListener(_syncFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_syncFocus);
    super.dispose();
  }

  void _syncFocus() {
    if (!mounted) return;
    if (!widget.focusNode.hasFocus && widget.controller.text.trim().isEmpty) {
      setState(() => _typing = false);
    }
  }

  void _openKeyboard() {
    setState(() => _typing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onKeyboardTap());
  }

  void _submit() {
    if (widget.controller.text.trim().isEmpty) return;
    widget.onSubmit();
    widget.focusNode.unfocus();
    setState(() => _typing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.bg.withValues(alpha: 0.98),
        boxShadow: [
          BoxShadow(color: t.bg, blurRadius: 24, offset: const Offset(0, -12)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: AnimatedSwitcher(
            duration: TpMotion.enter,
            switchInCurve: TpMotion.enterCurve,
            switchOutCurve: TpMotion.exitCurve,
            child: _typing
                ? Container(
                    key: const ValueKey('typing-dock'),
                    height: 58,
                    padding: const EdgeInsets.fromLTRB(6, 4, 5, 4),
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(31),
                      boxShadow: [
                        BoxShadow(
                          color: t.shadow,
                          blurRadius: 22,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {},
                          tooltip: 'Add',
                          icon: Icon(Icons.add_rounded, color: t.ink),
                        ),
                        Expanded(
                          child: TextField(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            onSubmitted: (_) => _submit(),
                            textInputAction: TextInputAction.send,
                            decoration: InputDecoration(
                              hintText: 'Ask anything...',
                              hintStyle: TextStyle(color: t.inkMuted),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton.filled(
                          onPressed: _submit,
                          tooltip: 'Ask',
                          style: IconButton.styleFrom(
                            backgroundColor: t.action,
                            foregroundColor: t.onAction,
                          ),
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                      ],
                    ),
                  )
                : Row(
                    key: const ValueKey('voice-dock'),
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SoftCircleButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Type a question',
                        onPressed: _openKeyboard,
                      ),
                      _VoicePill(
                        recording: widget.recording,
                        transcribing: widget.transcribing,
                        onTap: widget.onMicTap,
                      ),
                      _SoftCircleButton(
                        icon: Icons.keyboard_alt_outlined,
                        tooltip: 'Keyboard',
                        onPressed: _openKeyboard,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _VoicePill extends StatelessWidget {
  const _VoicePill({
    required this.recording,
    required this.transcribing,
    required this.onTap,
    this.width = 104,
  });

  final bool recording;
  final bool transcribing;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return TpTapScale(
      onTap: transcribing ? () {} : onTap,
      child: AnimatedContainer(
        duration: TpMotion.fast,
        width: width,
        height: 58,
        decoration: BoxDecoration(
          color: t.action,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: t.ink.withValues(alpha: recording ? 0.25 : 0.16),
              blurRadius: recording ? 24 : 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: transcribing
            ? ThinkingDots(size: 7)
            : recording
            ? ListeningWave(
                color: t.onAction,
                barCount: 5,
                height: 24,
                width: 58,
              )
            : Icon(Icons.mic_none_rounded, color: t.onAction, size: 27),
      ),
    );
  }
}

class _SoftCircleButton extends StatelessWidget {
  const _SoftCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: t.card,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: t.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, color: t.ink, size: 24),
      ),
    );
  }
}

class _MonogramVoiceFocus extends StatelessWidget {
  const _MonogramVoiceFocus({
    required this.recording,
    required this.transcribing,
    required this.onMicTap,
    required this.onKeyboardTap,
  });

  final bool recording;
  final bool transcribing;
  final VoidCallback onMicTap;
  final VoidCallback onKeyboardTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        duration: TpMotion.enter,
        curve: TpMotion.enterCurve,
        tween: Tween(begin: 0, end: 1),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.scale(scale: 0.985 + value * 0.015, child: child),
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: ColoredBox(
              color: t.bg.withValues(alpha: 0.94),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _SoftCircleButton(
                            icon: Icons.close_rounded,
                            tooltip: 'Close',
                            onPressed: transcribing ? () {} : onMicTap,
                          ),
                          _SoftCircleButton(
                            icon: Icons.keyboard_alt_outlined,
                            tooltip: 'Keyboard',
                            onPressed: onKeyboardTap,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(flex: 3),
                    AnimatedSwitcher(
                      duration: TpMotion.enter,
                      child: Column(
                        key: ValueKey(transcribing),
                        children: [
                          Text(
                            transcribing ? 'One moment' : 'I’m listening',
                            textAlign: TextAlign.center,
                            style: display(
                              36,
                              weight: FontWeight.w700,
                              height: 1.12,
                              color: t.ink,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            transcribing
                                ? 'Turning that into something useful.'
                                : 'Ask naturally. Tap the mic when you’re done.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: t.inkMuted,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      height: 54,
                      child: transcribing
                          ? const Center(child: ThinkingDots(size: 9))
                          : ListeningWave(
                              color: t.ink,
                              barCount: 7,
                              height: 48,
                              width: 108,
                            ),
                    ),
                    const Spacer(flex: 4),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _SoftCircleButton(
                            icon: Icons.add_rounded,
                            tooltip: 'Add',
                            onPressed: () {},
                          ),
                          _VoicePill(
                            recording: recording,
                            transcribing: transcribing,
                            onTap: onMicTap,
                            width: 142,
                          ),
                          _SoftCircleButton(
                            icon: Icons.keyboard_alt_outlined,
                            tooltip: 'Keyboard',
                            onPressed: onKeyboardTap,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Kept as an archived first-pass shell while the Monogram home is evaluated.
// ignore: unused_element
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.lang, required this.onLangChanged});

  final String lang;
  final ValueChanged<String> onLangChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return Row(
      children: [
        _RoundIconButton(
          icon: Icons.menu_rounded,
          tooltip: 'Menu',
          onPressed: () {},
        ),
        const Spacer(),
        const _Wordmark(),
        const Spacer(),
        PopupMenuButton<String>(
          initialValue: lang,
          tooltip: 'Language',
          onSelected: onLangChanged,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'en', child: Text('EN')),
            PopupMenuItem(value: 'hi', child: Text('हिं')),
            PopupMenuItem(value: 'te', child: Text('తె')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(99),
              boxShadow: [
                BoxShadow(
                  color: t.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              lang.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Stack(
          clipBehavior: Clip.none,
          children: [
            _RoundIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notifications',
              onPressed: () {},
            ),
            Positioned(
              right: 5,
              top: 5,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: t.signalRed,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.bg, width: 2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return IconButton(
      icon: Icon(icon, color: t.ink),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: t.bg,
        fixedSize: const Size(44, 44),
        shape: const CircleBorder(),
      ),
    );
  }
}

/// Plain wordmark with one genda identity stroke.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          left: 4,
          right: 4,
          bottom: 3,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: t.brand.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        Text(
          'TimePass',
          style: display(
            28,
            weight: FontWeight.w700,
            height: 1.05,
            color: t.ink,
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _QuickAskCard extends StatelessWidget {
  const _QuickAskCard({
    required this.recording,
    required this.transcribing,
    required this.onMicTap,
    required this.onTap,
  });

  final bool recording;
  final bool transcribing;
  final VoidCallback onMicTap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return TpTapScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 18, 18),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: t.brand, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Namaste, Ravi',
                    style: TextStyle(fontSize: 16, height: 1.25, color: t.ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    transcribing
                        ? 'Bas ek second...'
                        : recording
                        ? 'Sun raha hoon...'
                        : 'Aaj kya jaanna hai?',
                    style: display(
                      29,
                      weight: FontWeight.w700,
                      height: 1.12,
                      color: t.ink,
                    ),
                  ),
                ],
              ),
            ),
            GendaBurst(
              active: recording || transcribing,
              color: t.brand,
              child: _MicButton(
                recording: recording,
                onTap: transcribing ? () {} : onMicTap,
                size: 74,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mic: the one black accent — big, round, unmistakable. Coral while
/// recording.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.recording,
    required this.onTap,
    this.size = 48,
  });

  final bool recording;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return AnimatedContainer(
      duration: TpMotion.fast,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: recording ? t.signalRed : t.action,
        boxShadow: [
          BoxShadow(
            color: (recording ? t.signalRed : t.ink).withValues(alpha: 0.26),
            blurRadius: recording ? 22 : 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: IconButton(
        iconSize: size >= 70 ? 34 : 25,
        icon: Icon(
          recording ? Icons.stop_rounded : Icons.mic_rounded,
          color: recording ? Colors.white : t.onAction,
        ),
        tooltip: recording ? 'Stop listening' : 'Ask by voice',
        onPressed: onTap,
      ),
    );
  }
}

// ignore: unused_element
class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.onAsk});

  final void Function(String query) onAsk;

  static const _items = [
    (
      Icons.local_fire_department_rounded,
      'Trending',
      'what is trending in India today',
    ),
    (Icons.sports_cricket_rounded, 'Cricket', 'IPL live score'),
    (Icons.wb_cloudy_rounded, 'Weather', 'Hyderabad weather today'),
    (Icons.train_rounded, 'Train', '12952 train running status'),
    (Icons.calendar_month_rounded, 'Panchang', 'aaj ka panchang'),
    (Icons.movie_creation_rounded, 'Movies', 'pick one movie for tonight'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        children: [
          for (final (i, item) in _items.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ChoiceChip(
                selected: i == 0,
                showCheckmark: false,
                avatar: Icon(
                  item.$1,
                  size: 18,
                  color: i == 0 ? t.ink : t.inkMuted,
                ),
                label: Text(item.$2),
                selectedColor: t.brand,
                backgroundColor: t.card,
                side: BorderSide(color: t.ink.withValues(alpha: 0.08)),
                shape: const StadiumBorder(),
                onSelected: (_) => onAsk(item.$3),
              ),
            ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _DailyHome extends StatelessWidget {
  const _DailyHome({required this.onAsk});

  final void Function(String query) onAsk;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 360;
        final gap = twoColumns ? 12.0 : 10.0;
        final cardWidth = twoColumns
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _ScorePreviewCard(
                    onTap: () => onAsk('CSK vs MI live score'),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _WeatherPreviewCard(
                    onTap: () => onAsk('Delhi weather and AQI'),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _TrainPreviewCard(
                    onTap: () => onAsk('12952 Mumbai Rajdhani train status'),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _GyaanPreviewCard(
                    onTap: () => onAsk('Dahi jamane ka perfect tareeka?'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _MorningBanner(onTap: () => onAsk('give me a morning bulletin')),
          ],
        );
      },
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.tint,
  });

  final VoidCallback onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return TpEnter(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Material(
          color: tint ?? t.card,
          borderRadius: BorderRadius.circular(20),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class _ScorePreviewCard extends StatelessWidget {
  const _ScorePreviewCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    final theme = Theme.of(context).textTheme;
    return _HomeCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LiveBadge(),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, color: t.inkMuted),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Image.asset('assets/art/obj_ball.webp', height: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CSK', style: theme.bodyMedium),
                    Text('MI', style: theme.bodyMedium),
                  ],
                ),
              ),
              Text(
                '171/4',
                style: display(28, weight: FontWeight.w700, color: t.ink),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'MI needs 21 in 10 balls',
            style: display(14, weight: FontWeight.w600, color: t.signalRed),
          ),
        ],
      ),
    );
  }
}

class _WeatherPreviewCard extends StatelessWidget {
  const _WeatherPreviewCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    final theme = Theme.of(context).textTheme;
    return _HomeCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 18, color: t.inkMuted),
              const SizedBox(width: 6),
              Expanded(child: Text('Delhi, India', style: theme.bodySmall)),
              Icon(Icons.chevron_right_rounded, color: t.inkMuted),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '28°',
                style: display(42, weight: FontWeight.w700, color: t.ink),
              ),
              const SizedBox(width: 6),
              Image.asset('assets/art/obj_weather.webp', height: 52),
            ],
          ),
          Text('Partly cloudy', style: theme.bodyMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: t.link.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              'AQI 58',
              style: display(13, weight: FontWeight.w600, color: t.link),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainPreviewCard extends StatelessWidget {
  const _TrainPreviewCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    final theme = Theme.of(context).textTheme;
    return _HomeCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.train_rounded, color: t.link),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Train Status', style: sectionHeader(context)),
              ),
              Icon(Icons.chevron_right_rounded, color: t.inkMuted),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'NDLS',
                style: display(22, weight: FontWeight.w700, color: t.ink),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Divider(color: t.inkMuted.withValues(alpha: 0.38)),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: t.signalGreen),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Divider(color: t.inkMuted.withValues(alpha: 0.38)),
                ),
              ),
              Text(
                'MMCT',
                style: display(22, weight: FontWeight.w700, color: t.ink),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: t.signalGreen.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              'Running on time',
              style: display(
                12.5,
                weight: FontWeight.w600,
                color: t.signalGreen,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Arriving Danapur Jn at 10:35 AM', style: theme.bodySmall),
        ],
      ),
    );
  }
}

class _GyaanPreviewCard extends StatelessWidget {
  const _GyaanPreviewCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    final theme = Theme.of(context).textTheme;
    return _HomeCard(
      onTap: onTap,
      tint: t.brand.withValues(alpha: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/art/obj_diya.webp', height: 38),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Aaj ka Gyaan', style: sectionHeader(context)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Sawaal: Dahi jamane ka perfect tareeka?',
            style: display(14, weight: FontWeight.w700, color: t.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'Gungune doodh mein thoda purana dahi milao, dhak kar 6-8 ghante rakho.',
            style: theme.bodySmall?.copyWith(color: t.ink),
          ),
        ],
      ),
    );
  }
}

class _MorningBanner extends StatelessWidget {
  const _MorningBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return _HomeCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
      tint: t.brand.withValues(alpha: 0.26),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: t.brand,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Bazaar Morning',
                    style: display(12, weight: FontWeight.w700, color: t.ink),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Subah ki shuruaat,\nsahi jaankari ke saath',
                  style: display(
                    22,
                    weight: FontWeight.w700,
                    height: 1.18,
                    color: t.ink,
                  ),
                ),
              ],
            ),
          ),
          GendaBurst(
            active: true,
            color: t.brand,
            size: 78,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: t.action,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.graphic_eq_rounded, color: t.onAction),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _VoiceDock extends StatelessWidget {
  const _VoiceDock({
    required this.controller,
    required this.focusNode,
    required this.recording,
    required this.transcribing,
    required this.onMicTap,
    required this.onKeyboardTap,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool recording;
  final bool transcribing;
  final VoidCallback onMicTap;
  final VoidCallback onKeyboardTap;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: t.shadow,
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.add_rounded, color: t.inkMuted),
                tooltip: 'Add',
                onPressed: () {},
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onSubmitted: (_) => onSubmit(),
                  textInputAction: TextInputAction.send,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: recording
                        ? 'Listening...'
                        : transcribing
                        ? 'Transcribing...'
                        : 'Ask anything...',
                    hintStyle: TextStyle(color: t.inkMuted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (transcribing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: ThinkingDots(),
                )
              else
                GendaBurst(
                  active: recording,
                  size: 58,
                  color: t.brand,
                  child: _MicButton(
                    recording: recording,
                    onTap: onMicTap,
                    size: 48,
                  ),
                ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return IconButton(
                    icon: Icon(
                      hasText
                          ? Icons.arrow_upward_rounded
                          : Icons.keyboard_alt_outlined,
                      color: t.inkMuted,
                    ),
                    tooltip: hasText ? 'Ask' : 'Keyboard',
                    onPressed: hasText ? onSubmit : onKeyboardTap,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _VoiceFocusOverlay extends StatelessWidget {
  const _VoiceFocusOverlay({
    required this.recording,
    required this.transcribing,
    required this.onMicTap,
    required this.onKeyboardTap,
  });

  final bool recording;
  final bool transcribing;
  final VoidCallback onMicTap;
  final VoidCallback onKeyboardTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        duration: TpMotion.enter,
        curve: TpMotion.enterCurve,
        tween: Tween(begin: 0, end: 1),
        builder: (context, value, child) =>
            Opacity(opacity: value, child: child),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: t.bg.withValues(alpha: 0.86),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.close_rounded, color: t.ink),
                            tooltip: 'Close',
                            onPressed: recording ? onMicTap : () {},
                          ),
                          const Spacer(),
                          const _Wordmark(),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              Icons.keyboard_alt_outlined,
                              color: t.ink,
                            ),
                            tooltip: 'Keyboard',
                            onPressed: onKeyboardTap,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      transcribing ? 'Making sense of it' : 'I am listening',
                      textAlign: TextAlign.center,
                      style: display(
                        32,
                        weight: FontWeight.w700,
                        height: 1.12,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 18),
                    transcribing
                        ? const ThinkingDots(size: 9)
                        : ListeningWave(color: t.brand, height: 38, width: 72),
                    const SizedBox(height: 36),
                    GendaBurst(
                      active: recording || transcribing,
                      color: t.brand,
                      size: 126,
                      child: _MicButton(
                        recording: recording,
                        onTap: transcribing ? () {} : onMicTap,
                        size: 92,
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: Icon(Icons.add_rounded, color: t.ink),
                            tooltip: 'Add',
                            onPressed: () {},
                          ),
                          Text(
                            recording ? 'Tap to finish' : 'One moment',
                            style: TextStyle(
                              color: t.inkMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.keyboard_alt_outlined,
                              color: t.ink,
                            ),
                            tooltip: 'Keyboard',
                            onPressed: onKeyboardTap,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
    final t = context.tp;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: QueryBubble(text: answer.query),
          ),
          const SizedBox(height: 12),
          if (answer.error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.signalRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 18, color: t.signalRed),
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
            if (answer.loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 10, left: 4),
                child: ThinkingDots(),
              ),
            Surface(surfaceContext: controller.contextFor(answer.surfaceId)),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (answer.live) ...[
                    const LiveBadge(),
                    const SizedBox(width: 10),
                  ],
                  if (answer.caption.isNotEmpty) ...[
                    InkWell(
                      onTap: () => onSpeak(answer.caption),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.volume_up_outlined,
                          size: 16,
                          color: t.inkMuted,
                        ),
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
