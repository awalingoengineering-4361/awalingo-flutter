import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../screens/main/request_screen.dart';
import '../screens/main/my_word_requests_screen.dart';

// Ports WordRequestTabs.tsx exactly: neolingo's /dictionary/request (submit
// form) and /dictionary/requests (history) are two separate pages that both
// render this same nav — not local tab state. Tapping the inactive tab here
// does a real page swap (pushReplacement) between RequestScreen and
// MyWordRequestsScreen, matching the two <Link> hrefs in the original.
class WordRequestTabs extends StatelessWidget {
  final bool activeIsHistory;
  final int? requestCount;

  const WordRequestTabs({
    super.key,
    required this.activeIsHistory,
    this.requestCount,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.secondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Tab(
              label: 'Request a Word',
              active: !activeIsHistory,
              c: c,
              onTap: activeIsHistory
                  ? () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const RequestScreen()))
                  : null,
            ),
          ),
          Expanded(
            child: _Tab(
              label: requestCount != null ? 'My Requests ($requestCount)' : 'My Requests',
              active: activeIsHistory,
              c: c,
              onTap: activeIsHistory
                  ? null
                  : () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const MyWordRequestsScreen())),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final AppColorScheme c;
  final VoidCallback? onTap;
  const _Tab({required this.label, required this.active, required this.c, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? c.card : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Metropolis',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? c.foreground : c.mutedForeground,
          ),
        ),
      ),
    );
  }
}
