import 'package:awalingo/services/certificate_fonts.dart';
import 'package:awalingo/services/awaquiz_certificate.dart';
import 'package:awalingo/widgets/awaquiz_certificate_card.dart';
import 'package:awalingo/features/awaquiz/awaquiz_progression.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'certificate labels match completed web stages without a repeated Level',
    () {
      expect(
        [for (var i = 1; i <= 6; i++) certificateStageLabelForSection(i)],
        [
          'JJC (A1 Level)',
          'Sabi Player (A1 Level)',
          'Shugaba (B1 Level)',
          'Odogwu (B1 Level)',
          'Idan (C1 Level)',
          'Ancestor (C1 Level)',
        ],
      );
      expect(certificateStageLabelForSection(0), 'AwaQuiz');
    },
  );
  test('selects script fonts for mixed Arabic, Ethiopic and CJK details', () {
    expect(
      requiredCertificateFallbackAssets('Amina أمينة 李明 አማርኛ العربية 中文'),
      [
        'assets/certificate/Amiri-Regular.ttf',
        'assets/certificate/NotoSansEthiopic-Regular.ttf',
        'assets/certificate/NotoSansCJK-Regular.ttf',
      ],
    );
  });
  test(
    'unsupported characters cannot produce a silently incomplete PDF',
    () async {
      await expectLater(
        buildAwaQuizCertificatePdf(
          language: 'Yorùbá',
          levelLabel: 'JJC (A1 Level)',
          recipientName: 'Awa \uE000',
        ),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'recognition preview retains long accented data at narrow width and large text scale',
    (tester) async {
      const name = 'Adéọlá Ọlúwafẹ́mi Bakare Faid Toluwalope';
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(3)),
            child: Center(
              child: SizedBox(
                width: 280,
                child: AwaQuizCertificateCard(
                  recipientName: name,
                  language: 'Yorùbá',
                  levelLabel: 'JJC (A1 Level)',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('OF RECOGNITION'), findsOneWidget);
      expect(find.text('This is to recognize that'), findsOneWidget);
      expect(find.text(name), findsOneWidget);
      expect(
        find.textContaining('demonstrating commitment', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('OF ACHIEVEMENT'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
