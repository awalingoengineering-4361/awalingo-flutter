import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';

class LegalHubScreen extends StatelessWidget {
  const LegalHubScreen({super.key});

  // Replace with your actual deployed web app URL
  static const _baseUrl = 'https://awalingo.com';

  Future<void> _open(BuildContext context, String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open page. Please visit awalingo.com.', style: TextStyle(fontFamily: 'Metropolis')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);

    const items = [
      (icon: Icons.gavel_outlined,      title: 'Terms of Service',    subtitle: 'Rules for using Awalingo',                   path: '/terms'),
      (icon: Icons.privacy_tip_outlined, title: 'Privacy Policy',      subtitle: 'How we collect and use your data',           path: '/terms?tab=privacy'),
      (icon: Icons.help_outline,         title: 'FAQ',                  subtitle: 'Frequently asked questions',                 path: '/faq'),
      (icon: Icons.info_outline,         title: 'About Awalingo',       subtitle: 'Our mission and story',                      path: '/about'),
      (icon: Icons.people_outline,       title: 'Meet the Team',        subtitle: 'The people building Awalingo',               path: '/team'),
      (icon: Icons.mail_outline,         title: 'Contact Support',      subtitle: 'Get help from the Awalingo team',            path: '/about#contact'),
    ];

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: BackButton(color: c.foreground),
        title: Text('Legal Hub', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.border)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final item = items[i];
          return GestureDetector(
            onTap: () => _open(ctx, item.path),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(8)),
                    child: Icon(item.icon, size: 18, color: c.mutedForeground),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.title, style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, fontWeight: FontWeight.w500, color: c.foreground)),
                      const SizedBox(height: 2),
                      Text(item.subtitle, style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
                    ]),
                  ),
                  Icon(Icons.open_in_new, size: 16, color: c.mutedForeground),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
