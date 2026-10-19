import 'dart:ui' as ui;
import 'package:awalingo/services/certificate_export_service.dart';
import 'package:awalingo/widgets/certificate_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:share_plus/share_plus.dart';
import '../test/widgets/certificate_actions_test.dart' as suite;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suite.certificateActionsTests();

  testWidgets(
    'real certificate PNG and caption can be prepared twice on Android',
    (tester) async {
      final payloads = <ShareParams>[];
      final exporter = CertificateExportService(
        share: (params) async {
          payloads.add(params);
          return const ShareResult('', ShareResultStatus.dismissed);
        },
      );
      const details = CertificateDetails(
        recipientName: 'Ada Learner',
        language: 'Yoruba',
        levelLabel: 'Beginner',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Certificate')),
            body: SingleChildScrollView(
              child: CertificateActions(
                certificate: details,
                exporter: exporter,
              ),
            ),
          ),
        ),
      );
      for (var run = 0; run < 2; run++) {
        await tester.tap(find.text('Share Certificate'));
        await tester.pumpAndSettle();
        expect(payloads, hasLength(run + 1));
        final p = payloads.last;
        final bytes = await p.files!.single.readAsBytes();
        expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThanOrEqualTo(1600));
        expect(frame.image.height, greaterThanOrEqualTo(1100));
        frame.image.dispose();
        codec.dispose();
        expect(p.text, details.message);
        expect(p.sharePositionOrigin!.width, greaterThan(0));
        expect(tester.takeException(), isNull);
        if (run == 0) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      Image.memory(bytes),
                      CertificateActions(
                        certificate: details,
                        exporter: exporter,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await binding.convertFlutterSurfaceToImage();
          await tester.pumpAndSettle();
          await binding.takeScreenshot('certificate-image-sharing');
        }
      }
    },
  );
}
