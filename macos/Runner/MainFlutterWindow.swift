import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Set mobile-like aspect ratio
    let mobileFrame = NSRect(x: self.frame.origin.x, y: self.frame.origin.y, width: 400, height: 800)
    self.setFrame(mobileFrame, display: true)
    self.title = "Head Copy"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
