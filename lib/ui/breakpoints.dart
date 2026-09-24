import 'dart:ui';

/// Where the phone layout takes over. The desktop layout (board beside a
/// 380px assistant panel) needs roughly 1,000px across and 600px down.
abstract final class Breakpoints {
  /// Phones and tablets held upright (an iPad is 744-834 across) get the phone
  /// layout; a tablet on its side (1024+) and the Mac app, whose smallest
  /// window is 1024 wide, keep the desktop one. At 700 the desktop header was
  /// crushed in the gap between.
  static const mobileMaxWidth = 900.0;

  /// Landscape phones are wide but short; they get the phone layout too.
  static const mobileMaxHeight = 500.0;

  static bool isMobile(Size size) => size.width < mobileMaxWidth || size.height < mobileMaxHeight;
}
