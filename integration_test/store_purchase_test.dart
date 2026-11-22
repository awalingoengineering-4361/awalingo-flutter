import 'package:awalingo/services/store_purchase_service.dart';
import 'package:integration_test/integration_test.dart';
import '../test/services/store_purchase_service_test.dart' as suite;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suite.modalTests(
    store: CowryStore.googlePlay,
    capture: (tester) async {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('google-play-cowries-checkout');
    },
  );
}
