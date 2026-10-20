import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PushPermission {
  final bool granted, available;
  const PushPermission({required this.granted, required this.available});
}

abstract interface class AndroidPushPlatform {
  bool get supported;
  Stream<Map<String, dynamic>> get events;
  Future<PushPermission> status();
  Future<PushPermission> requestPermission();
  Future<String> getToken();
  Future<void> setSession(String? ownerId, String environment, bool enabled);
  Future<void> deleteToken();
  Future<void> cancelNotifications();
  Future<Map<String, dynamic>?> getInitialTap();
  Future<void> openSettings();
}

class NativeAndroidPushPlatform implements AndroidPushPlatform {
  static const _methods = MethodChannel('awalingo/push');
  static const _events = EventChannel('awalingo/push/events');
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  late final Stream<Map<String, dynamic>> events = supported
      ? _events.receiveBroadcastStream().map(
          (event) => Map<String, dynamic>.from(event as Map),
        )
      : const Stream.empty();
  Future<PushPermission> _permission(String method) async {
    if (!supported) {
      return const PushPermission(granted: false, available: false);
    }
    final map = await _methods.invokeMapMethod<String, dynamic>(method) ?? {};
    return PushPermission(
      granted: map['granted'] == true,
      available: map['available'] == true,
    );
  }

  @override
  Future<PushPermission> status() => _permission('status');
  @override
  Future<PushPermission> requestPermission() =>
      _permission('requestPermission');
  @override
  Future<String> getToken() async =>
      (await _methods.invokeMethod<String>('getToken'))!;
  @override
  Future<void> setSession(
    String? ownerId,
    String environment,
    bool enabled,
  ) async {
    if (supported) {
      await _methods.invokeMethod<void>('setSession', {
        'ownerId': ownerId,
        'environment': environment,
        'enabled': enabled,
      });
    }
  }

  @override
  Future<void> deleteToken() async {
    if (supported) await _methods.invokeMethod<void>('deleteToken');
  }

  @override
  Future<void> cancelNotifications() async {
    if (supported) await _methods.invokeMethod<void>('cancelNotifications');
  }

  @override
  Future<Map<String, dynamic>?> getInitialTap() async => supported
      ? _methods.invokeMapMethod<String, dynamic>('getInitialTap')
      : null;
  @override
  Future<void> openSettings() async {
    if (supported) await _methods.invokeMethod<void>('openSettings');
  }
}
