import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/payment_service.dart';
import '../services/store_purchase_service.dart';
import '../services/webview_support.dart';
import '../theme/app_theme.dart';
import 'cowry_checkout_webview.dart';

// Mirrors TopUpCowriesModal/useCowryCheckout (payments/TopUpCowriesModal.tsx):
// fetches live provider + package pricing (prices and available providers are
// DB-driven and vary by resolved country/currency, not a static client-side
// list), lets the user pick a provider when more than one is available, then
// calls the cowry-payment-initiate Edge Function and opens the returned
// checkout URL in-app (CowryCheckoutScreen) instead of a full page redirect.
// Shared between the AwaQuiz and Profile "Buy Cowries" entry points —
// `returnTo` differs between them and is passed through for parity/logging.
//
// In the iOS/Android builds (when a StorePurchaseService is running) cowries
// are sold through the App Store / Google Play instead, as both stores
// require for virtual currency; Paystack is only offered elsewhere.
class TopUpCowriesModal extends StatefulWidget {
  final String returnTo; // 'awaquiz' | 'profile'
  final StorePurchaseService? storePurchases;
  TopUpCowriesModal({
    super.key,
    required this.returnTo,
    StorePurchaseService? storePurchases,
  }) : storePurchases = storePurchases ?? StorePurchaseService.instance;

  @override
  State<TopUpCowriesModal> createState() => _TopUpCowriesModalState();
}

class _TopUpCowriesModalState extends State<TopUpCowriesModal> {
  // Lazy: only the Paystack path needs it, and it touches Supabase.instance.
  late final _payments = PaymentService();
  bool _loadingOptions = true;
  PaymentOptions? _options;
  String? _optionsError;
  String? _selectedProviderId;
  String? _startingPackageId;
  String? _error;
  List<StoreCowryPackage>? _storePackages;

  StorePurchaseService? get _store => widget.storePurchases;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final store = _store;
    if (store != null) return _loadStorePackages(store);
    setState(() {
      _loadingOptions = true;
      _optionsError = null;
    });
    try {
      final options = await _payments.loadPaymentOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        _selectedProviderId = options.providers.isNotEmpty ? options.providers.first.id : null;
        _loadingOptions = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _optionsError = 'Payment options are unavailable: $e';
          _loadingOptions = false;
        });
      }
    }
  }

  Future<void> _loadStorePackages(StorePurchaseService store) async {
    setState(() {
      _loadingOptions = true;
      _optionsError = null;
    });
    try {
      final packages = await store.loadPackages();
      if (!mounted) return;
      setState(() {
        _storePackages = packages;
        _loadingOptions = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _optionsError = 'Payment options are unavailable: $e';
          _loadingOptions = false;
        });
      }
    }
  }

  Future<void> _buyFromStore(StoreCowryPackage pkg) async {
    setState(() {
      _startingPackageId = pkg.id;
      _error = null;
    });
    final result = await _store!.buy(pkg);
    if (!mounted) return;
    if (result == CowryCheckoutResult.cancelled) {
      setState(() => _startingPackageId = null);
      return;
    }
    if (result == CowryCheckoutResult.failed) {
      setState(() {
        _startingPackageId = null;
        _error = 'Payment could not be completed. Please try again.';
      });
      return;
    }
    Navigator.of(context).pop(result);
  }

  PaymentProviderOption? get _selectedProvider {
    final options = _options;
    if (options == null) return null;
    for (final p in options.providers) {
      if (p.id == _selectedProviderId) return p;
    }
    return options.providers.isNotEmpty ? options.providers.first : null;
  }

  Future<void> _pay(PaymentPackageOption pkg) async {
    final provider = _selectedProvider;
    if (provider == null) return;
    setState(() {
      _startingPackageId = pkg.id;
      _error = null;
    });
    try {
      final checkoutUrl = await _payments.initiateTopUp(
        packageId: pkg.id,
        provider: provider.id,
        currency: _options!.currency,
        returnTo: widget.returnTo,
      );
      if (!mounted) return;
      CowryCheckoutResult? result;
      if (supportsInAppWebView) {
        result = await Navigator.of(context, rootNavigator: true)
            .push<CowryCheckoutResult>(
              MaterialPageRoute(
                builder: (_) => CowryCheckoutScreen(checkoutUrl: checkoutUrl),
              ),
            );
      } else {
        // webview_flutter has no desktop/web implementation — fall back to
        // the external browser there instead of crashing. We can't watch
        // for the callback redirect this way, so the balance only updates
        // on the next natural refresh.
        await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      Navigator.of(context).pop(result ?? CowryCheckoutResult.cancelled);
    } catch (e) {
      if (mounted) {
        setState(() {
          _startingPackageId = null;
          _error = 'Unable to start payment: $e';
        });
      }
    }
  }

  // Mirrors PaymentCatalog's price line (TopUpCowriesModal.tsx:169):
  // "{currency} {amount}" verbatim, not a currency-symbol conversion.
  String _formatAmount(String amount, String currency) => '$currency $amount';

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Top Up your cowries',
                        style: TextStyle(
                          fontFamily: 'Parkinsans',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: c.foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose a cowry package to continue.',
                        style: TextStyle(
                          fontFamily: 'Metropolis',
                          fontSize: 13,
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: c.mutedForeground),
                  onPressed: _startingPackageId != null
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: c.secondary,
                    minimumSize: const Size(28, 28),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loadingOptions)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_optionsError != null) ...[
              Text(
                _optionsError!,
                style: const TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: Color(0xFFDC2626)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadOptions,
                child: const Text('Retry', style: TextStyle(fontFamily: 'Metropolis')),
              ),
            ] else if (_storePackages != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _storePackages!.isEmpty
                      ? 'Top-ups are currently unavailable.'
                      : 'Pay with ${_store!.store.label}',
                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground),
                ),
              ),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 12,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              for (final pkg in _storePackages!)
                _packageRow(
                  c,
                  id: pkg.id,
                  name: pkg.name,
                  cowries: pkg.cowries,
                  price: pkg.price,
                  onTap: () => _buyFromStore(pkg),
                ),
            ] else if (_options!.providers.isEmpty)
              Text(
                'Top-ups are currently unavailable.',
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground),
              )
            else ...[
              if (_options!.providers.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: c.secondary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: _options!.providers.map((provider) {
                        final selected = provider.id == _selectedProviderId;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedProviderId = provider.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: selected ? c.card : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: selected
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6)]
                                    : null,
                              ),
                              child: Text(
                                provider.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Metropolis',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: selected ? c.foreground : c.mutedForeground,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              if (_options!.providers.length == 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Pay with ${_options!.providers.first.label}',
                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground),
                  ),
                ),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 12,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              for (final pkg in _selectedProvider?.packages ?? const <PaymentPackageOption>[])
                _packageRow(
                  c,
                  id: pkg.id,
                  name: pkg.name,
                  cowries: pkg.cowries,
                  price: _formatAmount(pkg.amount, _options!.currency),
                  onTap: () => _pay(pkg),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _packageRow(
    AppColorScheme c, {
    required String id,
    required String name,
    required int cowries,
    required String price,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _startingPackageId != null ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.secondary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: c.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '🐚 $cowries cowries',
                      style: TextStyle(
                        fontFamily: 'Metropolis',
                        fontSize: 12,
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (_startingPackageId == id)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.primary,
                  ),
                )
              else
                Text(
                  price,
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: c.foreground,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
