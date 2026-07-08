// Renderer-side contract test: real orchestrator NDJSON (recorded in
// test/fixtures/) must parse as A2UI v0.9.1, match the TimePass catalog, and
// render with data-model bindings resolved.
//
// Re-record fixtures after server changes:
//   curl -sN localhost:8000/v1/query -d '{"query":..., "surfaceId":...}' > test/fixtures/<name>.ndjson

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';

import 'package:timepass_app/catalog/schemas.g.dart' as generated;
import 'package:timepass_app/catalog/timepass_catalog.dart';

SurfaceController buildController() {
  final catalog = BasicCatalogItems.asCatalog().copyWith(
    newItems: timepassCatalogItems(),
    catalogId: generated.catalogId,
  );
  final controller = SurfaceController(catalogs: [catalog]);
  // Undisposed controllers keep timers/streams alive and hang the test
  // runner after the body completes.
  addTearDown(controller.dispose);
  return controller;
}

/// Feeds every A2UI line of a fixture into the controller and returns the
/// surface id from createSurface.
String feedFixture(SurfaceController controller, String name) {
  final lines = File('test/fixtures/$name.ndjson').readAsLinesSync();
  String? surfaceId;
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final decoded = jsonDecode(line) as Map<String, Object?>;
    if (decoded.containsKey('timepass')) continue; // caption extension line
    if (decoded.containsKey('createSurface')) {
      surfaceId = ((decoded['createSurface'] as Map)['surfaceId']) as String;
    }
    controller.handleMessage(A2uiMessage.fromJson(decoded));
  }
  return surfaceId!;
}

Future<void> pumpSurface(
  WidgetTester tester,
  SurfaceController controller,
  String surfaceId,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Surface(surfaceContext: controller.contextFor(surfaceId)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('cricket surface renders with bindings resolved (hi)',
      (tester) async {
    final controller = buildController();
    final surfaceId = feedFixture(controller, 'cricket_hi');
    await pumpSurface(tester, controller, surfaceId);

    // Structure from updateComponents; data via data-model bindings.
    expect(find.textContaining('IND vs AUS'), findsOneWidget);
    expect(find.textContaining('159/4'), findsOneWidget);
    expect(find.textContaining('43'), findsWidgets); // status line
    // R6 compliance: legal lag notice text present.
    expect(find.textContaining('5 मिनट'), findsOneWidget);
    // FollowUpChips rendered as tappable chips.
    expect(find.byType(ActionChip), findsWidgets);
  });

  testWidgets('weather surface renders forecast and IMD alert (en)',
      (tester) async {
    final controller = buildController();
    final surfaceId = feedFixture(controller, 'weather_en');
    await pumpSurface(tester, controller, surfaceId);

    expect(find.text('Hyderabad'), findsOneWidget);
    expect(find.textContaining('29°'), findsWidgets);
    expect(find.textContaining('orange alert'), findsOneWidget);
  });

  testWidgets('panchang surface renders localized Telugu strings',
      (tester) async {
    final controller = buildController();
    final surfaceId = feedFixture(controller, 'panchang_te');
    await pumpSurface(tester, controller, surfaceId);

    expect(find.textContaining('చతుర్దశి'), findsWidgets); // tithi
    expect(find.textContaining('Rahu kalam'), findsOneWidget);
  });

  testWidgets('follow-up chip tap dispatches follow_up_selected',
      (tester) async {
    final controller = buildController();
    final surfaceId = feedFixture(controller, 'weather_en');
    await pumpSurface(tester, controller, surfaceId);

    final queries = <String>[];
    final sub = controller.onSubmit.listen((message) {
      for (final part in message.parts.uiInteractionParts) {
        final decoded = jsonDecode(part.interaction) as Map<String, Object?>;
        final action = (decoded['action'] as Map).cast<String, Object?>();
        if (action['name'] == 'follow_up_selected') {
          queries.add(
              ((action['context'] as Map)['query'] as String?) ?? '');
        }
      }
    });
    addTearDown(sub.cancel);

    // Chips can sit below the test viewport's fold; invoke the handler
    // directly — this test covers event plumbing, not hit-testing.
    tester.widget<ActionChip>(find.byType(ActionChip).first).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(queries, ['hourly weather today']);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
