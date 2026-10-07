import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';

/// Outcome of a checkout session, parsed from the `payment` query param the
/// cowry-payment-callback Edge Function redirects to on completion
/// (supabase/functions/cowry-payment-callback: `.../complete?payment=...`).
enum CowryCheckoutResult { success, failed, missing, cancelled }

/// Hosts the payment provider's checkout page in an in-app WebView instead of
/// handing off to the system browser, so completing a top-up doesn't leave
/// the app. The whole payment round-trip (checkout → provider →
/// cowry-payment-callback Edge Function, which verifies + credits cowries,
/// → final redirect to a fixed .../complete?payment=... URL) happens inside
/// this WebView; we just watch for that final redirect to know when to close
/// it. onNavigationRequest intercepts and *prevents* that navigation before
/// it ever reaches the network, so the completion URL never actually needs
/// to load anything.
class CowryCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;
  const CowryCheckoutScreen({super.key, required this.checkoutUrl});

  @override
  State<CowryCheckoutScreen> createState() => _CowryCheckoutScreenState();
}

class _CowryCheckoutScreenState extends State<CowryCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  late final String _completeUrl =
      '${dotenv.env['SUPABASE_URL'] ?? ''}/functions/v1/cowry-payment-callback/complete';

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
        onNavigationRequest: (request) {
          final result = _resultFor(request.url);
          if (result != null) {
            Navigator.of(context).pop(result);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  CowryCheckoutResult? _resultFor(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (!url.startsWith(_completeUrl)) return null;
    switch (uri.queryParameters['payment']) {
      case 'success':
        return CowryCheckoutResult.success;
      case 'failed':
        return CowryCheckoutResult.failed;
      case 'missing':
        return CowryCheckoutResult.missing;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(CowryCheckoutResult.cancelled);
      },
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.card,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.close, color: c.foreground),
            onPressed: () => Navigator.of(context).pop(CowryCheckoutResult.cancelled),
          ),
          title: Text('Complete Payment',
              style: TextStyle(fontFamily: 'Parkinsans', fontSize: 16, fontWeight: FontWeight.w600, color: c.foreground)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _loading
                ? LinearProgressIndicator(minHeight: 2, color: c.primary, backgroundColor: c.border)
                : const SizedBox(height: 2),
          ),
        ),
        body: WebViewWidget(controller: _controller),
      ),
    );
  }
}
