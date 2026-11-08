import 'dart:typed_data';
import 'package:awalingo/services/certificate_export_service.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'shares PNG alone so image destinations do not receive mixed image and text',
    () async {
      final payloads = <ShareParams>[];
      final exporter = CertificateExportService(
        share: (params) async {
          payloads.add(params);
          return const ShareResult('', ShareResultStatus.dismissed);
        },
      );
      final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      for (final language in ['Yoruba', 'Igbo']) {
        await exporter.shareImage(
          CertificateDetails(
            recipientName: 'Ada',
            language: language,
            levelLabel: 'Beginner',
          ),
          bytes,
          const Rect.fromLTWH(10, 20, 100, 40),
        );
      }
      expect(payloads, hasLength(2));
      for (var i = 0; i < 2; i++) {
        final p = payloads[i];
        expect(p.files, hasLength(1));
        expect(p.files!.single.mimeType, 'image/png');
        expect(await p.files!.single.readAsBytes(), bytes);
        expect(p.fileNameOverrides!.single, endsWith('.png'));
        expect(p.text, isNull);
        expect(p.sharePositionOrigin, const Rect.fromLTWH(10, 20, 100, 40));
      }
    },
  );
}
