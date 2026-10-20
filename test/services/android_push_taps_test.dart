import 'package:awalingo/services/android_push_taps.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final payload = {
    'v': '1',
    'recipientId': 'A',
    'environment': 'test.supabase.co',
    'messageId': '1',
    'link': '/profile',
  };
  test('cold tap waits for navigation then routes exactly once', () async {
    final links = <String>[];
    final taps = AndroidPushTaps(
      environment: 'test.supabase.co',
      navigate: (link, owner) async => links.add(link),
    );
    taps.setOwner('A');
    await taps.receive(payload);
    expect(links, isEmpty);
    await taps.setReady(true);
    await taps.receive(payload);
    expect(links, ['/profile']);
  });
  test('logout drops queued taps and later login never replays them', () async {
    final links = <String>[];
    final taps = AndroidPushTaps(
      environment: 'test.supabase.co',
      navigate: (link, owner) async => links.add(link),
    );
    taps.setOwner('A');
    await taps.receive(payload);
    taps.setOwner(null);
    taps.setOwner('A');
    await taps.setReady(true);
    expect(links, isEmpty);
  });
  test('wrong account environment or external URI cannot navigate', () async {
    final links = <String>[];
    final taps = AndroidPushTaps(
      environment: 'test.supabase.co',
      navigate: (link, owner) async => links.add(link),
    );
    taps.setOwner('B');
    await taps.setReady(true);
    await taps.receive(payload);
    taps.setOwner('A');
    await taps.receive({...payload, 'environment': 'production.supabase.co'});
    for (final link in [
      'https://evil.test',
      '//evil.test',
      '/\\evil.test',
      '/profile\n',
    ]) {
      await taps.receive({...payload, 'messageId': link, 'link': link});
    }
    expect(links, isEmpty);
    await taps.receive({
      ...payload,
      'messageId': 'unknown',
      'link': '/unsupported',
    });
    expect(links, ['/notifications']);
  });
}
