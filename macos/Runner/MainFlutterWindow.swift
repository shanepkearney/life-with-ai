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
    registerFullScreenChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Full screen for the app's ⛶ and Board only (lib/app/platform/full_screen_io.dart):
  /// "isFullScreen" and "setFullScreen" from Dart, and "changed" back to it
  /// whenever the window enters or leaves full screen, however that happened
  /// (the green button, ⌃⌘F, Esc).
  private var fullScreenChannel: FlutterMethodChannel?

  private func registerFullScreenChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "life_with_ai/full_screen", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "isFullScreen":
        result(self.styleMask.contains(.fullScreen))
      case "setFullScreen":
        let wanted = (call.arguments as? Bool) ?? false
        if wanted != self.styleMask.contains(.fullScreen) { self.toggleFullScreen(nil) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    fullScreenChannel = channel
    for (name, value) in [(NSWindow.didEnterFullScreenNotification, true), (NSWindow.didExitFullScreenNotification, false)] {
      NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
        self?.fullScreenChannel?.invokeMethod("changed", arguments: value)
      }
    }
  }
}
