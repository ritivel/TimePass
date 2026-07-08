// TimePass M0 shell: query in → generated visual answer out.
//
// Deliberately plain chrome (M0). The answer surfaces themselves are rendered
// by genui from the server's A2UI stream against the TimePass catalog.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

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
}

class AnswerScreen extends StatefulWidget {
  const AnswerScreen({super.key});

  @override
  State<AnswerScreen> createState() => _AnswerScreenState();
}

class _AnswerScreenState extends State<AnswerScreen> {
  late final SurfaceController _controller;
  late final OrchestratorClient _client;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Answer> _answers = [];
  String _lang = 'en';
  var _nextSurface = 0;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    _client.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
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

  Future<void> _send(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _input.clear();
    final answer = _Answer(
      query: trimmed,
      surfaceId: 's_${_nextSurface++}',
    );
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
      await _client.send(
        query: trimmed,
        lang: _lang,
        surfaceId: answer.surfaceId,
        onMessage: _controller.handleMessage,
        // Caption streams in before the final surface on generic answers.
        onCaption: (caption) => setState(() => answer.caption = caption),
      );
      setState(() => answer.loading = false);
      // TODO(M1): speak the caption via Sarvam Bulbul TTS.
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
              onChanged: (value) =>
                  setState(() => _lang = value ?? 'en'),
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
                        answer: _answers[index], controller: _controller),
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
                        hintText: 'Ask anything…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
  const _AnswerTile({required this.answer, required this.controller});

  final _Answer answer;
  final SurfaceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
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
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(answer.query, style: theme.bodyMedium),
            ),
          ),
          const SizedBox(height: 12),
          if (answer.error != null)
            Text('Something went wrong: ${answer.error}',
                style: theme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error))
          else ...[
            if (answer.loading) const LinearProgressIndicator(minHeight: 2),
            Surface(surfaceContext: controller.contextFor(answer.surfaceId)),
            if (answer.caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.volume_up_outlined, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(answer.caption, style: theme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
