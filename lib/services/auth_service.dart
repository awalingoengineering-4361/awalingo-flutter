import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Current session user
  User? get currentUser => _supabase.auth.currentUser;
  bool get isAuthenticated => currentUser != null;

  // Stream of auth state changes (mirrors onAuthStateChange)
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // ─── Email / Password Sign In ─────────────────────────────────────────────
  // Mirrors: supabase.auth.signInWithPassword({ email, password })
  Future<User?> login(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.user;
    } on AuthException catch (e) {
      throw _friendlyError(e.message);
    } catch (e) {
      throw Exception('Login failed. Please try again.');
    }
  }

  // ─── Email / Password Sign Up ─────────────────────────────────────────────
  // Mirrors: supabase.auth.signUp({ email, password, options: { data: { name } } })
  Future<User?> signup({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'name': name, 'display_name': name},
      );
      return response.user;
    } on AuthException catch (e) {
      throw _friendlyError(e.message);
    } catch (e) {
      throw Exception('Registration failed. Please try again.');
    }
  }

  // ─── Google OAuth ─────────────────────────────────────────────────────────
  // Mirrors: supabase.auth.signInWithOAuth({ provider: 'google' })
  Future<void> signInWithGoogle() async {
    try {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.awalingo://login-callback',
      );
    } on AuthException catch (e) {
      throw _friendlyError(e.message);
    } catch (e) {
      throw Exception('Google sign in failed. Please try again.');
    }
  }

  // ─── Apple OAuth ──────────────────────────────────────────────────────────
  // Mirrors: supabase.auth.signInWithOAuth({ provider: 'apple' })
  Future<void> signInWithApple() async {
    try {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: 'io.supabase.awalingo://login-callback',
      );
    } on AuthException catch (e) {
      throw _friendlyError(e.message);
    } catch (e) {
      throw Exception('Apple sign in failed. Please try again.');
    }
  }

  // ─── Sign Out ─────────────────────────────────────────────────────────────
  // Mirrors: supabase.auth.signOut()
  Future<void> logout() async {
    try {
      await _supabase.auth.signOut();
    } on AuthException catch (e) {
      throw _friendlyError(e.message);
    }
  }

  // ─── Password Reset ───────────────────────────────────────────────────────
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } on AuthException catch (e) {
      throw _friendlyError(e.message);
    }
  }

  // ─── Friendly error messages (mirrors getAuthErrorMessage in Next.js) ─────
  Exception _friendlyError(String message) {
    final msg = message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid password')) {
      return Exception('Incorrect email or password. Please try again.');
    }
    if (msg.contains('email not confirmed')) {
      return Exception('Please verify your email before signing in.');
    }
    if (msg.contains('user already registered')) {
      return Exception('An account with this email already exists.');
    }
    if (msg.contains('password should be')) {
      return Exception('Password must be at least 6 characters.');
    }
    if (msg.contains('rate limit')) {
      return Exception('Too many attempts. Please wait a moment and try again.');
    }
    return Exception(message);
  }
}
