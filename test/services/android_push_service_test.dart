import 'dart:async';
import 'package:awalingo/services/android_push_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/android_push_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'launch never prompts; enable disable enable registers and gates twice',
    () async {
      final platform = FakePushPlatform(), api = FakePushApi();
      final service = await pushFixture(platform, api);
      addTearDown(service.dispose);
      await service.reconcile(pushUser('A'));
      expect(platform.prompts, 0);
      expect(platform.gate, false);
      await service.setEnabled(true);
      expect(service.state.enabled, true);
      expect(platform.gate, true);
      await service.setEnabled(false);
      expect(service.state.enabled, false);
      expect(platform.gate, false);
      expect(api.account, false);
      await service.setEnabled(true);
      expect(platform.gate, true);
      expect(api.enables, 2);
    },
  );
  test('denial and OS revocation never leave local delivery open', () async {
    final platform = FakePushPlatform(), api = FakePushApi();
    final service = await pushFixture(platform, api);
    addTearDown(service.dispose);
    await service.reconcile(pushUser('A'));
    platform.granted = false;
    await service.setEnabled(true);
    expect(service.state.blockedByOs, true);
    expect(api.enables, 0);
    expect(platform.gate, false);
    platform.granted = true;
    await service.setEnabled(true);
    platform.granted = false;
    await service.reconcile(pushUser('A'));
    expect(platform.gate, false);
    expect(service.state.enabled, false);
  });
  test(
    'failed disable persists across restart and is retried before restoration',
    () async {
      final platform = FakePushPlatform(), api = FakePushApi();
      var service = await pushFixture(platform, api);
      await service.reconcile(pushUser('A'));
      await service.setEnabled(true);
      api.fail = true;
      await service.setEnabled(false);
      expect(platform.gate, false);
      expect(service.state.pendingDisable, true);
      service.dispose();
      api.fail = false;
      service = await pushFixture(platform, api);
      addTearDown(service.dispose);
      await service.reconcile(pushUser('A'));
      expect(api.account, false);
      expect(platform.gate, false);
      expect(service.state.pendingDisable, false);
    },
  );
  test(
    'simultaneous enable requests produce one registration and stale A result cannot open B gate',
    () async {
      final platform = FakePushPlatform(), api = FakePushApi();
      final service = await pushFixture(platform, api);
      addTearDown(service.dispose);
      await service.reconcile(pushUser('A'));
      api.delay = Completer<void>();
      final first = service.setEnabled(true);
      final duplicate = service.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      api.nextStatus = const PushRegistration(
        configured: true,
        accountEnabled: true,
        deviceEnabled: false,
        environment: 'test.supabase.co',
      );
      final switched = service.reconcile(pushUser('B'));
      expect(platform.gate, false);
      api.delay!.complete();
      await first;
      await duplicate;
      await switched;
      expect(api.enables, 1);
      expect(platform.gate, false);
      expect(service.state.enabled, false);
    },
  );
  test(
    'token refresh reconciles once and repeated logins own one event listener',
    () async {
      final platform = FakePushPlatform(), api = FakePushApi();
      final service = await pushFixture(platform, api);
      addTearDown(service.dispose);
      await service.reconcile(pushUser('A'));
      await service.setEnabled(true);
      platform.token = 'token-2';
      platform.controller.add({'type': 'token'});
      await service.idle;
      expect(api.registeredToken, 'token-2');
      final count = api.enables;
      await service.reconcile(pushUser('A'));
      await service.reconcile(pushUser('A'));
      expect(api.enables, count);
      service.dispose();
      expect(platform.controller.hasListener, false);
    },
  );
  test(
    'backend enable failure stays off and allows retry; offline logout clears gate immediately',
    () async {
      final platform = FakePushPlatform(), api = FakePushApi();
      final service = await pushFixture(platform, api);
      addTearDown(service.dispose);
      await service.reconcile(pushUser('A'));
      api.fail = true;
      await service.setEnabled(true);
      expect(platform.gate, false);
      expect(service.state.error, isNotNull);
      api.fail = false;
      await service.setEnabled(true);
      api.fail = true;
      await service.prepareForSignOut();
      expect(platform.gate, false);
      expect(platform.owner, isNull);
      await service.idle;
    },
  );
  test('token refresh cannot cancel an immediate disable intent', () async {
    final platform = FakePushPlatform(), api = FakePushApi();
    final service = await pushFixture(platform, api);
    addTearDown(service.dispose);
    await service.reconcile(pushUser('A'));
    await service.setEnabled(true);
    final disable = service.setEnabled(false);
    platform.controller.add({'type': 'token'});
    await disable;
    await service.idle;
    expect(platform.gate, false);
    expect(api.account, false);
  });

  test('initial native token event does not cancel explicit opt-in', () async {
    final platform = FakePushPlatform(), api = FakePushApi();
    final service = await pushFixture(platform, api);
    addTearDown(service.dispose);
    await service.reconcile(pushUser('A'));
    platform.onTokenRead = () {
      platform.onTokenRead = null;
      platform.controller.add({'type': 'token'});
    };
    await service.setEnabled(true);
    await service.idle;
    expect(service.state.enabled, true);
    expect(platform.gate, true);
  });
}
