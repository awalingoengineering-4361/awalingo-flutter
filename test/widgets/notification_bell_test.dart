import 'dart:async';
import 'dart:convert';

import 'package:awalingo/services/auth_provider.dart';
import 'package:awalingo/services/theme_notifier.dart';
import 'package:awalingo/widgets/mobile_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _SignedInAuth extends AuthNotifier {
  @override
  User get user => User(
    id: 'bell-user',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-10-16T08:00:00Z',
  );
}

void main() {
  notificationBellTests();
}

void notificationBellTests({
  Future<void> Function(WidgetTester)? onPreviewOpened,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _SignedInAuth auth;
  late ThemeNotifier theme;
  Completer<http.Response>? pendingPreview;
  Completer<void>? pendingWrite;
  late List<Map<String, dynamic>> notifications;
  late bool failPreview;
  late bool failWrite;
  late List<http.Request> writes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pendingPreview = null;
    pendingWrite = null;
    failPreview = false;
    failWrite = false;
    writes = [];
    notifications = [
      {
        'id': 1,
        'type': 'SYSTEM',
        'title': 'Welcome to Awalingo',
        'message': 'Your community has news.',
        'link': null,
        'isRead': false,
        'createdAt': '2026-10-16T08:00:00Z',
      },
    ];
    await Supabase.initialize(
      url: 'https://bell.test',
      publishableKey: 'fixture-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/user_target_languages')) {
          return http.Response(
            jsonEncode({
              'language': {'short': 'YR', 'icon': 'NG'},
            }),
            200,
            request: request,
          );
        }
        if (request.url.path.endsWith('/notifications')) {
          if (request.method == 'PATCH') {
            writes.add(request);
            if (pendingWrite != null) await pendingWrite!.future;
            if (failWrite) {
              return http.Response(
                '{"message":"Unavailable","code":"503"}',
                503,
                request: request,
              );
            }
            for (final notification in notifications) {
              notification['isRead'] = true;
            }
            return http.Response('', 204, request: request);
          }
          if (request.url.queryParameters['select'] == 'id') {
            return http.Response(
              jsonEncode(
                notifications
                    .where((n) => n['isRead'] == false)
                    .map((n) => {'id': n['id']})
                    .toList(),
              ),
              200,
              request: request,
            );
          }
          if (pendingPreview != null) {
            final response = await pendingPreview!.future;
            return http.Response(
              response.body,
              response.statusCode,
              request: request,
            );
          }
          if (failPreview) {
            return http.Response(
              '{"message":"Unavailable","code":"503"}',
              503,
              request: request,
            );
          }
          return http.Response(
            jsonEncode(notifications),
            200,
            request: request,
          );
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      }),
    );
    auth = _SignedInAuth();
    theme = ThemeNotifier();
  });

  tearDown(() async {
    auth.dispose();
    theme.dispose();
    await Supabase.instance.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      AuthProvider(
        notifier: auth,
        child: ThemeProvider(
          notifier: theme,
          child: MaterialApp(
            home: const Scaffold(appBar: AppMobileHeader()),
            routes: {
              '/profile': (_) =>
                  const Scaffold(body: Text('Profile destination')),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('bell opens notifications and can be reopened', (tester) async {
    await mount(tester);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Welcome to Awalingo'), findsOneWidget);
      expect(find.text('View all notifications'), findsOneWidget);
      if (attempt == 0 && onPreviewOpened != null) {
        await onPreviewOpened(tester);
      }
      await tester.tapAt(const Offset(5, 550));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing while loading ignores the late preview response', (
    tester,
  ) async {
    await mount(tester);
    pendingPreview = Completer<http.Response>();
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tapAt(const Offset(5, 550));
    await tester.pumpAndSettle();
    pendingPreview!.complete(http.Response('[]', 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed preview shows retry rather than an empty inbox', (
    tester,
  ) async {
    await mount(tester);
    failPreview = true;
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load notifications.'), findsOneWidget);
    expect(find.text('No notifications'), findsNothing);
    failPreview = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Awalingo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mark all read persists and stays read after reopening', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();
    expect(notifications.single['isRead'], isTrue);
    expect(writes.single.url.queryParameters['userId'], 'eq.bell-user');
    expect(find.text('Mark all as read'), findsNothing);
    await tester.tapAt(const Offset(5, 550));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Awalingo'), findsOneWidget);
    expect(find.text('Mark all as read'), findsNothing);
    expect(writes, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed read update keeps unread state and can be retried', (
    tester,
  ) async {
    await mount(tester);
    failWrite = true;
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();
    expect(notifications.single['isRead'], isFalse);
    expect(find.text('Mark all as read'), findsOneWidget);
    expect(find.text('Unable to mark notifications as read.'), findsOneWidget);
    failWrite = false;
    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();
    expect(notifications.single['isRead'], isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'opening a notification persists read state and follows its link',
    (tester) async {
      notifications.single['link'] = '/profile';
      await mount(tester);
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.byIcon(Icons.notifications_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Welcome to Awalingo'));
        await tester.pumpAndSettle();
        expect(find.text('Profile destination'), findsOneWidget);
        expect(notifications.single['isRead'], isTrue);
        expect(writes, hasLength(1));
        expect(writes.single.url.queryParameters['id'], 'eq.1');
        expect(writes.single.url.queryParameters['userId'], 'eq.bell-user');
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('view all opens the full list and can return to the bell', (
    tester,
  ) async {
    await mount(tester);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View all notifications'));
      await tester.pumpAndSettle();
      expect(find.text('1 unread notification'), findsOneWidget);
      expect(find.text('Welcome to Awalingo'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an old load cannot replace a reopened preview', (tester) async {
    await mount(tester);
    final oldLoad = Completer<http.Response>();
    pendingPreview = oldLoad;
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tapAt(const Offset(5, 550));
    await tester.pumpAndSettle();
    pendingPreview = null;
    notifications.single['title'] = 'Latest community news';
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    oldLoad.complete(http.Response('[]', 200));
    await tester.pumpAndSettle();
    expect(find.text('Latest community news'), findsOneWidget);
    expect(find.text('No notifications'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dismissing during a read update cancels later navigation', (
    tester,
  ) async {
    notifications.single['link'] = '/profile';
    await mount(tester);
    pendingWrite = Completer<void>();
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome to Awalingo'));
    await tester.pump();
    expect(writes, hasLength(1));
    await tester.tapAt(const Offset(5, 550));
    // The route is reversing but its widget is still mounted.
    await tester.pump(const Duration(milliseconds: 20));
    pendingWrite!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Profile destination'), findsNothing);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(notifications.single['isRead'], isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
