import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import 'notifications_screen.dart';

/// Shows the complete item when a notification has no native destination.
class NotificationDetailScreen extends StatelessWidget {
  const NotificationDetailScreen({
    super.key,
    required this.notification,
    required this.ownerId,
  });

  final AppNotification notification;
  final String ownerId;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorScheme.of(context);
    final date = notification.createdAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final timestamp =
        '${localizations.formatMediumDate(date)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.card,
        foregroundColor: colors.foreground,
        title: Text(
          'Notification',
          style: TextStyle(
            fontFamily: 'Parkinsans',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colors.foreground,
          ),
        ),
      ),
      body: AuthProvider.of(context).user?.id != ownerId
          ? const Center(
              child: Text('This notification is no longer available.'),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timestamp,
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 12,
                        color: colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SelectableText(
                      notification.message,
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 14,
                        height: 1.5,
                        color: colors.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
