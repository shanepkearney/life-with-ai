import 'package:web/web.dart' as web;

import 'mac_user_agent.dart';

/// A browser on a Mac: see [looksLikeMac].
bool get isMacBrowser => looksLikeMac(web.window.navigator.userAgent, web.window.navigator.maxTouchPoints);
