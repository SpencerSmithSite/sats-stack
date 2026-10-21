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
  }
}
