import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../screens/main/become_curator_screen.dart';

// Ports CurateGuardModal.tsx exactly: shown whenever a non-curator tries to
// reach a curate-only surface (the Translate nav tab, or a dictionary
// card's Translate action). "Take Test" routes to BecomeCuratorScreen.
Future<void> showCurateGuardModal(BuildContext context) {
  final c = AppColorScheme.of(context);
  return showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
              child: Icon(Icons.hourglass_top_rounded, size: 44, color: c.primary),
            ),
            const SizedBox(height: 20),
            Text('Curator -in- waiting',
                style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
            const SizedBox(height: 10),
            Text(
              'You are one step away from becoming a curator. Take the test to become Awalingo Curator.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                      foregroundColor: c.foreground,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Go Back', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BecomeCuratorScreen()));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.foreground,
                      foregroundColor: c.background,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: const Text('Take Test', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
