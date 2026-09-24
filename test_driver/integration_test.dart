// The host side of `flutter drive` for the web tests: it just collects the
// results that integration_test/web_flows.dart reports from the browser.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
