import 'package:awalingo/services/android_push_api.dart';
import 'package:awalingo/services/notification_router.dart';
import 'package:awalingo/screens/main/notifications_screen.dart';
import 'package:http/http.dart' as http;
import '../test/support/offline_fixture.dart';
import 'package:awalingo/services/android_push_platform.dart';
import 'package:awalingo/services/android_push_taps.dart';
import 'package:awalingo/widgets/android_push_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/support/android_push_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Android permission deny then allow without launch prompt', (
    tester,
  ) async {
    final native = NativeAndroidPushPlatform();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Android notification permission test')),
        ),
      ),
    );
    final initial = await native.status();
    expect(initial.available, true);
    expect(initial.granted, false);
    final denied = await native.requestPermission();
    expect(denied.granted, false);
    final granted = await native.requestPermission();
    expect(granted.granted, true);
    await native.setSession(null, 'fixture.supabase.co', false);
    expect(await native.getInitialTap(), isNull);
  });
  testWidgets(
    'two complete push journeys and recovery with controlled account data',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final platform = FakePushPlatform(), api = FakePushApi();
      var service = await pushFixture(platform, api);
      await service.reconcile(pushUser('A'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Notification settings')),
            body: AndroidPushSetting(service: service),
          ),
        ),
      );
      for (var journey = 0; journey < 2; journey++) {
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(platform.gate, true);
        if (journey == 0) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pumpAndSettle();
          await binding.takeScreenshot('push-enabled');
        }
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(platform.gate, false);
        expect(api.account, false);
      }
      api.fail = true;
      await service.setEnabled(true);
      await tester.pumpAndSettle();
      expect(platform.gate, false);
      api.fail = false;
      await service.setEnabled(true);
      platform.token = 'rotated';
      platform.controller.add({'type': 'token'});
      await service.idle;
      expect(api.registeredToken, 'rotated');
      api.fail = true;
      await service.setEnabled(false);
      await tester.pumpAndSettle();
      expect(service.state.pendingDisable, true);
      await binding.takeScreenshot('push-off-pending-save');
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      api.fail = false;
      service = await pushFixture(platform, api);
      await service.reconcile(pushUser('A'));
      expect(api.account, false);
      expect(platform.gate, false);
      await service.setEnabled(true);
      api.fail = true;
      await service.prepareForSignOut();
      await service.idle;
      expect(platform.owner, isNull);
      api.fail = false;
      api.nextStatus = const PushRegistration(
        configured: true,
        accountEnabled: true,
        deviceEnabled: false,
        environment: 'test.supabase.co',
      );
      await service.reconcile(pushUser('B'));
      expect(platform.gate, false);
      final fixture = OfflineFixture();
      await fixture.initialize();
      fixture.offline = false;
      fixture.intercept = (request) async =>
          request.url.pathSegments.last == 'notifications'
          ? http.Response(
              '[]',
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            )
          : fixture.respond(request);
      late BuildContext navigationContext;
      await fixture.mount(
        tester,
        Builder(
          builder: (context) {
            navigationContext = context;
            return const Scaffold(body: Text('Home'));
          },
        ),
      );
      var navigations = 0;
      final taps = AndroidPushTaps(
        environment: 'test.supabase.co',
        navigate: (link, owner) async {
          navigations++;
          await openNotificationLink(navigationContext, owner, link);
        },
      );
      taps.setOwner(fixture.auth.user.id);
      final payload = {
        'v': '1',
        'recipientId': fixture.auth.user.id,
        'environment': 'test.supabase.co',
        'messageId': 'once',
        'link': '/unsupported',
      };
      await taps.receive(payload);
      expect(navigations, 0);
      await taps.setReady(true);
      await taps.receive(payload);
      expect(navigations, 1);
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      await binding.takeScreenshot('push-tap-notifications');
      await tester.pumpWidget(const SizedBox());
      await fixture.dispose();
      service.dispose();
    },
  );
}
