import 'dart:async';
import 'dart:convert';
import 'package:awalingo/screens/main/notifications_screen.dart';
import 'package:awalingo/services/auth_provider.dart';
import 'package:awalingo/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Auth extends AuthNotifier {
  String owner = 'notification-owner';
  @override
  User get user => User(
    id: owner,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-11-03',
  );
  void switchOwner([String next = 'another-owner']) {
    owner = next;
    notifyListeners();
  }
}

void main() => notificationClickTests();

void notificationClickTests({
  Future<void> Function(WidgetTester tester, String name)? screenshot,
}) {
  late _Auth auth;
  late Map<String, dynamic> notification;
  late List<http.Request> writes;
  Completer<void>? pendingWrite;
  var failWrite = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pendingWrite = null;
    failWrite = false;
    writes = [];
    notification = {
      'id': 101,
      'type': 'SYSTEM',
      'title': 'Community announcement',
      'message': 'Read the full update about your community here.',
      'link': '/notifications',
      'isRead': false,
      'createdAt': '2026-11-03T08:00:00Z',
    };
    await Supabase.initialize(
      url: 'https://notification.test',
      publishableKey: 'fixture-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.method == 'PATCH') {
          writes.add(request);
          await pendingWrite?.future;
          if (failWrite) {
            return http.Response(
              '{"message":"Try later"}',
              500,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          notification['isRead'] = true;
          return http.Response('', 204, request: request);
        }
        return http.Response(
          jsonEncode(
            request.url.queryParameters['userId'] == 'eq.notification-owner'
                ? [notification]
                : [],
          ),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    auth = _Auth();
  });
  tearDown(() async {
    auth.dispose();
    await Supabase.instance.dispose();
  });
  Future<void> mount(WidgetTester tester, {bool dark = false}) async {
    await tester.pumpWidget(
      AuthProvider(
        notifier: auth,
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: const NotificationsScreen(),
          routes: {
            '/profile': (_) => const Scaffold(body: Text('Profile item')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  for (final link in ['/notifications', null, '/contributor']) {
    testWidgets(
      'notification $link opens its full item twice without duplicating reads',
      (tester) async {
        notification['link'] = link;
        await mount(tester);
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.text('Community announcement'));
          await tester.pumpAndSettle();
          expect(find.text('Notification'), findsOneWidget);
          expect(find.text(notification['message'] as String), findsOneWidget);
          expect(find.byType(NotificationsScreen), findsNothing);
          expect(notification['isRead'], isTrue);
          expect(writes, hasLength(1));
          expect(writes.single.url.queryParameters['id'], 'eq.101');
          expect(
            writes.single.url.queryParameters['userId'],
            'eq.notification-owner',
          );
          if (i == 0 && screenshot != null) {
            await screenshot(tester, 'notification-details');
          }
          await close(tester);
        }
        expect(find.byType(NotificationsScreen), findsOneWidget);
        expect(find.text('1 unread notification'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('long notification message remains readable in dark mode', (
    tester,
  ) async {
    notification['message'] = List.filled(
      30,
      'Community update with complete details.',
    ).join('\n');
    await mount(tester, dark: true);
    await tester.tap(find.text('Community announcement'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      notification['message'],
    );
    expect(
      Theme.of(tester.element(find.byType(SelectableText))).brightness,
      Brightness.dark,
    );
    if (screenshot != null) {
      await screenshot(tester, 'notification-details-dark-long');
    }
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await close(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'linked item opens repeatedly without rewriting an already read notification',
    (tester) async {
      notification['link'] = '/profile';
      await mount(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Community announcement'));
        await tester.pumpAndSettle();
        expect(find.text('Profile item'), findsOneWidget);
        expect(writes, hasLength(1));
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('failed read stays unread and can retry opening the item', (
    tester,
  ) async {
    await mount(tester);
    failWrite = true;
    await tester.tap(find.text('Community announcement'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to open notification. Please retry.'),
      findsOneWidget,
    );
    expect(find.text('1 unread notification'), findsOneWidget);
    expect(notification['isRead'], isFalse);
    expect(tester.takeException(), isNull);
    failWrite = false;
    await tester.tap(find.text('Community announcement'));
    await tester.pumpAndSettle();
    expect(find.text('Notification'), findsOneWidget);
    expect(notification['isRead'], isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('changing account hides an already opened notification message', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Community announcement'));
    await tester.pumpAndSettle();
    auth.switchOwner();
    await tester.pumpAndSettle();
    expect(find.text(notification['message'] as String), findsNothing);
    expect(
      find.text('This notification is no longer available.'),
      findsOneWidget,
    );
    await close(tester);
    expect(find.text('Community announcement'), findsNothing);
    expect(find.text('No notifications'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching away and back cannot revive a pending open', (
    tester,
  ) async {
    await mount(tester);
    pendingWrite = Completer<void>();
    await tester.tap(find.text('Community announcement'));
    await tester.pump();
    auth.switchOwner();
    await tester.pumpAndSettle();
    auth.switchOwner('notification-owner');
    await tester.pumpAndSettle();
    pendingWrite!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Notification'), findsNothing);
    expect(writes, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  for (final switchAccount in [false, true]) {
    testWidgets(
      'pending open cancels on ${switchAccount ? 'account change' : 'leaving the source'}',
      (tester) async {
        await mount(tester);
        pendingWrite = Completer<void>();
        await tester.tap(find.text('Community announcement'));
        await tester.pump();
        await tester.tap(find.text('Community announcement'));
        await tester.pump();
        expect(writes, hasLength(1));
        if (switchAccount) {
          auth.switchOwner();
          await tester.pump();
        } else {
          await tester.pumpWidget(const SizedBox());
        }
        pendingWrite!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Notification'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
