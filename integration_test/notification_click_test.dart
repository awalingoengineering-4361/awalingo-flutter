import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/screens/notification_click_test.dart' as list_tests;
import '../test/widgets/notification_bell_test.dart' as bell_tests;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var captures = 0;
  group('notification list', () {
    list_tests.notificationClickTests(
      screenshot: (tester, name) async {
        // The binding restores the Android surface after every test.
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        await binding.takeScreenshot('$name-${++captures}');
      },
    );
  });
  group('notification bell', () => bell_tests.notificationBellTests());
}
