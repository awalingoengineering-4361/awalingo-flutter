import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/verification/certificate/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
  responseDataCallback: (data) async {
    if (data == null) {
      return;
    }
    for (final entry in data.entries) {
      if (!RegExp(r'^certificate-\d+\.(pdf|png)$').hasMatch(entry.key)) {
        continue;
      }
      final file = File('build/verification/certificate/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(base64Decode(entry.value as String));
    }
  },
);
