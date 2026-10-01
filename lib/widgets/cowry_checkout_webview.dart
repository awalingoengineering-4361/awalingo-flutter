import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';

/// Outcome of a checkout session, parsed from the `payment` query param the
/// web app's callback route redirects to on completion
/// (api/payments/{flutterwave,paystack}/callback/route.ts:
/// `{returnPath}?payment=...`, where returnPath is `/awaquiz` or `/profile`
/// depending on the `returnTo` sent at initiate time — see return-target.ts).
enum CowryCheckoutResult { success, failed, missing, cancelled }

/// Hosts the payment provider's checkout page in an in-app WebView instead of
/// handing off to the system browser, so completing a top-up doesn't leave
/// the app. The whole payment round-trip (checkout → provider →
/// web app's callback route, which verifies + credits cowries, → final
/// redirect back to {expectedPath}?payment=...) happens inside this WebView;
/// we just watch for that final redirect to know when to close it.
class CowryCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;
  final String webBaseUrl;
  // Must match whatever `returnTo` was sent when initiating payment —
  // '/awaquiz' for returnTo: 'awaquiz', '/profile' for returnTo: 'profile'.
  final String expectedPath;
  const CowryCheckoutScreen({
    super.key,
    required this.checkoutUrl,
    required this.webBaseUrl,
    this.expectedPath = '/awaquiz',
  });

  @override
  State<CowryCheckoutScreen> createState() => _CowryCheckoutScreenState();
}

class _CowryCheckoutScreenState extends State<CowryCheckoutScreen> {
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
    if (!url.startsWith(widget.webBaseUrl) || uri.path != widget.expectedPath) return null;
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
