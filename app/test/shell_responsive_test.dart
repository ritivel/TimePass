import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nakul_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in const [Size(360, 800), Size(412, 915)]) {
    testWidgets('shell remains usable at ${size.width}x${size.height}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const NakulApp());
      await tester.pump();

      expect(find.byTooltip('Keyboard'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Keyboard'));
      await tester.pumpAndSettle();

      expect(find.byType(EditableText), findsOneWidget);
      expect(find.byTooltip('Ask'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact shell supports 1.3x text scaling', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(360, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(const NakulApp());
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Keyboard'));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
