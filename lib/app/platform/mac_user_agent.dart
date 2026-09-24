/// Whether a browser with this [userAgent] runs on a Mac, i.e. could run the
/// macOS app. iPads also say "Macintosh" (they ask for desktop sites), but
/// they're touch devices ([maxTouchPoints] > 1) and can't.
bool looksLikeMac(String userAgent, int maxTouchPoints) => userAgent.contains('Macintosh') && maxTouchPoints <= 1;
