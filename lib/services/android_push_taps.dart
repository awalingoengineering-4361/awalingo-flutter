class AndroidPushTaps {
  final String environment;
  final Future<void> Function(String link, String owner) navigate;
  String? _owner;
  bool _ready = false;
  Map<String, dynamic>? _pending;
  final Set<String> _consumed = {};
  AndroidPushTaps({required this.environment, required this.navigate});
  void setOwner(String? owner) {
    if (_owner != owner) {
      _pending = null;
      _consumed.clear();
    }
    _owner = owner;
  }

  Future<void> setReady(bool ready) async {
    _ready = ready;
    final pending = _pending;
    if (ready && pending != null) {
      _pending = null;
      await receive(pending);
    }
  }

  Future<void> receive(Map<String, dynamic> payload) async {
    if (_owner == null ||
        payload['recipientId'] != _owner ||
        payload['environment'] != environment ||
        payload['v'] != '1') {
      return;
    }
    final id = payload['messageId'], link = payload['link'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 128 ||
        link is! String ||
        !isSafePushLink(link) ||
        _consumed.contains(id)) {
      return;
    }
    if (!_ready) {
      _pending = Map.of(payload);
      return;
    }
    _consumed.add(id);
    if (_consumed.length > 128) _consumed.remove(_consumed.first);
    await navigate(pushDestination(link), _owner!);
  }
}

bool isSafePushLink(String link) {
  if (link.isEmpty ||
      link.length > 1024 ||
      !link.startsWith('/') ||
      link.startsWith('//') ||
      link.contains('\\') ||
      link.runes.any((rune) => rune <= 32)) {
    return false;
  }
  final uri = Uri.tryParse(link);
  return uri != null && !uri.hasScheme && !uri.hasAuthority && !uri.hasFragment;
}

String pushDestination(String link) {
  final path = Uri.parse(link).path;
  const allowed = [
    '/notifications',
    '/profile',
    '/vote',
    '/dictionary',
    '/dictionary/requests',
    '/curator/requests',
  ];
  return allowed.contains(path) ||
          RegExp(r'^/dictionary/request/[a-zA-Z0-9-]+$').hasMatch(path)
      ? link
      : '/notifications';
}
