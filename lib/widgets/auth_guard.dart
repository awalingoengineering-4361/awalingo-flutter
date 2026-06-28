import 'package:flutter/material.dart';
import '../services/auth_provider.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;

  const AuthGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.of(context);

    if (!auth.isAuthenticated) {
      // Schedule redirect after the current frame to avoid calling Navigator
      // during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/signin',
          (route) => false,
        );
      });
      return const SizedBox.shrink();
    }

    return child;
  }
}
