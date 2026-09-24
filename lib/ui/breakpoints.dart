import 'dart:ui';

/// Where the phone layout takes over. The desktop layout (board beside a
/// 380px assistant panel) needs roughly 1,000px across and 600px down.
abstract final class Breakpoints {
  static const mobileMaxWidth = 700.0;

  /// Landscape phones are wide but short; they get the phone layout too.
  static const mobileMaxHeight = 500.0;

  static bool isMobile(Size size) => size.width < mobileMaxWidth || size.height < mobileMaxHeight;
}
