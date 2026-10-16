import 'package:integration_test/integration_test.dart';
import '../test/screens/offline_recovery_test.dart' as suite;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suite.offlineRecoveryTests(
    screenshotsOnly: const bool.fromEnvironment('OFFLINE_SCREENSHOTS_ONLY'),
    capture: (tester, name) async {
      // Each screen test may capture both its failure and recovered state.
      if (name.endsWith('-offline')) {
        await binding.convertFlutterSurfaceToImage();
      }
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    },
  );
}
