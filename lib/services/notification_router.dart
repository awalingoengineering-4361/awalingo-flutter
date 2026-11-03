import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/main/curator_requests_screen.dart';
import '../screens/main/notifications_screen.dart';
import '../screens/main/notification_detail_screen.dart';
import '../screens/main/dictionary_screen.dart';
import '../screens/main/my_word_requests_screen.dart';
import '../screens/main/vote_screen.dart';

// Shared by the notification bell preview and the full notifications list:
// mirrors neolingo's click-through — both NotificationBell.tsx and the full
// notifications page call router.push(notification.link). Flutter has no
// router matching every web path 1:1, so this maps the concrete links
// notifications.ts actually emits onto the equivalent screen; anything else
// returns false so record-aware callers can display the complete notification.
Future<bool> openNotificationLink(
  BuildContext context,
  String? userId,
  String? link, {
  bool Function()? canNavigate,
}) async {
  if (canNavigate?.call() == false) return false;
  if (link == null || link.isEmpty) return false;
  final uri = Uri.tryParse(link);
  if (uri == null) return false;
  final path = uri.path;

  if (path == '/notifications') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    return true;
  }
  if (path == '/curator/requests') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CuratorRequestsScreen()));
    return true;
  }
  if (path == '/dictionary') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DictionaryScreen()));
    return true;
  }
  if (path == '/dictionary/requests') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MyWordRequestsScreen()));
    return true;
  }
  if (path.startsWith('/dictionary/request')) {
    Navigator.of(context).pushNamed('/request');
    return true;
  }
  if (path == '/profile') {
    Navigator.of(context).pushNamed('/profile');
    return true;
  }
  if (path == '/vote') {
    final termId = int.tryParse(uri.queryParameters['termId'] ?? '');
    final isWordOfTheDay = uri.queryParameters.containsKey('wordoftheday');
    if (termId != null && userId != null) {
      final communityLangId = await _resolveCommunityLangId(userId);
      if (!context.mounted || canNavigate?.call() == false) return false;
      if (communityLangId != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VoteDetailScreen(
              termId: termId,
              communityLangId: communityLangId,
              isWordOfTheDay: isWordOfTheDay,
            ),
          ),
        );
        return true;
      }
    }
    if (!context.mounted || canNavigate?.call() == false) return false;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const VoteScreen()));
    return true;
  }
  // Any other link has no Flutter screen.
  return false;
}

/// Opens a record's destination, or its full message rather than another list.
Future<void> openAppNotification(
  BuildContext context,
  String userId,
  AppNotification notification, {
  bool Function()? canNavigate,
}) async {
  if (!context.mounted || canNavigate?.call() == false) return;
  final path = Uri.tryParse(notification.link ?? '')?.path;
  if (path != '/notifications') {
    final handled = await openNotificationLink(
      context,
      userId,
      notification.link,
      canNavigate: canNavigate,
    );
    if (handled) return;
  }
  if (!context.mounted || canNavigate?.call() == false) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          NotificationDetailScreen(notification: notification, ownerId: userId),
    ),
  );
}

Future<int?> _resolveCommunityLangId(String userId) async {
  try {
    final row = await Supabase.instance.client
        .from('user_target_languages')
        .select('languageId')
        .eq('userId', userId)
        .maybeSingle();
    return row?['languageId'] as int?;
  } catch (_) {
    return null;
  }
}
