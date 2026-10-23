import 'dart:async';
import 'package:awalingo/services/android_push_api.dart';
import 'package:awalingo/services/android_push_platform.dart';
import 'package:awalingo/services/android_push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User pushUser(String id) => User(
  id: id,
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-19',
);

class FakePushPlatform implements AndroidPushPlatform {
  @override
  bool get supported => true;
  final controller = StreamController<Map<String, dynamic>>.broadcast(
    sync: true,
  );
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  bool granted = true, available = true, gate = false;
  String? owner;
  String token = 'token-1';
  int prompts = 0, tokenReads = 0;
  void Function()? onTokenRead;
  Map<String, dynamic>? tap;
  @override
  Future<PushPermission> status() async =>
      PushPermission(granted: granted, available: available);
  @override
  Future<PushPermission> requestPermission() async {
    prompts++;
    return status();
  }

  @override
  Future<String> getToken() async {
    tokenReads++;
    onTokenRead?.call();
    return token;
  }

  @override
  Future<void> setSession(
    String? ownerId,
    String environment,
    bool enabled,
  ) async {
    owner = ownerId;
    gate = enabled;
  }

  @override
  Future<void> cancelNotifications() async {}
  @override
  Future<void> deleteToken() async {}
  @override
  Future<Map<String, dynamic>?> getInitialTap() async {
    final value = tap;
    tap = null;
    return value;
  }

  @override
  Future<void> openSettings() async {}
}

class FakePushApi implements AndroidPushApi {
  @override
  bool get configured => true;
  bool account = false, device = false, fail = false;
  PushRegistration? nextStatus;
  int enables = 0, disables = 0, removes = 0;
  String? registeredToken;
  Completer<void>? delay;
  PushRegistration result() => PushRegistration(
    configured: true,
    accountEnabled: account,
    deviceEnabled: device,
    environment: 'test.supabase.co',
  );
  @override
  Future<PushRegistration> status(String installationId, String bearer) async {
    if (fail) throw const PushApiException('Network unavailable');
    final value = nextStatus;
    nextStatus = null;
    return value ?? result();
  }

  @override
  Future<PushRegistration> enable(
    String installationId,
    String token,
    String bearer,
  ) async {
    enables++;
    if (delay != null) await delay!.future;
    if (fail) throw const PushApiException('Network unavailable');
    account = device = true;
    registeredToken = token;
    return result();
  }

  @override
  Future<PushRegistration> disable(String installationId, String bearer) async {
    disables++;
    if (fail) throw const PushApiException('Network unavailable');
    account = device = false;
    return result();
  }

  @override
  Future<void> unregister(String installationId, String bearer) async {
    removes++;
    if (fail) throw const PushApiException('Network unavailable');
    device = false;
  }
}

Future<AndroidPushService> pushFixture(
  FakePushPlatform platform,
  FakePushApi api,
) async => AndroidPushService(
  platform: platform,
  api: api,
  preferences: await SharedPreferences.getInstance(),
  environment: 'test.supabase.co',
  accessToken: () => 'test-session',
);
