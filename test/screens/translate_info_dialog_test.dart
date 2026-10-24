import 'package:awalingo/screens/main/translate_screen.dart';
import 'package:awalingo/screens/main/vote_screen.dart' show TermWithNeoCount;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/offline_fixture.dart';

void main() {
  late OfflineFixture fixture;

  setUp(() async {
    fixture = OfflineFixture();
    await fixture.initialize();
    fixture.offline = false;
  });
  tearDown(() => fixture.dispose());

  testWidgets('"Got it" closes only the neo type info dialog', (tester) async {
    // SuggestScreen lives in the Menu's nested Navigator in the app, while
    // dialogs open on the root Navigator — reproduce that split here.
    await fixture.mount(
      tester,
      Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SuggestScreen(
                    term: TermWithNeoCount(
                      id: 10,
                      text: 'Alpha',
                      meaning: '',
                      partOfSpeech: '',
                      neoCount: 0,
                      languageId: 1,
                    ),
                    communityLangId: 2,
                    engLangId: 1,
                  ),
                ),
              ),
              child: const Text('Open suggest'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open suggest'));
    await tester.pumpAndSettle();
    expect(find.byType(SuggestScreen), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Popular').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('Got it'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Got it'), findsNothing);
    expect(find.byType(SuggestScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
