import 'dart:async';
import 'package:http/http.dart' as http;

/// User-facing feedback for a failed read, never the transport's raw message.
class LoadFailure {
  final bool isOffline;

  const LoadFailure._(this.isOffline);

  factory LoadFailure.fromError(Object error) =>
      LoadFailure._(error is http.ClientException || error is TimeoutException);

  String get title => isOffline ? 'You are offline' : 'Unable to load';

  String get message => isOffline
      ? 'Please check your internet connection and reconnect with your mother tongue community.'
      : 'Please try again.';
}
