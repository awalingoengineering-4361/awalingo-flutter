import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'android_push_platform.dart';
import 'android_push_api.dart';

class AndroidPushState {
  final bool supported, busy, enabled, blockedByOs, pendingDisable;
  final String? error;
  const AndroidPushState({
    this.supported = true,
    this.busy = false,
    this.enabled = false,
    this.blockedByOs = false,
    this.pendingDisable = false,
    this.error,
  });
  AndroidPushState copy({
    bool? busy,
    bool? enabled,
    bool? blockedByOs,
    bool? pendingDisable,
    String? error,
  }) => AndroidPushState(
    supported: supported,
    busy: busy ?? this.busy,
    enabled: enabled ?? this.enabled,
    blockedByOs: blockedByOs ?? this.blockedByOs,
    pendingDisable: pendingDisable ?? this.pendingDisable,
    error: error,
  );
}

class AndroidPushService extends ChangeNotifier with WidgetsBindingObserver {
  final AndroidPushPlatform platform;
  final AndroidPushApi _api;
  final SharedPreferences _preferences;
  final String environment;
  final String? Function() _accessToken;
  late final String _installationId;
  late final Future<bool> _installationReady;
  late AndroidPushState _state;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Future<void> _tail = Future.value();
  User? _user;
  int _generation = 0, _tokenVersion = 0;
  bool _disposed = false, _mutationPending = false;
  String? _registeredOwner, _registeredToken;
  AndroidPushState get state => _state;
  String? get ownerId => _user?.id;
  Future<void> get idle => _tail;
  AndroidPushService({
    required this.platform,
    required AndroidPushApi api,
    required SharedPreferences preferences,
    required this.environment,
    required String? Function() accessToken,
  }) : _api = api,
       _preferences = preferences,
       _accessToken = accessToken {
    _installationId =
        preferences.getString('push.installation') ?? const Uuid().v4();
    _installationReady = preferences.setString(
      'push.installation',
      _installationId,
    );
    _state = AndroidPushState(
      supported: platform.supported && api.configured && environment.isNotEmpty,
    );
    if (platform.supported) {
      _subscription = platform.events.listen(
        (event) {
          if (event['type'] == 'token') {
            _tokenVersion++;
            unawaited(_closeGate());
            unawaited(reconcile(_user));
          }
        },
        onError: (_) {
          unawaited(_closeGate());
          _emit(
            _state.copy(
              enabled: false,
              error: 'Push updates disconnected. Reopen the app to retry.',
            ),
          );
        },
      );
      WidgetsBinding.instance.addObserver(this);
    }
  }
  void _emit(AndroidPushState value) {
    if (!_disposed) {
      _state = value;
      notifyListeners();
    }
  }

  bool _current(int generation, String owner) =>
      !_disposed && generation == _generation && owner == _user?.id;
  String _pendingKey(String owner) => 'push.pendingDisable.$owner';
  String _consentKey(String owner) => 'push.optIn.$owner';
  Future<void> _closeGate() async {
    try {
      await platform.setSession(null, environment, false);
    } catch (_) {
      /* Native channel unavailable: never open delivery from Dart. */
    }
  }

  Future<void> _enqueue(Future<void> Function() operation, int generation) {
    final next = _tail.then((_) async {
      if (_disposed || generation != _generation) return;
      _emit(_state.copy(busy: true));
      try {
        await _installationReady;
        await operation();
      } catch (error) {
        if (!_disposed && generation == _generation) {
          await _closeGate();
          _emit(
            _state.copy(
              enabled: false,
              error: error is PushApiException
                  ? error.message
                  : 'Unable to update push notifications. Please retry.',
            ),
          );
        }
      } finally {
        if (!_disposed && generation == _generation) {
          _emit(_state.copy(busy: false, error: _state.error));
        }
      }
    });
    _tail = next;
    return next;
  }

  Future<void> reconcile(User? user) {
    final changed = user?.id != _user?.id;
    _user = user;
    if (changed) {
      _generation++;
      _registeredOwner = _registeredToken = null;
      unawaited(_closeGate());
      _emit(AndroidPushState(supported: _state.supported));
    }
    if (user == null || !_state.supported) {
      unawaited(_closeGate());
      return Future.value();
    }
    final owner = user.id, generation = _generation;
    final bearer = _accessToken();
    if (bearer == null) {
      unawaited(_closeGate());
      _emit(_state.copy(enabled: false));
      return Future.value();
    }
    return _enqueue(() async {
      if (!_current(generation, owner)) return;
      if (_preferences.getBool(_pendingKey(owner)) == true) {
        await _closeGate();
        _emit(_state.copy(enabled: false, pendingDisable: true));
        await _api.disable(_installationId, bearer);
        await _preferences.remove(_pendingKey(owner));
        await _preferences.setBool(_consentKey(owner), false);
        if (_current(generation, owner)) {
          _emit(_state.copy(enabled: false, pendingDisable: false));
        }
        return;
      }
      final permission = await platform.status();
      final remote = await _api.status(_installationId, bearer);
      if (!_current(generation, owner)) return;
      if (!remote.configured || !permission.available) {
        throw const PushApiException(
          'Push notifications are not available yet. Please try later.',
        );
      }
      if (!permission.granted ||
          !remote.accountEnabled ||
          (!remote.deviceEnabled &&
              _preferences.getBool(_consentKey(owner)) != true)) {
        await _closeGate();
        _emit(_state.copy(enabled: false, blockedByOs: !permission.granted));
        return;
      }
      final token = await platform.getToken().timeout(
        const Duration(seconds: 15),
      );
      if (!_current(generation, owner)) return;
      final tokenVersion = _tokenVersion;
      if (_registeredOwner != owner ||
          _registeredToken != token ||
          !remote.deviceEnabled) {
        final registered = await _api.enable(_installationId, token, bearer);
        _requireAcknowledgement(registered);
      }
      if (!_current(generation, owner)) return;
      if (tokenVersion != _tokenVersion) return;
      _registeredOwner = owner;
      _registeredToken = token;
      await _preferences.setBool(_consentKey(owner), true);
      if (!_current(generation, owner) || tokenVersion != _tokenVersion) return;
      await platform.setSession(owner, environment, true);
      if (_current(generation, owner) && tokenVersion == _tokenVersion) {
        _emit(_state.copy(enabled: true, blockedByOs: false));
      } else {
        await _closeGate();
      }
    }, generation);
  }

  void _requireAcknowledgement(PushRegistration result) {
    if (!result.configured ||
        !result.accountEnabled ||
        !result.deviceEnabled ||
        result.environment != environment) {
      throw const PushApiException(
        'Push registration did not complete. Please retry.',
      );
    }
  }

  Future<void> setEnabled(bool enabled) {
    if (_mutationPending || _user == null || !_state.supported || _disposed) {
      return Future.value();
    }
    _mutationPending = true;
    final owner = _user!.id, generation = _generation, bearer = _accessToken();
    if (!enabled) {
      unawaited(_closeGate());
      _emit(_state.copy(enabled: false, pendingDisable: true));
    }
    final pendingSave = enabled
        ? Future.value(true)
        : _preferences.setBool(_pendingKey(owner), true);
    return _enqueue(() async {
      await pendingSave;
      if (bearer == null) {
        throw const PushApiException(
          'Sign in again to manage push notifications.',
        );
      }
      if (!enabled) {
        await _preferences.setBool(_pendingKey(owner), true);
        await _preferences.setBool(_consentKey(owner), false);
        await _closeGate();
        await _api.disable(_installationId, bearer);
        await _preferences.remove(_pendingKey(owner));
        if (_current(generation, owner)) {
          _emit(_state.copy(enabled: false, pendingDisable: false));
        }
        return;
      }
      if (_preferences.getBool(_pendingKey(owner)) == true) {
        await _api.disable(_installationId, bearer);
        await _preferences.remove(_pendingKey(owner));
      }
      final permission = await platform.requestPermission();
      if (!_current(generation, owner)) return;
      if (!permission.available) {
        throw const PushApiException(
          'Google Play services are unavailable on this device.',
        );
      }
      if (!permission.granted) {
        await _closeGate();
        _emit(_state.copy(enabled: false, blockedByOs: true));
        return;
      }
      final token = await platform.getToken().timeout(
        const Duration(seconds: 15),
      );
      if (!_current(generation, owner)) return;
      final tokenVersion = _tokenVersion;
      final result = await _api.enable(_installationId, token, bearer);
      _requireAcknowledgement(result);
      if (!_current(generation, owner) || tokenVersion != _tokenVersion) return;
      _registeredOwner = owner;
      _registeredToken = token;
      await _preferences.setBool(_consentKey(owner), true);
      if (!_current(generation, owner)) return;
      if (!_current(generation, owner) || tokenVersion != _tokenVersion) return;
      await platform.setSession(owner, environment, true);
      if (_current(generation, owner) && tokenVersion == _tokenVersion) {
        _emit(
          _state.copy(enabled: true, blockedByOs: false, pendingDisable: false),
        );
      } else {
        await _closeGate();
      }
    }, generation).whenComplete(() {
      _mutationPending = false;
    });
  }

  Future<void> prepareForSignOut() async {
    final owner = _user?.id, bearer = _accessToken();
    _user = null;
    _generation++;
    _registeredOwner = _registeredToken = null;
    await _closeGate();
    try {
      await platform.cancelNotifications();
    } catch (_) {
      /* Sign-out still proceeds. */
    }
    _emit(AndroidPushState(supported: _state.supported));
    // Cleanup is serialized ahead of the next account, but never delays sign-out.
    _tail = _tail.then((_) async {
      if (owner != null && bearer != null && _api.configured) {
        try {
          await _api
              .unregister(_installationId, bearer)
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          /* Native owner gate already closed. */
        }
      }
      try {
        await platform.deleteToken().timeout(const Duration(seconds: 15));
      } catch (_) {
        /* Next opt-in obtains current token. */
      }
    });
  }

  Future<void> openSettings() => platform.openSettings();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(reconcile(_user));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class AndroidPushScope extends InheritedNotifier<AndroidPushService> {
  const AndroidPushScope({
    super.key,
    required AndroidPushService service,
    required super.child,
  }) : super(notifier: service);
  static AndroidPushService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AndroidPushScope>()?.notifier;
}
