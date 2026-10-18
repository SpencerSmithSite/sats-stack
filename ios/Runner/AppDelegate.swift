import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications needs this on iOS 10+ or a notification
    // raised while the app is in the foreground is swallowed — which is most
    // of them here, since budget alerts fire off a stream the open app is
    // driving. FlutterAppDelegate implements the delegate protocol itself and
    // forwards to the plugin.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Registered by hand rather than as a pub plugin: it is one file, specific
    // to this app, and wraps a framework that only exists on iOS 26+.
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "FoundationModelsBridge") {
      FoundationModelsBridge.register(with: registrar)
    }

    // Physical memory and free space, so the app can stop offering a 2.1 GB
    // model to a phone that cannot hold it. Dart cannot read either portably;
    // two methods are cheaper than a dependency. macOS does not need this — the
    // Dart side reads `sysctl` and `df` directly there.
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SatsStackDevice") {
      let channel = FlutterMethodChannel(
        name: "app.satsstack/device",
        binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "totalMemoryMb":
          result(Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024)))
        case "freeDiskMb":
          // `volumeAvailableCapacityForImportantUsage` rather than the plain
          // free-space attribute: it reports what iOS will actually let the app
          // have, which accounts for purgeable caches the system will evict.
          // The older key under-reports and would refuse downloads that would
          // in fact succeed.
          let url = URL(fileURLWithPath: NSHomeDirectory())
          if let values = try? url.resourceValues(
               forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
             let bytes = values.volumeAvailableCapacityForImportantUsage {
            result(Int(bytes / (1024 * 1024)))
          } else {
            result(nil)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
