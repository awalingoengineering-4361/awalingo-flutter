import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

// Syncs display name into user_profile so leaderboard and other features
// can read it without needing access to auth.users.
Future<void> _syncProfileName(User user) async {
  final meta = user.userMetadata ?? {};
  final name =
      (meta['name'] as String?)?.trim() ??
      (meta['display_name'] as String?)?.trim() ??
      (meta['full_name'] as String?)?.trim() ??
      user.email?.split('@').first ??
      '';
  if (name.isEmpty) return;
  try {
    await Supabase.instance.client.from('user_profile').upsert({
      'userId': user.id,
      'name': name,
    }, onConflict: 'userId');
  } catch (_) {
    // Non-critical — leaderboard falls back gracefully if this fails
  }
}

/// Flutter equivalent of Next.js AuthContext.
/// Wrap your app with [AuthProvider] then call [AuthProvider.of(context)]
/// anywhere in the tree.
class AuthProvider extends InheritedNotifier<AuthNotifier> {
  const AuthProvider({
    super.key,
    required AuthNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  static AuthNotifier of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<AuthProvider>();
    assert(provider != null, 'No AuthProvider found in widget tree');
    return provider!.notifier!;
  }
}

class AuthNotifier extends ChangeNotifier {
  final AuthService _service = AuthService();
  final Future<void> Function()? beforeSignOut;
  StreamSubscription<AuthState>? _authSubscription;

  User? _user;
  bool _isLoading = true;
  String? _error;
  bool _disposed = false;
  Future<void>? _sessionCheck;
  String? _sessionCheckToken;

  User? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  AuthNotifier({this.beforeSignOut}) {
    _init();
  }

  void _init() {
    // Set initial user
    _user = _service.currentUser;
    _isLoading = false;

    // Listen to auth state changes — mirrors onAuthStateChange in Next.js
    _authSubscription = _service.authStateChanges.listen(
      (state) {
        final event = state.event;
        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.initialSession ||
            event == AuthChangeEvent.tokenRefreshed) {
          _user = state.session?.user;
          if (_user != null) _syncProfileName(_user!);
        } else if (event == AuthChangeEvent.signedOut) {
          // SDK storage cleanup can delay this event past a newer sign-in.
          _user = _service.currentUser;
        }
        _isLoading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object _) {
        unawaited(revalidateSession());
      },
    );
  }

  /// A remote deletion does not emit a local signed-out event on this device.
  Future<void> revalidateSession() {
    final session = _service.currentSession;
    if (_disposed || session == null || _user == null) return Future.value();
    final token = session.accessToken;
    if (_sessionCheckToken == token && _sessionCheck != null) {
      return _sessionCheck!;
    }
    _sessionCheckToken = token;
    late final Future<void> checking;
    checking = _checkSession(session.user.id, token).whenComplete(() {
      if (identical(_sessionCheck, checking)) {
        _sessionCheck = null;
        _sessionCheckToken = null;
      }
    });
    _sessionCheck = checking;
    return checking;
  }

  Future<void> _checkSession(String ownerId, String token) async {
    ({bool valid, String? accessToken}) result;
    try {
      result = await _service.validateSession().timeout(
        const Duration(seconds: 10),
      );
    } catch (_) {
      return; // Offline and server failures preserve cached offline access.
    }
    if (_disposed ||
        result.valid ||
        _user?.id != ownerId ||
        _service.currentSession?.accessToken != result.accessToken) {
      return;
    }
    await logoutAfterDeletion(ownerId, expectedAccessToken: result.accessToken);
  }

  // ─── Login ────────────────────────────────────────────────────────────────
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final user = await _service.login(email, password);
      _user = user;
      _isLoading = false;
      notifyListeners();
      return user != null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ─── Sign Up ──────────────────────────────────────────────────────────────
  Future<bool> signup({
    required String email,
    required String password,
    required String name,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final user = await _service.signup(
        email: email,
        password: password,
        name: name,
      );
      _user = user;
      _isLoading = false;
      notifyListeners();
      return user != null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ─── Google OAuth ─────────────────────────────────────────────────────────
  Future<void> signInWithGoogle() async {
    _error = null;
    try {
      await _service.signInWithGoogle();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  // ─── Logout ───────────────────────────────────────────────────────────────
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    try {
      await beforeSignOut?.call();
      await _service.logout();
      _user = null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    _isLoading = false;
    notifyListeners();
  }

  /// A durable deletion request must also clear this device when offline.
  Future<void> logoutAfterDeletion(
    String ownerId, {
    String? expectedAccessToken,
  }) async {
    if (_disposed || _user?.id != ownerId) return;
    try {
      await beforeSignOut?.call().timeout(const Duration(seconds: 5));
    } catch (_) {
      /* Server cleanup will remove registrations as well. */
    }
    final activeId = Supabase.instance.client.auth.currentUser?.id;
    if (_disposed ||
        _user?.id != ownerId ||
        (expectedAccessToken != null &&
            _service.currentSession?.accessToken != expectedAccessToken) ||
        (activeId != null && activeId != ownerId)) {
      return;
    }
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      /* Supabase clears the local session before its network call. */
    }
    final currentId = Supabase.instance.client.auth.currentUser?.id;
    // Local signOut clears synchronously before its HTTP request. Any session
    // present now belongs to a later sign-in, including the same account.
    if (_disposed || currentId != null) return;
    _user = null;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
