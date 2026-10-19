import 'package:integration_test/integration_test.dart';
import '../test/screens/curator_menu_refresh_test.dart' as suite;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suite.curatorMenuRefreshTests(
    capture: (tester, name) async {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    },
  );
}
