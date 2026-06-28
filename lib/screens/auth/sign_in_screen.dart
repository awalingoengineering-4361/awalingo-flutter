import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../services/auth_provider.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _rememberMe = false;

  String? _emailError;
  String? _passwordError;

  bool _validate() {
    setState(() {
      _emailError = _emailController.text.trim().isEmpty
          ? 'Email is required'
          : (!_emailController.text.contains('@') ? 'Enter a valid email' : null);
      _passwordError =
          _passwordController.text.isEmpty ? 'Password is required' : null;
    });
    return _emailError == null && _passwordError == null;
  }

  Future<void> _handleSignIn() async {
    if (!_validate()) return;
    final auth = AuthProvider.of(context);
    final success = await auth.login(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      _showError(auth.error ?? 'Login failed. Please check your credentials.');
    }
  }

  Future<void> _handleGoogleLogin() async {
    final auth = AuthProvider.of(context);
    await auth.signInWithGoogle();
    if (!mounted) return;
    if (auth.error != null) _showError(auth.error!);
  }

  Future<void> _handleAppleLogin() async {
    final auth = AuthProvider.of(context);
    await auth.signInWithApple();
    if (!mounted) return;
    if (auth.error != null) _showError(auth.error!);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.of(context);
    final loading = auth.isLoading;

    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Logo
              Image.asset(
                'assets/branding/logo-wordmark-light.png',
                height: 72,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 24),

              // Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    const Center(
                      child: Column(
                        children: [
                          Text(
                            'Sign into Your Account',
                            style: TextStyle(
                              fontFamily: 'Parkinsans',
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.foreground,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Sign in with',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.mutedForeground,
                              fontFamily: 'Metropolis',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Social buttons
                    Row(
                      children: [
                        Expanded(
                          child: SocialLoginButton(
                            label: 'Google',
                            icon: const GoogleIcon(),
                            onPressed: loading ? () {} : _handleGoogleLogin,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SocialLoginButton(
                            label: 'Apple',
                            icon: const Icon(Icons.apple, size: 20, color: AppColors.foreground),
                            onPressed: loading ? () {} : _handleAppleLogin,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Divider
                    Row(
                      children: [
                        Expanded(child: Divider(color: AppColors.border.withOpacity(0.4))),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or sign in with email',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.mutedForeground,
                              fontFamily: 'Metropolis',
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: AppColors.border.withOpacity(0.4))),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Email
                    AppTextField(
                      label: 'Email Address',
                      placeholder: 'Enter Email Address',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      errorText: _emailError,
                      enabled: !loading,
                      suffixIcon: const Icon(Icons.mail_outline, size: 20, color: AppColors.mutedForeground),
                    ),
                    const SizedBox(height: 16),

                    // Password
                    AppTextField(
                      label: 'Password',
                      placeholder: 'Enter Password',
                      controller: _passwordController,
                      obscure: !_showPassword,
                      enabled: !loading,
                      errorText: _passwordError,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: AppColors.mutedForeground,
                        ),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Remember me + Forgot password
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (v) =>
                                    setState(() => _rememberMe = v ?? false),
                                activeColor: AppColors.primary,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Remember Me',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.mutedForeground,
                                fontFamily: 'Metropolis',
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () {},
                          child: const Text(
                            'Forget Password?',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.mutedForeground,
                              fontFamily: 'Metropolis',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Login button
              AppButton(
                label: loading ? 'Signing In...' : 'Log in',
                loading: loading,
                onPressed: _handleSignIn,
              ),
              const SizedBox(height: 12),

              // Sign up link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(
                        fontSize: 12, color: AppColors.mutedForeground),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pushNamed('/signup'),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                        fontFamily: 'Metropolis',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
