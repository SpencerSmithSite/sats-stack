import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Apple Intelligence. Registered here rather than in AppDelegate because on
    // macOS the FlutterViewController is the plugin registry, and it only
    // exists once the window has been built.
    //
    // Leaving this out is half of the bug that makes a Mac with Apple
    // Intelligence report "no built-in model": the Dart gate has to allow
    // macOS *and* this registration has to happen. Both had to be wrong for the
    // symptom to appear, so both have to be right.
    // Non-optional on macOS, unlike the iOS registry's equivalent — so this is
    // a plain call rather than the `if let` the iOS side needs.
    let registrar = flutterViewController.registrar(
      forPlugin: "FoundationModelsBridge")
    FoundationModelsBridge.register(with: registrar)

    super.awakeFromNib()
  }
}
