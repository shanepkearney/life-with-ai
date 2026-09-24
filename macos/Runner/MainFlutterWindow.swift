import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Wide enough that the control bar fits on one row beside the assistant
  /// panel (it needs ~1,332pt); 4:3-friendly for the board; and it fits a 13"
  /// MacBook's default 1470x956 screen. integration_test/app_test.dart checks
  /// the one-row claim at this size.
  static let defaultContentSize = NSSize(width: 1440, height: 920)
  static let minimumContentSize = NSSize(width: 1024, height: 700)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.contentMinSize = Self.minimumContentSize

    // Never open larger than the screen's usable area (menu bar and Dock excluded).
    var size = Self.defaultContentSize
    if let visible = (self.screen ?? NSScreen.main)?.visibleFrame {
      let titleBar = self.frame.height - self.contentRect(forFrameRect: self.frame).height
      size.width = min(size.width, visible.width)
      size.height = min(size.height, visible.height - titleBar)
    }
    self.setContentSize(size)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
