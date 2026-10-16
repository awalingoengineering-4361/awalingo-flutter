import 'package:flutter/material.dart';
import '../services/load_failure.dart';
import '../theme/app_theme.dart';

class LoadFailureView extends StatelessWidget {
  final LoadFailure failure;
  final VoidCallback onRetry;
  final bool compact;

  const LoadFailureView({
    super.key,
    required this.failure,
    required this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final card = Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: EdgeInsets.all(compact ? 16 : 24),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failure.isOffline ? Icons.cloud_off_outlined : Icons.error_outline,
            size: 36,
            color: c.mutedForeground,
          ),
          const SizedBox(height: 16),
          Text(
            failure.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Parkinsans',
              fontWeight: FontWeight.w600,
              fontSize: 20,
              color: c.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            failure.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Metropolis',
              fontSize: 14,
              color: c.mutedForeground,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.foreground,
              side: BorderSide(color: c.border),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
    if (compact) return card;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: card,
      ),
    );
  }
}
