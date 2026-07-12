// Nakul custom catalog items — "Quiet Interface" design pass.
//
// Every component is one polished implementation that all answers inherit
// (DESIGN.md). Names, schemas, and behavior are the contract
// (COMPONENT_CATALOG.md) and must not change here; only look and feel does.
// Chrome stays neutral; color appears only where it carries meaning
// (AQI bands, boundaries/wickets, alerts, festivals).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/orchestrator_client.dart';
import '../product/product_backend.dart';
import '../theme/tp_theme.dart';
import '../theme/tp_widgets.dart';
import 'schemas.g.dart';

/// All Nakul custom items, merged with the Basic Catalog by the caller.
List<CatalogItem> nakulCatalogItems() => [
  _markdown,
  _keyValueGrid,
  _comparisonTable,
  _checklist,
  _notice,
  _sourceChips,
  _followUpChips,
  _generatedVisual,
  _chartCard,
  _timelineCard,
  _recipeCard,
  _cricketLiveScore,
  _panchangCard,
  _weatherStrip,
  _aqiMeter,
];

Schema _schemaFor(String name) => ObjectSchema.fromMap(componentSchemas[name]!);

const _gap = SizedBox(height: 10);

// ── binding resolution ─────────────────────────────────────────────────────

bool _isBinding(Object? v) => v is Map && v.containsKey('path');

/// Resolves every top-level prop (literal or `{path}` binding) and rebuilds
/// when bound data-model values change. M0 templates only bind at the top
/// level of a prop, so this is sufficient.
class _ResolvedProps extends StatefulWidget {
  const _ResolvedProps({required this.itemContext, required this.builder});

  final CatalogItemContext itemContext;
  final Widget Function(BuildContext context, Map<String, Object?> props)
  builder;

  @override
  State<_ResolvedProps> createState() => _ResolvedPropsState();
}

class _ResolvedPropsState extends State<_ResolvedProps> {
  final Map<String, Object?> _resolved = {};
  final List<StreamSubscription<Object?>> _subs = [];

  @override
  void initState() {
    super.initState();
    final props = widget.itemContext.data as Map<String, Object?>;
    for (final entry in props.entries) {
      if (_isBinding(entry.value)) {
        _subs.add(
          widget.itemContext.dataContext.resolve(entry.value).listen((value) {
            if (mounted) setState(() => _resolved[entry.key] = value);
          }),
        );
      } else {
        _resolved[entry.key] = entry.value;
      }
    }
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _resolved);
}

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.cast<String, Object?>() : const {};

List<Map<String, Object?>> _mapList(Object? v) => v is List
    ? v.whereType<Map>().map((e) => e.cast<String, Object?>()).toList()
    : const [];

List<String> _strList(Object? v) =>
    v is List ? v.whereType<String>().toList() : const [];

Widget _labeled(BuildContext context, String label, String value) {
  final theme = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 112, child: Text(label, style: theme.bodySmall)),
        Expanded(child: Text(value, style: theme.bodyMedium)),
      ],
    ),
  );
}

/// Soft tinted tile for inline callouts (alerts, timings) — quiet, rounded,
/// no borders or stripes.
Widget _tintedTile(
  BuildContext context, {
  required Color tint,
  required Widget child,
  EdgeInsetsGeometry? padding,
}) {
  return Container(
    padding: padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

// ── Markdown ───────────────────────────────────────────────────────────────
// Prose answers. Not in genui's Basic Catalog, so it's ours: GFM subset,
// no raw HTML, no images (contract §7.1).

final _markdown = CatalogItem(
  name: 'Markdown',
  dataSchema: _schemaFor('Markdown'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final theme = Theme.of(context).textTheme;
      final t = context.tp;
      return MarkdownBody(
        data: _str(props['text']),
        selectable: false,
        styleSheet: MarkdownStyleSheet(
          p: theme.bodyMedium,
          h1: display(21, weight: FontWeight.w700, height: 1.3, color: t.ink),
          h2: display(18, weight: FontWeight.w600, height: 1.3, color: t.ink),
          h3: display(16, weight: FontWeight.w600, height: 1.3, color: t.ink),
          listBullet: theme.bodyMedium,
          blockquoteDecoration: BoxDecoration(
            color: t.tile,
            borderRadius: BorderRadius.circular(10),
          ),
          blockquotePadding: const EdgeInsets.all(10),
          code: theme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: t.ink,
            backgroundColor: t.tile,
          ),
        ),
      );
    },
  ),
);

// ── KeyValueGrid ───────────────────────────────────────────────────────────

final _keyValueGrid = CatalogItem(
  name: 'KeyValueGrid',
  dataSchema: _schemaFor('KeyValueGrid'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final theme = Theme.of(context).textTheme;
      final t = context.tp;
      final title = _str(props['title']);
      final columns = props['columns'] is int ? props['columns'] as int : 2;
      final items = _mapList(props['items']);

      Widget cell(Map<String, Object?> item) {
        final emphasis = item['emphasis'] == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_str(item['label']), style: theme.bodySmall),
            const SizedBox(height: 1),
            Text(
              _str(item['value']),
              style: emphasis
                  ? display(
                      17,
                      weight: FontWeight.w600,
                      height: 1.3,
                      color: t.ink,
                    )
                  : theme.bodyLarge,
            ),
          ],
        );
      }

      final rows = <Widget>[];
      for (var i = 0; i < items.length; i += columns) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = i; j < i + columns; j++)
                  Expanded(
                    child: j < items.length ? cell(items[j]) : const SizedBox(),
                  ),
              ],
            ),
          ),
        );
      }

      return TpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) ...[TpSectionHeader(title), _gap],
            ...rows,
          ],
        ),
      );
    },
  ),
);

// ── ComparisonTable ────────────────────────────────────────────────────────

final _comparisonTable = CatalogItem(
  name: 'ComparisonTable',
  dataSchema: _schemaFor('ComparisonTable'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final theme = Theme.of(context).textTheme;
      final t = context.tp;
      final title = _str(props['title']);
      final columns = _mapList(props['columns']);
      final rows = _mapList(props['rows']);
      final highlightKey = _str(props['highlightColumnKey']);
      final footnote = _str(props['footnote']);
      final highlightIndex = columns.indexWhere(
        (c) => _str(c['key']) == highlightKey,
      );

      TableCell cell(Widget child, int columnIndex) => TableCell(
        child: Container(
          color: columnIndex == highlightIndex ? t.tile : null,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: child,
        ),
      );

      return TpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) ...[TpSectionHeader(title), _gap],
            Table(
              columnWidths: const {0: IntrinsicColumnWidth()},
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              border: TableBorder(horizontalInside: BorderSide(color: t.tile)),
              children: [
                TableRow(
                  children: [
                    cell(const SizedBox(), -1),
                    for (final (i, col) in columns.indexed)
                      cell(
                        Text(
                          _str(col['label']),
                          style: display(
                            13,
                            weight: FontWeight.w600,
                            height: 1.3,
                            color: t.ink,
                          ),
                        ),
                        i,
                      ),
                  ],
                ),
                for (final row in rows)
                  TableRow(
                    children: [
                      cell(
                        Text(_str(row['label']), style: theme.bodySmall),
                        -1,
                      ),
                      for (final (i, _) in columns.indexed)
                        cell(
                          Text(
                            i < _strList(row['cells']).length
                                ? _strList(row['cells'])[i]
                                : '',
                            style: theme.bodyMedium,
                          ),
                          i,
                        ),
                    ],
                  ),
              ],
            ),
            if (footnote.isNotEmpty) ...[
              _gap,
              Text(footnote, style: theme.bodySmall),
            ],
          ],
        ),
      );
    },
  ),
);

// ── Checklist ──────────────────────────────────────────────────────────────

final _checklist = CatalogItem(
  name: 'Checklist',
  dataSchema: _schemaFor('Checklist'),
  widgetBuilder: (itemContext) => _ChecklistWidget(itemContext: itemContext),
);

class _ChecklistWidget extends StatefulWidget {
  const _ChecklistWidget({required this.itemContext});

  final CatalogItemContext itemContext;

  @override
  State<_ChecklistWidget> createState() => _ChecklistWidgetState();
}

class _ChecklistWidgetState extends State<_ChecklistWidget> {
  final Map<String, bool> _checked = {};

  @override
  Widget build(BuildContext context) {
    return _ResolvedProps(
      itemContext: widget.itemContext,
      builder: (context, props) {
        final title = _str(props['title']);
        final items = _mapList(props['items']);
        final interactive = props['interactive'] == true;

        return TpCard(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 6),
                  child: TpSectionHeader(title),
                ),
              for (final item in items) _row(context, item, interactive),
            ],
          ),
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    Map<String, Object?> item,
    bool interactive,
  ) {
    final theme = Theme.of(context).textTheme;
    final t = context.tp;
    final id = _str(item['id']);
    final checked = _checked[id] ?? (item['checked'] == true);
    final detail = _str(item['detail']);

    void toggle(bool? value) {
      setState(() => _checked[id] = value ?? false);
      widget.itemContext.dispatchEvent(
        UserActionEvent(
          name: 'checklist_toggled',
          sourceComponentId: widget.itemContext.id,
          context: {'itemId': id, 'checked': value ?? false},
        ),
      );
    }

    return CheckboxListTile(
      value: checked,
      onChanged: interactive ? toggle : null,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      title: Text(
        _str(item['text']),
        style: checked
            ? theme.bodyMedium?.copyWith(
                color: t.inkMuted,
                decoration: TextDecoration.lineThrough,
                decorationColor: t.inkMuted,
              )
            : theme.bodyMedium,
      ),
      subtitle: detail.isEmpty ? null : Text(detail, style: theme.bodySmall),
    );
  }
}

// ── Notice ─────────────────────────────────────────────────────────────────

final _notice = CatalogItem(
  name: 'Notice',
  dataSchema: _schemaFor('Notice'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final t = context.tp;
      final variant = _str(props['variant'], 'info');
      final dense = props['dense'] == true;
      final (icon, iconColor, tint) = switch (variant) {
        'warning' => (
          Icons.warning_amber_rounded,
          t.signalRed,
          t.signalRed.withValues(alpha: 0.08),
        ),
        'success' => (
          Icons.check_circle_outline,
          t.signalGreen,
          t.signalGreen.withValues(alpha: 0.08),
        ),
        'legal' => (Icons.balance_outlined, t.inkMuted, t.tile),
        _ => (Icons.info_outline, t.inkMuted, t.tile),
      };
      return TpEnter(
        child: _tintedTile(
          context,
          tint: tint,
          padding: dense
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
              : const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: iconColor),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _str(props['text']),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: t.ink.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  ),
);

// ── SourceChips ────────────────────────────────────────────────────────────
// Trust surface: 1–2 real sources beat many (DESIGN_RESEARCH.md §b5).

final _sourceChips = CatalogItem(
  name: 'SourceChips',
  dataSchema: _schemaFor('SourceChips'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final sources = _mapList(props['sources']);
      final t = context.tp;
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final s in sources)
            ActionChip(
              backgroundColor: t.tile,
              avatar: Icon(Icons.language, size: 14, color: t.inkMuted),
              label: Text(
                _str(s['domain']),
                style: TextStyle(fontSize: 12.5, color: t.link),
              ),
              tooltip: _str(s['title']),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                itemContext.dispatchEvent(
                  UserActionEvent(
                    name: 'source_opened',
                    sourceComponentId: itemContext.id,
                    context: {'url': _str(s['url'])},
                  ),
                );
                final uri = Uri.tryParse(_str(s['url']));
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      );
    },
  ),
);

// ── FollowUpChips ──────────────────────────────────────────────────────────

final _followUpChips = CatalogItem(
  name: 'FollowUpChips',
  dataSchema: _schemaFor('FollowUpChips'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final suggestions = _mapList(props['suggestions']);
      final t = context.tp;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in suggestions)
            ActionChip(
              backgroundColor: t.tile,
              label: Text(
                _str(s['label']),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                  color: t.ink,
                ),
              ),
              onPressed: () => itemContext.dispatchEvent(
                UserActionEvent(
                  name: 'follow_up_selected',
                  sourceComponentId: itemContext.id,
                  context: {'query': _str(s['query'])},
                ),
              ),
            ),
        ],
      );
    },
  ),
);

// ── GeneratedVisual ───────────────────────────────────────────────────────
// The model chooses whether an answer benefits from imagery and describes the
// subject. The server owns art direction, generation, caching, and safety.

final Map<String, Uint8List> _visualMemoryCache = {};

Future<Uint8List> _fetchVisual(String prompt, String aspectRatio) async {
  final key = '$aspectRatio\n$prompt';
  final cached = _visualMemoryCache[key];
  if (cached != null) return cached;
  final token = ProductBackend.accessToken();
  final response = await http
      .post(
        Uri.parse('${defaultBaseUrl()}/v1/visual'),
        headers: {
          'content-type': 'application/json',
          if (token != null && token.isNotEmpty)
            'authorization': 'Bearer $token',
        },
        body: jsonEncode({'prompt': prompt, 'aspectRatio': aspectRatio}),
      )
      .timeout(const Duration(seconds: 80));
  if (response.statusCode != 200) {
    throw http.ClientException('visual failed (${response.statusCode})');
  }
  final bytes = response.bodyBytes;
  _visualMemoryCache[key] = bytes;
  return bytes;
}

/// Replaced by renderer tests so GeneratedVisual can be exercised without a
/// network call. Production keeps the server-backed loader above.
@visibleForTesting
Future<Uint8List> Function(String prompt, String aspectRatio)
nakulVisualLoader = _fetchVisual;

final _generatedVisual = CatalogItem(
  name: 'GeneratedVisual',
  dataSchema: _schemaFor('GeneratedVisual'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) => _GeneratedVisualView(
      key: ValueKey('${_str(props['aspectRatio'])}:${_str(props['prompt'])}'),
      prompt: _str(props['prompt']),
      alt: _str(props['alt']),
      title: _str(props['title']),
      caption: _str(props['caption']),
      aspectRatio: _str(props['aspectRatio'], 'landscape'),
    ),
  ),
);

class _GeneratedVisualView extends StatefulWidget {
  const _GeneratedVisualView({
    super.key,
    required this.prompt,
    required this.alt,
    required this.title,
    required this.caption,
    required this.aspectRatio,
  });

  final String prompt;
  final String alt;
  final String title;
  final String caption;
  final String aspectRatio;

  @override
  State<_GeneratedVisualView> createState() => _GeneratedVisualViewState();
}

class _GeneratedVisualViewState extends State<_GeneratedVisualView> {
  late Future<Uint8List> _image;

  @override
  void initState() {
    super.initState();
    _image = nakulVisualLoader(widget.prompt, widget.aspectRatio);
  }

  void _retry() => setState(() {
    _visualMemoryCache.remove('${widget.aspectRatio}\n${widget.prompt}');
    _image = nakulVisualLoader(widget.prompt, widget.aspectRatio);
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    final ratio = switch (widget.aspectRatio) {
      'square' => 1.0,
      'portrait' => 4 / 5,
      _ => 16 / 9,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title.isNotEmpty) ...[
          TpSectionHeader(widget.title),
          const SizedBox(height: 10),
        ],
        Semantics(
          image: true,
          label: widget.alt,
          child: AspectRatio(
            aspectRatio: ratio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: FutureBuilder<Uint8List>(
                future: _image,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return AnimatedSwitcher(
                      duration: TpMotion.enter,
                      child: Image.memory(
                        snapshot.data!,
                        key: ValueKey(snapshot.data!.length),
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return ColoredBox(
                      color: t.tile,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.image_not_supported_outlined,
                              color: t.inkMuted,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Visual unavailable',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            TextButton(
                              onPressed: _retry,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ColoredBox(
                    color: t.tile,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ThinkingDots(),
                          const SizedBox(height: 12),
                          Text(
                            'Creating a visual…',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (widget.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              widget.caption,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

// ── ChartCard ─────────────────────────────────────────────────────────────

Color _chartColor(TpTokens t, String tone) => switch (tone) {
  'green' => t.signalGreen,
  'amber' => t.warnAmber,
  'red' => t.signalRed,
  'blue' => t.link,
  _ => t.ink,
};

final _chartCard = CatalogItem(
  name: 'ChartCard',
  dataSchema: _schemaFor('ChartCard'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final t = context.tp;
      final theme = Theme.of(context).textTheme;
      final series = _mapList(props['series']);
      final type = _str(props['type'], 'bar');
      final title = _str(props['title']);
      final subtitle = _str(props['subtitle']);
      final footnote = _str(props['footnote']);
      final values = [
        for (final item in series)
          item['value'] is num ? (item['value'] as num).toDouble() : 0.0,
      ];
      final colors = [
        for (final item in series) _chartColor(t, _str(item['tone'], 'ink')),
      ];
      final accessible = series
          .map(
            (item) => '${_str(item['label'])}: ${_str(item['displayValue'])}',
          )
          .join(', ');

      Widget chart;
      if (type == 'bar') {
        final maxValue = values.fold<double>(0, math.max);
        chart = SizedBox(
          height: 168,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, item) in series.indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        Text(
                          _str(item['displayValue']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: display(
                            12.5,
                            weight: FontWeight.w600,
                            color: t.ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) => Align(
                              alignment: Alignment.bottomCenter,
                              child: AnimatedContainer(
                                duration: TpMotion.enter,
                                width: 24,
                                height: maxValue <= 0
                                    ? 2
                                    : constraints.maxHeight *
                                          (values[index] / maxValue).clamp(
                                            0.04,
                                            1.0,
                                          ),
                                decoration: BoxDecoration(
                                  color: colors[index].withValues(alpha: 0.82),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _str(item['label']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      } else {
        chart = SizedBox(
          height: 176,
          child: CustomPaint(
            painter: _ChartPainter(type: type, values: values, colors: colors),
            child: const SizedBox.expand(),
          ),
        );
      }

      return TpCard(
        child: Semantics(
          label: '$title. $accessible',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TpSectionHeader(title),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(subtitle, style: theme.bodySmall),
              ],
              const SizedBox(height: 16),
              chart,
              if (type != 'bar') ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final (index, item) in series.indexed)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colors[index],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${_str(item['label'])} ${_str(item['displayValue'])}',
                            style: theme.bodySmall,
                          ),
                        ],
                      ),
                  ],
                ),
              ],
              if (footnote.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(footnote, style: theme.bodySmall),
              ],
            ],
          ),
        ),
      );
    },
  ),
);

class _ChartPainter extends CustomPainter {
  const _ChartPainter({
    required this.type,
    required this.values,
    required this.colors,
  });

  final String type;
  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    if (type == 'donut') {
      final total = values
          .where((value) => value > 0)
          .fold<double>(0, (a, b) => a + b);
      final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: math.min(size.width, size.height) * 0.37,
      );
      var start = -math.pi / 2;
      for (var i = 0; i < values.length; i++) {
        final sweep = total <= 0
            ? 0.0
            : math.pi * 2 * values[i].clamp(0, double.infinity) / total;
        canvas.drawArc(
          rect,
          start,
          math.max(0, sweep - 0.035),
          false,
          Paint()
            ..color = colors[i]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 24
            ..strokeCap = StrokeCap.round,
        );
        start += sweep;
      }
      return;
    }

    final maxValue = values.fold<double>(0, math.max);
    final minValue = values.fold<double>(values.first, math.min);
    final range = math.max(1.0, maxValue - minValue);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : i * size.width / (values.length - 1);
      final y =
          size.height -
          14 -
          ((values[i] - minValue) / range) * (size.height - 28);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final line = Paint()
      ..color = colors.first
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : i * size.width / (values.length - 1);
      final y =
          size.height -
          14 -
          ((values[i] - minValue) / range) * (size.height - 28);
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.type != type ||
      oldDelegate.values != values ||
      oldDelegate.colors != colors;
}

// ── TimelineCard ──────────────────────────────────────────────────────────

final _timelineCard = CatalogItem(
  name: 'TimelineCard',
  dataSchema: _schemaFor('TimelineCard'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final t = context.tp;
      final theme = Theme.of(context).textTheme;
      final items = _mapList(props['items']);
      final subtitle = _str(props['subtitle']);
      final footnote = _str(props['footnote']);
      Color statusColor(String status) => switch (status) {
        'done' => t.signalGreen,
        'active' => t.link,
        'warning' => t.signalRed,
        _ => t.inkMuted,
      };
      return TpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TpSectionHeader(_str(props['title'])),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(subtitle, style: theme.bodySmall),
            ],
            const SizedBox(height: 14),
            for (final (index, item) in items.indexed)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 68,
                      child: Text(
                        _str(item['timeLabel']),
                        style: theme.bodySmall,
                      ),
                    ),
                    SizedBox(
                      width: 22,
                      child: Column(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: statusColor(_str(item['status'])),
                              shape: BoxShape.circle,
                            ),
                          ),
                          if (index < items.length - 1)
                            Expanded(child: Container(width: 2, color: t.tile)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _str(item['title']),
                              style: display(
                                15,
                                weight: FontWeight.w600,
                                color: t.ink,
                              ),
                            ),
                            if (_str(item['detail']).isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                _str(item['detail']),
                                style: theme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (footnote.isNotEmpty) Text(footnote, style: theme.bodySmall),
          ],
        ),
      );
    },
  ),
);

// ── RecipeCard ────────────────────────────────────────────────────────────

final _recipeCard = CatalogItem(
  name: 'RecipeCard',
  dataSchema: _schemaFor('RecipeCard'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) => _RecipeCardView(
      key: ValueKey(
        '${_str(props['title'])}:${_mapList(props['steps']).length}',
      ),
      itemContext: itemContext,
      props: props,
    ),
  ),
);

class _RecipeCardView extends StatefulWidget {
  const _RecipeCardView({
    super.key,
    required this.itemContext,
    required this.props,
  });

  final CatalogItemContext itemContext;
  final Map<String, Object?> props;

  @override
  State<_RecipeCardView> createState() => _RecipeCardViewState();
}

class _RecipeCardViewState extends State<_RecipeCardView> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    final theme = Theme.of(context).textTheme;
    final ingredients = _mapList(widget.props['ingredients']);
    final steps = _mapList(widget.props['steps']);
    final tips = _strList(widget.props['tips']);
    final step = steps.isEmpty
        ? const <String, Object?>{}
        : steps[_step.clamp(0, steps.length - 1)];
    final meta = [
      _str(widget.props['servingsText']),
      _str(widget.props['totalTimeText']),
    ].where((value) => value.isNotEmpty).join(' · ');

    return TpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TpSectionHeader(_str(widget.props['title'])),
          if (_str(widget.props['summary']).isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(_str(widget.props['summary']), style: theme.bodyMedium),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(meta, style: theme.bodySmall),
          ],
          const SizedBox(height: 18),
          Text('What you need', style: sectionHeader(context)),
          const SizedBox(height: 10),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ingredients.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = ingredients[index];
                return Container(
                  width: 112,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.tile,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _str(item['name']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: display(
                          13,
                          weight: FontWeight.w600,
                          color: t.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _str(item['amount']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Text('Step by step', style: sectionHeader(context)),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < steps.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${index + 1}'),
                      selected: _step == index,
                      onSelected: (_) {
                        setState(() => _step = index);
                        widget.itemContext.dispatchEvent(
                          UserActionEvent(
                            name: 'recipe_step_selected',
                            sourceComponentId: widget.itemContext.id,
                            context: {'stepIndex': index},
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: TpMotion.enter,
            child: Container(
              key: ValueKey(_step),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.tile,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _str(step['title']),
                          style: display(
                            15,
                            weight: FontWeight.w700,
                            color: t.ink,
                          ),
                        ),
                      ),
                      if (_str(step['durationText']).isNotEmpty)
                        Text(
                          _str(step['durationText']),
                          style: theme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_str(step['detail']), style: theme.bodyMedium),
                ],
              ),
            ),
          ),
          if (tips.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Why it works', style: sectionHeader(context)),
            const SizedBox(height: 7),
            for (final tip in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 17,
                      color: t.signalGreen,
                    ),
                    const SizedBox(width: 7),
                    Expanded(child: Text(tip, style: theme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── CricketLiveScore ───────────────────────────────────────────────────────

final _cricketLiveScore = CatalogItem(
  name: 'CricketLiveScore',
  dataSchema: _schemaFor('CricketLiveScore'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final theme = Theme.of(context).textTheme;
      final t = context.tp;
      final teams = _mapList(props['teams']);
      final batters = _mapList(props['batters']);
      final bowler = _map(props['bowler']);
      final balls = _strList(props['recentBalls']);

      Widget teamRow(Map<String, Object?> team) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: 62,
              child: Text(
                _str(team['shortName']),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: t.inkMuted,
                ),
              ),
            ),
            Text(
              _str(team['scoreText']),
              style: display(
                22,
                weight: FontWeight.w700,
                height: 1.2,
                color: t.ink,
              ),
            ),
            const SizedBox(width: 8),
            Text('(${_str(team['oversText'])})', style: theme.bodySmall),
          ],
        ),
      );

      Widget ballDot(String ball) {
        final (bg, fg) = switch (ball) {
          'W' => (t.signalRed, Colors.white),
          '4' || '6' => (t.signalGreen, Colors.white),
          _ => (t.tile, t.ink),
        };
        return Container(
          width: 27,
          height: 27,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Text(
            ball,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        );
      }

      return TpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TpSectionHeader(
              _str(props['matchTitle']),
              trailing: const LiveBadge(),
            ),
            _gap,
            ...teams.map(teamRow),
            const SizedBox(height: 6),
            Text(
              _str(props['statusText']),
              style: display(
                15,
                weight: FontWeight.w600,
                height: 1.35,
                color: t.ink,
              ),
            ),
            if (batters.isNotEmpty) ...[
              _gap,
              Text(
                batters
                    .map(
                      (b) =>
                          '${_str(b['name'])} ${_str(b['runsText'])} (${_str(b['ballsText'])})',
                    )
                    .join('  •  '),
                style: theme.bodyMedium,
              ),
            ],
            if (bowler.isNotEmpty)
              Text(
                '${_str(bowler['name'])} ${_str(bowler['figuresText'])} (${_str(bowler['oversText'])})',
                style: theme.bodyMedium,
              ),
            if (balls.isNotEmpty) ...[
              _gap,
              Row(
                children: [
                  for (final ball in balls)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ballDot(ball),
                    ),
                ],
              ),
            ],
            _gap,
            Text(
              'updated ${_str(props['updatedAtText'])}',
              style: theme.bodySmall,
            ),
          ],
        ),
      );
    },
  ),
);

// ── PanchangCard ───────────────────────────────────────────────────────────

final _panchangCard = CatalogItem(
  name: 'PanchangCard',
  dataSchema: _schemaFor('PanchangCard'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final theme = Theme.of(context).textTheme;
      final t = context.tp;
      String timing(Object? v) {
        final m = _map(v);
        final ends = _str(m['endsAtText']);
        return ends.isEmpty ? _str(m['name']) : '${_str(m['name'])} · $ends';
      }

      final rahu = _map(props['rahuKalam']);
      final festivals = _strList(props['festivals']);

      return TpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_str(props['locationName']), style: theme.bodySmall),
            const SizedBox(height: 2),
            Text(
              _str(props['dateText']),
              style: display(
                19,
                weight: FontWeight.w700,
                height: 1.3,
                color: t.ink,
              ),
            ),
            _gap,
            _labeled(context, 'Tithi', timing(props['tithi'])),
            _labeled(context, 'Nakshatra', timing(props['nakshatra'])),
            if (_map(props['yoga']).isNotEmpty)
              _labeled(context, 'Yoga', timing(props['yoga'])),
            if (_map(props['karana']).isNotEmpty)
              _labeled(context, 'Karana', timing(props['karana'])),
            _labeled(
              context,
              'Sunrise / Sunset',
              '${_str(props['sunriseText'])} / ${_str(props['sunsetText'])}',
            ),
            _gap,
            _tintedTile(
              context,
              tint: t.warnAmber.withValues(alpha: 0.12),
              child: Text(
                'Rahu kalam  ${_str(rahu['startText'])} – ${_str(rahu['endText'])}',
                style: theme.bodyMedium,
              ),
            ),
            for (final f in festivals)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('◆ ', style: TextStyle(color: t.warnAmber)),
                    Expanded(child: Text(f, style: theme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  ),
);

// ── WeatherStrip ───────────────────────────────────────────────────────────

IconData _conditionIcon(String condition) => switch (condition) {
  'clear' => Icons.wb_sunny_outlined,
  'partlyCloudy' => Icons.wb_cloudy_outlined,
  'cloudy' => Icons.cloud_outlined,
  'mist' || 'haze' => Icons.blur_on,
  'rain' => Icons.water_drop_outlined,
  'heavyRain' => Icons.water_drop,
  'thunderstorm' => Icons.thunderstorm_outlined,
  'snow' => Icons.ac_unit,
  _ => Icons.thermostat,
};

final _weatherStrip = CatalogItem(
  name: 'WeatherStrip',
  dataSchema: _schemaFor('WeatherStrip'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final theme = Theme.of(context).textTheme;
      final t = context.tp;
      final current = _map(props['current']);
      final days = _mapList(props['days']);
      final alerts = _mapList(props['alerts']);
      final details = [
        _str(current['feelsLikeText']),
        _str(current['humidityText']),
        _str(current['windText']),
      ].where((s) => s.isNotEmpty).join('  ·  ');

      return TpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TpSectionHeader(_str(props['locationName'])),
            _gap,
            Row(
              children: [
                Icon(
                  _conditionIcon(_str(current['condition'])),
                  size: 36,
                  color: t.ink,
                ),
                const SizedBox(width: 12),
                Text(
                  _str(current['tempText']),
                  style: display(
                    34,
                    weight: FontWeight.w700,
                    height: 1.1,
                    color: t.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _str(current['conditionText']),
                    style: theme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (details.isNotEmpty) Text(details, style: theme.bodySmall),
            _gap,
            const Divider(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final day in days)
                    Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: Column(
                        children: [
                          Text(_str(day['dayLabel']), style: theme.bodySmall),
                          const SizedBox(height: 4),
                          Icon(
                            _conditionIcon(_str(day['condition'])),
                            size: 20,
                            color: t.inkMuted,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _str(day['maxText']),
                            style: display(
                              14.5,
                              weight: FontWeight.w600,
                              color: t.ink,
                            ),
                          ),
                          Text(_str(day['minText']), style: theme.bodySmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            for (final alert in alerts)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _tintedTile(
                  context,
                  tint: t.signalRed.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: t.signalRed,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _str(alert['text']),
                          style: theme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  ),
);

// ── AqiMeter ───────────────────────────────────────────────────────────────

Color _aqiColor(String category) => switch (category) {
  'good' => const Color(0xFF2E9E44),
  'satisfactory' => const Color(0xFF7BAE3A),
  'moderate' => const Color(0xFFD9A514),
  'poor' => const Color(0xFFDD7E23),
  'veryPoor' => const Color(0xFFE0453A),
  'severe' => const Color(0xFF9C2A1F),
  _ => Colors.grey,
};

/// The six CPCB bands as a segmented scale with a marker at the reading —
/// the meter encodes the real Indian AQI categories, not an abstract 0–100%.
class _CpcbScale extends StatelessWidget {
  const _CpcbScale({required this.aqi});

  final int aqi;

  static const _bands = [
    (50, 'good'),
    (100, 'satisfactory'),
    (200, 'moderate'),
    (300, 'poor'),
    (400, 'veryPoor'),
    (500, 'severe'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    final fraction = (aqi / 500).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 14,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                top: 4,
                bottom: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Row(
                    children: [
                      for (var i = 0; i < _bands.length; i++)
                        Expanded(
                          flex: _bands[i].$1 - (i == 0 ? 0 : _bands[i - 1].$1),
                          child: Container(
                            margin: const EdgeInsets.only(right: 1),
                            color: _aqiColor(
                              _bands[i].$2,
                            ).withValues(alpha: 0.28),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: (width * fraction - 1.5).clamp(0.0, width - 3),
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: t.ink,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

final _aqiMeter = CatalogItem(
  name: 'AqiMeter',
  dataSchema: _schemaFor('AqiMeter'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final theme = Theme.of(context).textTheme;
      final category = _str(props['category']);
      final color = _aqiColor(category);
      final aqi = props['aqi'] is num ? (props['aqi'] as num).round() : 0;
      final meta = [
        _str(props['dominantPollutant']),
        _str(props['stationName']),
        _str(props['updatedAtText']).isEmpty
            ? ''
            : 'updated ${_str(props['updatedAtText'])} ago',
      ].where((s) => s.isNotEmpty).join(' · ');

      return TpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TpSectionHeader('AQI · ${_str(props['locationName'])}'),
            _gap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$aqi',
                  style: display(
                    44,
                    weight: FontWeight.w700,
                    height: 1.05,
                    color: color,
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _str(props['categoryText']),
                    style: display(13.5, weight: FontWeight.w600, color: color),
                  ),
                ),
              ],
            ),
            _gap,
            _CpcbScale(aqi: aqi),
            _gap,
            if (meta.isNotEmpty) Text(meta, style: theme.bodySmall),
            const SizedBox(height: 6),
            Text(_str(props['healthAdviceText']), style: theme.bodyMedium),
          ],
        ),
      );
    },
  ),
);
