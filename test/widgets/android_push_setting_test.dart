import 'package:awalingo/widgets/android_push_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/android_push_fixture.dart';

void main() {
  testWidgets(
    'switch explains account scope and displays failed save without enabled state',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final platform = FakePushPlatform(), api = FakePushApi();
      final service = await pushFixture(platform, api);
      addTearDown(service.dispose);
      await service.reconcile(pushUser('A'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AndroidPushSetting(service: service)),
        ),
      );
      expect(find.textContaining('account'), findsOneWidget);
      api.fail = true;
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
      expect(find.textContaining('Network unavailable'), findsOneWidget);
    },
  );
}
