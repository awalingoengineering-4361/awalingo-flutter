import 'package:integration_test/integration_test.dart';
import '../test/screens/account_deletion_screen_test.dart' as suite;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suite.accountDeletionScreenTests(
    capture: (tester, name) async {
      if (name != 'account-deletion-requested') {
        await binding.convertFlutterSurfaceToImage();
        }
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    },
  );
}
