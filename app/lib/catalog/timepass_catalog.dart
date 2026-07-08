// TimePass custom catalog items (M0 set).
//
// Styling is deliberately plain and neutral: consistent spacing and default
// Material typography only. The post-M0 design pass restyles these widgets;
// names, schemas, and behavior are the contract (COMPONENT_CATALOG.md) and
// must not change there.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'schemas.g.dart';

/// All TimePass custom items, merged with the Basic Catalog by the caller.
List<CatalogItem> timepassCatalogItems() => [
      _markdown,
      _keyValueGrid,
      _notice,
      _followUpChips,
      _cricketLiveScore,
      _panchangCard,
      _weatherStrip,
      _aqiMeter,
    ];

Schema _schemaFor(String name) => ObjectSchema.fromMap(componentSchemas[name]!);

const _pad = EdgeInsets.all(16);
const _gap = SizedBox(height: 8);

// ── binding resolution ─────────────────────────────────────────────────────

bool _isBinding(Object? v) => v is Map && v.containsKey('path');

/// Resolves every top-level prop (literal or `{path}` binding) and rebuilds
/// when bound data-model values change. M0 templates only bind at the top
/// level of a prop, so this is sufficient.
class _ResolvedProps extends StatefulWidget {
  const _ResolvedProps({
    required this.itemContext,
    required this.builder,
  });

  final CatalogItemContext itemContext;
  final Widget Function(BuildContext context, Map<String, Object?> props) builder;

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
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(label, style: theme.bodySmall)),
        Expanded(child: Text(value, style: theme.bodyMedium)),
      ],
    ),
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
    builder: (context, props) => MarkdownBody(
      data: _str(props['text']),
      selectable: false,
    ),
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
      final title = _str(props['title']);
      final columns = props['columns'] is int ? props['columns'] as int : 2;
      final items = _mapList(props['items']);

      Widget cell(Map<String, Object?> item) {
        final emphasis = item['emphasis'] == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_str(item['label']), style: theme.bodySmall),
            Text(
              _str(item['value']),
              style: emphasis
                  ? theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
                  : theme.bodyLarge,
            ),
          ],
        );
      }

      final rows = <Widget>[];
      for (var i = 0; i < items.length; i += columns) {
        rows.add(Padding(
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
        ));
      }

      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: _pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty) ...[
                Text(title, style: theme.titleMedium),
                _gap,
              ],
              ...rows,
            ],
          ),
        ),
      );
    },
  ),
);

// ── Notice ─────────────────────────────────────────────────────────────────

final _notice = CatalogItem(
  name: 'Notice',
  dataSchema: _schemaFor('Notice'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final variant = _str(props['variant'], 'info');
      final dense = props['dense'] == true;
      final (icon, color) = switch (variant) {
        'warning' => (Icons.warning_amber_rounded, Colors.orange.shade800),
        'legal' => (Icons.info_outline, Colors.blueGrey.shade600),
        'success' => (Icons.check_circle_outline, Colors.green.shade700),
        _ => (Icons.info_outline, Colors.blue.shade700),
      };
      return Container(
        padding: dense
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
            : const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _str(props['text']),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: color),
              ),
            ),
          ],
        ),
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
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final s in suggestions)
            ActionChip(
              label: Text(_str(s['label'])),
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

// ── CricketLiveScore ───────────────────────────────────────────────────────

final _cricketLiveScore = CatalogItem(
  name: 'CricketLiveScore',
  dataSchema: _schemaFor('CricketLiveScore'),
  widgetBuilder: (itemContext) => _ResolvedProps(
    itemContext: itemContext,
    builder: (context, props) {
      final theme = Theme.of(context).textTheme;
      final teams = _mapList(props['teams']);
      final batters = _mapList(props['batters']);
      final bowler = _map(props['bowler']);
      final balls = _strList(props['recentBalls']);

      Widget teamRow(Map<String, Object?> team) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(_str(team['shortName']),
                      style: theme.titleMedium),
                ),
                Text(_str(team['scoreText']),
                    style:
                        theme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text('(${_str(team['oversText'])})', style: theme.bodySmall),
              ],
            ),
          );

      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: _pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_str(props['matchTitle']),
                        style: theme.titleMedium),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('LIVE',
                        style: theme.labelSmall
                            ?.copyWith(color: Colors.red.shade700)),
                  ),
                ],
              ),
              _gap,
              ...teams.map(teamRow),
              _gap,
              Text(_str(props['statusText']),
                  style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              if (batters.isNotEmpty) ...[
                _gap,
                Text(
                  batters
                      .map((b) =>
                          '${_str(b['name'])} ${_str(b['runsText'])} (${_str(b['ballsText'])})')
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
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: ball == 'W'
                              ? Colors.red.shade100
                              : ball == '4' || ball == '6'
                                  ? Colors.green.shade100
                                  : Colors.grey.shade200,
                          child: Text(ball, style: theme.labelSmall),
                        ),
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
      String timing(Object? v) {
        final m = _map(v);
        final ends = _str(m['endsAtText']);
        return ends.isEmpty ? _str(m['name']) : '${_str(m['name'])} · $ends';
      }

      final rahu = _map(props['rahuKalam']);
      final festivals = _strList(props['festivals']);

      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: _pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_str(props['locationName']), style: theme.bodySmall),
              Text(_str(props['dateText']), style: theme.titleMedium),
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Rahu kalam  ${_str(rahu['startText'])} – ${_str(rahu['endText'])}',
                  style: theme.bodyMedium,
                ),
              ),
              for (final f in festivals)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('◆ $f', style: theme.bodyMedium),
                ),
            ],
          ),
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
      final current = _map(props['current']);
      final days = _mapList(props['days']);
      final alerts = _mapList(props['alerts']);
      final details = [
        _str(current['feelsLikeText']),
        _str(current['humidityText']),
        _str(current['windText']),
      ].where((s) => s.isNotEmpty).join('  ·  ');

      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: _pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_str(props['locationName']), style: theme.titleMedium),
              _gap,
              Row(
                children: [
                  Icon(_conditionIcon(_str(current['condition'])), size: 40),
                  const SizedBox(width: 12),
                  Text(_str(current['tempText']), style: theme.displaySmall),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_str(current['conditionText']),
                        style: theme.bodyMedium),
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
                            Text(_str(day['dayLabel']),
                                style: theme.bodySmall),
                            const SizedBox(height: 4),
                            Icon(_conditionIcon(_str(day['condition'])),
                                size: 20),
                            const SizedBox(height: 4),
                            Text(_str(day['maxText']),
                                style: theme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            Text(_str(day['minText']), style: theme.bodySmall),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              for (final alert in alerts)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: Colors.orange.shade800),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_str(alert['text']),
                            style: theme.bodySmall),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  ),
);

// ── AqiMeter ───────────────────────────────────────────────────────────────

Color _aqiColor(String category) => switch (category) {
      'good' => Colors.green.shade600,
      'satisfactory' => Colors.lightGreen.shade700,
      'moderate' => Colors.amber.shade700,
      'poor' => Colors.orange.shade800,
      'veryPoor' => Colors.red.shade700,
      'severe' => Colors.red.shade900,
      _ => Colors.grey,
    };

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

      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: _pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AQI · ${_str(props['locationName'])}',
                  style: theme.titleMedium),
              _gap,
              Row(
                children: [
                  Text('$aqi',
                      style: theme.displayMedium?.copyWith(color: color)),
                  const SizedBox(width: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(_str(props['categoryText']),
                        style: theme.titleSmall?.copyWith(color: color)),
                  ),
                ],
              ),
              _gap,
              LinearProgressIndicator(
                value: (aqi / 500).clamp(0.0, 1.0),
                color: color,
                backgroundColor: Colors.grey.shade200,
                minHeight: 6,
              ),
              _gap,
              if (meta.isNotEmpty) Text(meta, style: theme.bodySmall),
              _gap,
              Text(_str(props['healthAdviceText']), style: theme.bodyMedium),
            ],
          ),
        ),
      );
    },
  ),
);
