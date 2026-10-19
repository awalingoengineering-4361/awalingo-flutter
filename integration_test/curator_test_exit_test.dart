import 'package:integration_test/integration_test.dart';
import '../test/screens/curator_test_exit_test.dart' as suite;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suite.curatorTestExitTests(
    // The ten-minute timeout race uses the widget-test virtual clock.
    runClockTests: false,
    capture: (tester, name) async {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    },
  );
}
