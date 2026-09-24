import 'package:flutter_test/flutter_test.dart';

import 'desktop_flows.dart' as desktop;
import 'phone_flows.dart' as phone;

/// The single entry point for the integration suite. Flutter launches the
/// macOS app once per test file, and a second launch can fail while the first
/// instance is still shutting down, so every flow runs from this one file.
///
///   flutter test integration_test -d macos
void main() {
  group('desktop layout', desktop.main);
  group('phone layout', phone.main);
}
