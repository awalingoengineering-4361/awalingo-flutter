import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../services/auth_provider.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _showPassword = false;
  bool _showConfirm = false;

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  List<_PasswordRule> get _rules => [
        _PasswordRule('At least 8 characters', _passwordController.text.length >= 8),
        _PasswordRule('One uppercase letter (A-Z)', RegExp(r'[A-Z]').hasMatch(_passwordController.text)),
        _PasswordRule('One lowercase letter (a-z)', RegExp(r'[a-z]').hasMatch(_passwordController.text)),
        _PasswordRule('One number (0-9)', RegExp(r'[0-9]').hasMatch(_passwordController.text)),
        _PasswordRule('One special character (!@#\$...)', RegExp(r'[^A-Za-z0-9]').hasMatch(_passwordController.text)),
      ];

  bool get _passwordsMatch =>
      _confirmController.text.isNotEmpty &&
      _passwordController.text == _confirmController.text;

  bool _validate() {
    setState(() {
      _nameError = _nameController.text.trim().isEmpty ? 'Name is required' : null;
      _emailError = _emailController.text.trim().isEmpty
          ? 'Email is required'
          : (!_emailController.text.contains('@') ? 'Enter a valid email' : null);
      _passwordError = _passwordController.text.isEmpty ? 'Password is required' : null;
      _confirmError = _confirmController.text.isEmpty
          ? 'Please confirm your password'
          : (!_passwordsMatch ? "Passwords don't match" : null);
    });
    return _nameError == null &&
        _emailError == null &&
        _passwordError == null &&
        _confirmError == null;
  }

  Future<void> _handleSignUp() async {
    if (!_validate()) return;
    final auth = AuthProvider.of(context);
    final success = await auth.signup(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
    );
    if (!mounted) return;
    if (success) {
      // Mirrors Next.js: navigate to email verification after signup
      _showSuccess('Account created! Please check your email to verify your account.');
      Navigator.of(context).pushReplacementNamed('/email-verification');
    } else {
      _showError(auth.error ?? 'Registration failed. Please try again.');
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

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.of(context);
    final loading = auth.isLoading;
    final hasPasswordInput = _passwordController.text.isNotEmpty;
    final hasConfirmInput = _confirmController.text.isNotEmpty;

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
                            'Join the Community',
                            style: TextStyle(
                              fontFamily: 'Parkinsans',
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.foreground,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Sign up with',
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
                            'or sign up with email',
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

                    // Name
                    AppTextField(
                      label: 'Name',
                      placeholder: 'Enter Name',
                      controller: _nameController,
                      errorText: _nameError,
                      enabled: !loading,
                    ),
                    const SizedBox(height: 16),

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
                      errorText: _passwordError,
                      enabled: !loading,
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

                    // Password checklist
                    if (hasPasswordInput) ...[
                      const SizedBox(height: 10),
                      Column(
                        children: _rules
                            .map((r) => _PasswordRuleTile(rule: r))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Confirm password
                    AppTextField(
                      label: 'Confirm Password',
                      placeholder: 'Re-enter Password',
                      controller: _confirmController,
                      obscure: !_showConfirm,
                      errorText: _confirmError,
                      enabled: !loading,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: AppColors.mutedForeground,
                        ),
                        onPressed: () =>
                            setState(() => _showConfirm = !_showConfirm),
                      ),
                    ),

                    // Passwords match indicator
                    if (hasConfirmInput) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            _passwordsMatch
                                ? Icons.check_circle
                                : Icons.cancel,
                            size: 14,
                            color: _passwordsMatch
                                ? AppColors.success
                                : AppColors.error,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _passwordsMatch
                                ? 'Passwords match'
                                : "Passwords don't match",
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'Metropolis',
                              color: _passwordsMatch
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Submit
              AppButton(
                label: loading ? 'Creating Account...' : 'Set Up Your Profile',
                loading: loading,
                onPressed: _handleSignUp,
              ),
              const SizedBox(height: 12),

              // Sign in link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Have an account? ',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.mutedForeground),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Sign In',
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

class _PasswordRule {
  final String label;
  final bool met;
  const _PasswordRule(this.label, this.met);
}

class _PasswordRuleTile extends StatelessWidget {
  final _PasswordRule rule;
  const _PasswordRuleTile({required this.rule});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            rule.met ? Icons.check_circle : Icons.circle_outlined,
            size: 14,
            color: rule.met ? AppColors.success : AppColors.mutedForeground,
          ),
          const SizedBox(width: 6),
          Text(
            rule.label,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Metropolis',
              color: rule.met ? AppColors.success : AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
