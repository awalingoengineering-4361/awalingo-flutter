import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

// Mirrors COWRY_PACKAGE_DEFINITIONS (lib/cowry-payments.ts) — the package
// catalog (id/name/cowries) is a fixed list on web too, not DB-driven; only
// the price per currency is.
class _CowryPackageDefinition {
  final String id;
  final String name;
  final int cowries;
  const _CowryPackageDefinition(this.id, this.name, this.cowries);
}

const List<_CowryPackageDefinition> _kCowryPackageDefinitions = [
  _CowryPackageDefinition('copper-50', 'Copper', 50),
  _CowryPackageDefinition('silver-100', 'Silver', 100),
  _CowryPackageDefinition('gold-500', 'Gold', 500),
  _CowryPackageDefinition('diamond-1000', 'Diamond', 1000),
];

// Mirrors the registered provider adapters (lib/payments/flutterwave.ts,
// lib/payments/paystack.ts) — id/label/supportedCurrencies/minimumAmounts
// are static there too. What we can't replicate is PAYMENT_PROVIDERS env
// ordering or adapter.isConfigured() (server-side secret presence), since
// that's runtime config on the web deployment this app never sees. A
// provider listed here but not actually configured server-side will still
// fail at the (separate, still web-only) checkout-initiation step.
class _ProviderDefinition {
  final String id;
  final String label;
  final List<String> supportedCurrencies;
  final Map<String, String> minimumAmounts;
  const _ProviderDefinition(
    this.id,
    this.label,
    this.supportedCurrencies,
    this.minimumAmounts,
  );
}

const List<_ProviderDefinition> _kProviderDefinitions = [
  _ProviderDefinition('FLUTTERWAVE', 'Flutterwave', ['NGN'], {'NGN': '0.01'}),
  _ProviderDefinition(
    'PAYSTACK',
    'Paystack',
    ['NGN', 'USD'],
    {'NGN': '50.00', 'USD': '2.00'},
  ),
];

// Mirrors PaymentPackageOption/PaymentOptionsResponse (payments/contracts.ts).
class PaymentPackageOption {
  final String id;
  final String name;
  final int cowries;
  final String amount; // decimal string, e.g. "750.00"
  const PaymentPackageOption({
    required this.id,
    required this.name,
    required this.cowries,
    required this.amount,
  });

  factory PaymentPackageOption.fromJson(Map<String, dynamic> json) =>
      PaymentPackageOption(
        id: json['id'] as String,
        name: json['name'] as String,
        cowries: json['cowries'] as int,
        amount: json['amount'] as String,
      );
}

class PaymentProviderOption {
  final String id; // 'FLUTTERWAVE' | 'PAYSTACK'
  final String label;
  final List<PaymentPackageOption> packages;
  const PaymentProviderOption({
    required this.id,
    required this.label,
    required this.packages,
  });

  factory PaymentProviderOption.fromJson(Map<String, dynamic> json) =>
      PaymentProviderOption(
        id: json['id'] as String,
        label: json['label'] as String,
        packages: (json['packages'] as List)
            .map((p) => PaymentPackageOption.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

class PaymentOptions {
  final String countryCode;
  final String currency;
  final List<PaymentProviderOption> providers;
  const PaymentOptions({
    required this.countryCode,
    required this.currency,
    required this.providers,
  });

  factory PaymentOptions.fromJson(Map<String, dynamic> json) => PaymentOptions(
    countryCode: json['countryCode'] as String,
    currency: json['currency'] as String,
    providers: (json['providers'] as List)
        .map((p) => PaymentProviderOption.fromJson(p as Map<String, dynamic>))
        .toList(),
  );
}

/// Shared by the AwaQuiz and Profile "Buy Cowries" entry points — both talk
/// to the same Supabase Edge Functions (cowry-payment-initiate,
/// cowry-payment-callback), differing only in the `returnTo` value passed
/// through to the provider for logging/parity with the web app.
class PaymentService {
  final SupabaseClient _db = Supabase.instance.client;

  Map<String, String> _authHeaders() {
    final token = _db.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Not authenticated');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Mirrors loadPaymentOptions/buildPaymentOptions (lib/payments/catalog.ts),
  // reading straight from Supabase instead of going through
  // /api/payments/options — that route only ever authenticates via browser
  // cookie (getCurrentUser(), web-only) and rejects every mobile request
  // with a 401, and that's web server code this app can't change. Pricing
  // itself (cowry_package_prices) is ordinary catalog data, so reading it
  // directly here keeps this app's only remaining web dependency to the
  // part that actually requires a server holding provider secret keys:
  // initiateTopUp() below.
  //
  // One deliberate deviation from web: country (→ currency) is resolved
  // there from an edge IP-geolocation header (x-vercel-ip-country /
  // cf-ipcountry) added to every request by Vercel/Cloudflare. A native HTTP
  // client never receives that header itself, so this does the equivalent
  // IP lookup client-side via a small geolocation API instead — the device's
  // locale region is NOT a safe substitute here (it's a language/region
  // *setting*, unrelated to the device's actual location; a user physically
  // in Nigeria can easily have an English (UK) locale), so it's only used
  // as a last-resort fallback if the network lookup fails outright.
  Future<String> _resolveCountryCode() async {
    try {
      final response = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final code = data['country_code'] as String?;
        if (code != null && code.isNotEmpty) {
          debugPrint('resolveCountryCode: ip lookup -> $code');
          return code.toUpperCase();
        }
      }
      debugPrint(
        'resolveCountryCode: ip lookup bad response ${response.statusCode} ${response.body}',
      );
    } catch (e) {
      debugPrint('resolveCountryCode: ip lookup failed: $e');
    }
    final fallback =
        PlatformDispatcher.instance.locale.countryCode?.toUpperCase() ?? 'ZZ';
    debugPrint('resolveCountryCode: falling back to locale -> $fallback');
    return fallback;
  }

  Future<PaymentOptions> loadPaymentOptions() async {
    final countryCode = await _resolveCountryCode();
    final currency = countryCode == 'NG' ? 'NGN' : 'USD';

    final rows = await _db
        .from('cowry_package_prices')
        .select('packageId, currency, amount, enabled')
        .eq('currency', currency)
        .eq('enabled', true)
        .order('id');
    debugPrint(
      'loadPaymentOptions: countryCode=$countryCode currency=$currency rows=${rows.length} $rows',
    );

    final pricesByPackageId = <String, double>{
      for (final row in rows)
        row['packageId'] as String: double.parse(row['amount'].toString()),
    };

    final providers = <PaymentProviderOption>[];
    for (final provider in _kProviderDefinitions) {
      if (!provider.supportedCurrencies.contains(currency)) continue;
      final minimum = double.tryParse(provider.minimumAmounts[currency] ?? '');

      final packages = <PaymentPackageOption>[];
      for (final def in _kCowryPackageDefinitions) {
        final amount = pricesByPackageId[def.id];
        if (amount == null) continue;
        if (minimum != null && amount < minimum) continue;
        packages.add(PaymentPackageOption(
          id: def.id,
          name: def.name,
          cowries: def.cowries,
          amount: amount.toStringAsFixed(2),
        ));
      }
      if (packages.isEmpty) continue;
      providers.add(PaymentProviderOption(
        id: provider.id,
        label: provider.label,
        packages: packages,
      ));
    }

    return PaymentOptions(
      countryCode: countryCode,
      currency: currency,
      providers: providers,
    );
  }

  // Mirrors handleTopUp (awaquiz/page.tsx) / useCowryCheckout, but calls this
  // app's own `cowry-payment-initiate` Supabase Edge Function instead of the
  // web app's /api/payments/initiate route — that route depends on a
  // separate deployment this app has no visibility into; the Edge Function
  // lives in the same Supabase project as everything else this app talks to
  // and holds the provider secret keys itself. Auth is the same Supabase
  // access token already used everywhere else in this app.
  //
  // `currency` must be passed through explicitly (from the same
  // loadPaymentOptions() call that priced the package) because the Edge
  // Function runtime has no equivalent of the Vercel/Cloudflare
  // IP-geolocation header the web app's route derives currency from.
  Future<String> initiateTopUp({
    required String packageId,
    required String provider,
    required String currency,
    required String returnTo, // 'awaquiz' | 'profile'
  }) async {
    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final response = await http.post(
      Uri.parse('$supabaseUrl/functions/v1/cowry-payment-initiate'),
      headers: _authHeaders(),
      body: jsonEncode({
        'attemptKey': const Uuid().v4(),
        'packageId': packageId,
        'provider': provider,
        'currency': currency,
        'returnTo': returnTo,
      }),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final checkoutUrl = data['checkoutUrl'] as String?;
    if (response.statusCode != 200 || checkoutUrl == null) {
      throw Exception(data['error'] as String? ?? 'Unable to start payment (${response.statusCode}).');
    }
    return checkoutUrl;
  }
}
