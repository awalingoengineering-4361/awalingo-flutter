import 'dart:convert';
import 'package:http/http.dart' as http;

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message, {this.needsSignIn = false});
  final String message;
  final bool needsSignIn;
  @override
  String toString() => message;
}

/// Uses the shared website backend; never sends user IDs or privileged keys.
class AccountDeletionService {
  AccountDeletionService({
    required this.origin,
    required this.accessToken,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;
  final String? origin;
  final String? Function() accessToken;
  final http.Client _client;
  final bool _ownsClient;

  Future<void> requestDeletion() async {
    final token = accessToken();
    if (token == null || token.isEmpty) {
      throw const AccountDeletionException(
        'Sign in again to delete your account.',
        needsSignIn: true,
      );
    }
    if (origin == null || origin!.isEmpty) {
      throw const AccountDeletionException(
        'Account deletion is unavailable. Contact privacy@awalingo.com.',
      );
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$origin/api/account/deletion'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'confirmation': 'DELETE'}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 202) {
        final receipt = jsonDecode(response.body);
        if (receipt is Map &&
            receipt['status'] == 'requested' &&
            receipt['requestId'] is String) {
          return;
        }
      }
      if (response.statusCode == 401) {
        throw const AccountDeletionException(
          'Your session is no longer valid. Sign in to delete your account.',
          needsSignIn: true,
        );
      }
      throw const AccountDeletionException(
        'Unable to request account deletion. Please retry.',
      );
    } on AccountDeletionException {
      rethrow;
    } catch (_) {
      throw const AccountDeletionException(
        'We could not confirm your request. Check your connection and retry; retrying will not create another request.',
      );
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
