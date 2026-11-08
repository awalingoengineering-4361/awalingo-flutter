import 'dart:convert';
import 'package:awalingo/services/certificate_export_service.dart';
import 'package:awalingo/widgets/awaquiz_certificate_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'recognition preview and real exports use current accented details',
    (tester) async {
      final exporter = CertificateExportService();
      final records = <String, Object>{};
      final fixtures = [
        const CertificateDetails(
          recipientName: 'Bakare Faid Toluwalope',
          language: 'Yorùbá',
          levelLabel: 'JJC (A1 Level)',
        ),
        const CertificateDetails(
          recipientName: 'Adéọlá Ọlúwafẹ́mi Bakare Faid Toluwalope',
          language: 'Èdè Yorùbá àti àṣà ìbílẹ̀',
          levelLabel: 'Ancestor (C1 Level)',
        ),
        const CertificateDetails(
          recipientName: 'Amina أمينة 李明 አማርኛ',
          language: 'العربية 中文',
          levelLabel: 'JJC (A1 Level)',
        ),
      ];
      for (var index = 0; index < fixtures.length; index++) {
        final details = fixtures[index];
        final pdf = await tester.runAsync(() => exporter.createPdf(details));
        final png = await tester.runAsync(() => exporter.createImage(details));
        expect(pdf, isNotNull);
        expect(png, isNotNull);
        records['certificate-$index.pdf'] = base64Encode(pdf!);
        records['certificate-$index.png'] = base64Encode(png!);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: index == 0 ? Brightness.light : Brightness.dark,
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('Certificate verification')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AwaQuizCertificateCard(
                    recipientName: details.recipientName,
                    language: details.language,
                    levelLabel: details.levelLabel,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('OF RECOGNITION'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (index == 0) await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        await binding.takeScreenshot('preview-$index');
      }
      binding.reportData ??= {};
      binding.reportData!.addAll(records);
    },
  );
}
