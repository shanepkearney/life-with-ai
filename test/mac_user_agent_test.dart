import 'package:flutter_test/flutter_test.dart';
import 'package:life_with_ai/app/platform/mac_user_agent.dart';

void main() {
  const mac = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36';
  const macSafari = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
  const windows = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36';
  const linux = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36';
  const iphone = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

  test('Macs get the download', () {
    expect(looksLikeMac(mac, 0), isTrue);
    expect(looksLikeMac(macSafari, 0), isTrue);
  });

  test("iPads say Macintosh but are touch devices, so they don't", () {
    expect(looksLikeMac(macSafari, 5), isFalse);
  });

  test('nothing else does', () {
    for (final ua in [windows, linux, iphone]) {
      expect(looksLikeMac(ua, 0), isFalse, reason: ua);
    }
  });
}
