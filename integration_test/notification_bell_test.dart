import 'package:integration_test/integration_test.dart';
import '../test/widgets/notification_bell_test.dart' as suite;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suite.notificationBellTests(
    onPreviewOpened: (tester) async {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('notification-bell-open');
    },
  );
}
