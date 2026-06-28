import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

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
    final provider =
        context.dependOnInheritedWidgetOfExactType<AuthProvider>();
    assert(provider != null, 'No AuthProvider found in widget tree');
    return provider!.notifier!;
  }
}

class AuthNotifier extends ChangeNotifier {
  final AuthService _service = AuthService();

  User? _user;
  bool _isLoading = true;
  String? _error;

  User? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  AuthNotifier() {
    _init();
  }

  void _init() {
    // Set initial user
    _user = _service.currentUser;
    _isLoading = false;

    // Listen to auth state changes — mirrors onAuthStateChange in Next.js
    _service.authStateChanges.listen((state) {
      final event = state.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession ||
          event == AuthChangeEvent.tokenRefreshed) {
        _user = state.session?.user;
      } else if (event == AuthChangeEvent.signedOut) {
        _user = null;
      }
      _isLoading = false;
      _error = null;
      notifyListeners();
    });
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

  // ─── Apple OAuth ──────────────────────────────────────────────────────────
  Future<void> signInWithApple() async {
    _error = null;
    try {
      await _service.signInWithApple();
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
      await _service.logout();
      _user = null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
