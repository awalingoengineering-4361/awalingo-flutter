import 'package:awalingo/services/certificate_export_service.dart';
import 'package:awalingo/widgets/certificate_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:share_plus/share_plus.dart';

/// This device check requires dismissing the native chooser twice with Back.
/// Never select a recipient or send the fixture certificate.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native certificate chooser can be dismissed and reopened', (
    tester,
  ) async {
    var opened = 0;
    var closed = 0;
    final exporter = CertificateExportService(
      share: (params) async {
        debugPrint('CERTIFICATE_NATIVE_SHARE_OPEN_${++opened}');
        try {
          return await SharePlus.instance.share(params);
        } finally {
          debugPrint('CERTIFICATE_NATIVE_SHARE_CLOSED_${++closed}');
        }
      },
    );
    const details = CertificateDetails(
      recipientName: 'Ada Learner',
      language: 'Yoruba',
      levelLabel: 'Beginner',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Preparing certificate...'))),
      ),
    );
    final png = await exporter.createImage(details);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Certificate')),
          body: SingleChildScrollView(
            child: Column(
              children: [
                Image.memory(png),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: CertificateActions(
                    certificate: details,
                    exporter: exporter,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var run = 1; run <= 2; run++) {
      await tester.ensureVisible(find.text('Share Certificate'));
      await tester.tap(find.text('Share Certificate'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(minutes: 2),
      );
      expect(opened, run);
      expect(closed, run);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
      expect(find.byType(SnackBar), findsNothing);
    }
  });
}
