import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/main/curator_requests_screen.dart';
import '../screens/main/dictionary_screen.dart';
import '../screens/main/my_word_requests_screen.dart';
import '../screens/main/vote_screen.dart';

// Shared by the notification bell preview and the full notifications list:
// mirrors neolingo's click-through — both NotificationBell.tsx and the full
// notifications page call router.push(notification.link). Flutter has no
// router matching every web path 1:1, so this maps the concrete links
// notifications.ts actually emits onto the equivalent screen; anything else
// (web-only /admin, /manager routes) is a safe no-op.
Future<void> openNotificationLink(
  BuildContext context,
  String? userId,
  String? link,
) async {
  if (link == null || link.isEmpty) return;
  final uri = Uri.tryParse(link);
  if (uri == null) return;
  final path = uri.path;

  if (path == '/curator/requests') {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CuratorRequestsScreen()));
    return;
  }
  if (path == '/dictionary') {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DictionaryScreen()));
    return;
  }
  if (path == '/dictionary/requests') {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyWordRequestsScreen()));
    return;
  }
  if (path.startsWith('/dictionary/request')) {
    Navigator.of(context).pushNamed('/request');
    return;
  }
  if (path == '/profile') {
    Navigator.of(context).pushNamed('/profile');
    return;
  }
  if (path == '/vote') {
    final termId = int.tryParse(uri.queryParameters['termId'] ?? '');
    final isWordOfTheDay = uri.queryParameters.containsKey('wordoftheday');
    if (termId != null && userId != null) {
      final communityLangId = await _resolveCommunityLangId(userId);
      if (!context.mounted) return;
      if (communityLangId != null) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VoteDetailScreen(
            termId: termId,
            communityLangId: communityLangId,
            isWordOfTheDay: isWordOfTheDay,
          ),
        ));
        return;
      }
    }
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VoteScreen()));
  }
  // Any other link (e.g. /admin/*, /manager/*) has no Flutter screen — no-op.
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
