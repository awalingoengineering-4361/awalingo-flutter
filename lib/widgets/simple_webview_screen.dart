import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';

/// Hosts a plain read-only web page in-app instead of handing off to the
/// system browser — same reasoning as CowryCheckoutScreen, just without a
/// result to watch for (e.g. Profile's "Legal Hub" link to the web app's
/// /legal page).
class SimpleWebViewScreen extends StatefulWidget {
  final String url;
  final String title;
  const SimpleWebViewScreen({super.key, required this.url, required this.title});

  @override
  State<SimpleWebViewScreen> createState() => _SimpleWebViewScreenState();
}

class _SimpleWebViewScreenState extends State<SimpleWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.foreground),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title,
            style: TextStyle(fontFamily: 'Parkinsans', fontSize: 16, fontWeight: FontWeight.w600, color: c.foreground)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _loading
              ? LinearProgressIndicator(minHeight: 2, color: c.primary, backgroundColor: c.border)
              : const SizedBox(height: 2),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
