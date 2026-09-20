import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// webview_flutter only ships iOS and Android platform implementations —
/// there is none for desktop (macOS/Windows/Linux) or plain web, so
/// constructing a WebViewController on those platforms throws "A platform
/// implementation for `webview_flutter` has not been set." Anything that
/// hosts a page in-app should check this first and fall back to launching
/// the URL externally instead.
bool get supportsInAppWebView =>
    !kIsWeb && (Platform.isIOS || Platform.isAndroid);
