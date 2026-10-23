import 'dart:async';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final adb =
      Platform.environment['AWALINGO_ADB_BIN'] ??
      '${Platform.environment['HOME']}/Library/Android/sdk/platform-tools/adb';
  final directory = Directory('build/verification/android-push');
  await directory.create(recursive: true);
  var finished = false, prompts = 0;
  final permissions = () async {
    while (!finished && prompts < 2) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final dump = await Process.run(adb, [
        'shell',
        'uiautomator',
        'dump',
        '/sdcard/awalingo-push-permission.xml',
      ]);
      if (dump.exitCode != 0 || finished || prompts >= 2) continue;
      final xml = await Process.run(adb, [
        'shell',
        'cat',
        '/sdcard/awalingo-push-permission.xml',
      ]);
      final id = prompts == 0
          ? 'permission_deny_button'
          : 'permission_allow_button';
      final node = RegExp(
        'resource-id="com.android.permissioncontroller:id/$id"[^>]*bounds="\\[(\\d+),(\\d+)\\]\\[(\\d+),(\\d+)\\]"',
      ).firstMatch(xml.stdout.toString());
      if (node == null) continue;
      final shot = await Process.run(adb, [
        'exec-out',
        'screencap',
        '-p',
      ], stdoutEncoding: null);
      await File(
        '${directory.path}/permission-${prompts == 0 ? 'deny' : 'allow'}.png',
      ).writeAsBytes(shot.stdout as List<int>);
      final x = (int.parse(node[1]!) + int.parse(node[3]!)) ~/ 2,
          y = (int.parse(node[2]!) + int.parse(node[4]!)) ~/ 2;
      await Process.run(adb, ['shell', 'input', 'tap', '$x', '$y']);
      prompts++;
    }
  }();
  try {
    await integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        await File('${directory.path}/$name.png').writeAsBytes(bytes);
        return true;
      },
    );
  } finally {
    finished = true;
    await permissions;
  }
}
