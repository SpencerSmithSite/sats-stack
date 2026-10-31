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
    observeSceneActivation()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ── Privacy cover ─────────────────────────────────────────────────────────
  //
  // iOS photographs the window as the app leaves the foreground, for the app
  // switcher — the dashboard's balances, the stack, transactions, the AI chat
  // (audit P-1). The window is covered with the launch artwork first, and
  // uncovered on return. Scene notifications, because this is a scene-based
  // app: the app-delegate lifecycle callbacks do not fire for it.

  private var privacyCovers: [UIView] = []

  private func observeSceneActivation() {
    let center = NotificationCenter.default
    center.addObserver(
      forName: UIScene.willDeactivateNotification, object: nil, queue: .main
    ) { [weak self] note in
      self?.cover(note.object as? UIWindowScene)
    }
    center.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.uncover()
    }
  }

  private func cover(_ scene: UIWindowScene?) {
    guard let scene = scene else { return }
    uncover()
    for window in scene.windows {
      let cover = UIView(frame: window.bounds)
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      // #141414, as the launch screen.
      cover.backgroundColor = UIColor(
        red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255, alpha: 1)
      if let image = UIImage(named: "LaunchImage") {
        let artwork = UIImageView(image: image)
        artwork.contentMode = .center
        artwork.frame = cover.bounds
        artwork.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.addSubview(artwork)
      }
      window.addSubview(cover)
      privacyCovers.append(cover)
    }
  }

  private func uncover() {
    privacyCovers.forEach { $0.removeFromSuperview() }
    privacyCovers.removeAll()
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
