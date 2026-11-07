import 'package:integration_test/integration_test.dart';
import '../test/widgets/remote_account_lifecycle_test.dart' as suite;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suite.remoteAccountLifecycleTests(
    capture: (tester) async {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('remote-account-signed-out');
    },
  );
}
