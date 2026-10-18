import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../shared/utils/currency_utils.dart';

/// Wraps [FlutterLocalNotificationsPlugin] and provides budget-specific
/// notification helpers.
///
/// Uses a per-session in-memory set to avoid firing the same notification
/// repeatedly while the app is open. On the next cold start the set is empty
/// again, so stale-but-still-relevant alerts reappear (once) as a reminder.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  /// Notification IDs already shown this session.
  final _shown = <int>{};

  bool _initialized = false;

  /// Permission is asked for once, on the first notification, rather than on
  /// every one. Null until asked.
  bool? _permissionGranted;

  /// Budget IDs start above this so they cannot collide with
  /// [_stackGoalId]: `categoryId * 2 + 1` hit 9999 exactly at category 4999,
  /// which would have silently replaced the goal notification.
  static const _budgetIdBase = 100000;
  static const _stackGoalId = 9999;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      await _plugin.initialize(
        const InitializationSettings(
          // iOS was missing entirely, so on the TestFlight build the plugin
          // was never configured for it: no permission was ever requested and
          // no budget or stack-goal notification could appear at all.
          iOS: DarwinInitializationSettings(
            // Asked on the first notification instead of at launch — a
            // permission prompt during onboarding, before the user has set a
            // single budget, is the one most people decline.
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _initialized = true;
    } catch (_) {}
  }

  // ── Budget alerts ──────────────────────────────────────────────────────────

  /// Fires a warning notification when a budget reaches ≥ 80 %.
  /// Silent if already shown this session.
  Future<void> showBudgetWarning({
    required int categoryId,
    required String categoryName,
    required int percentUsed,
    required double budgetAmount,
    required String currency,
  }) async {
    final id = _budgetIdBase + categoryId * 2;
    if (_shown.contains(id)) return;
    _shown.add(id);

    final budgetStr =
        CurrencyUtils.format(budgetAmount, currency, decimalDigits: 0);
    await _show(
      id: id,
      title: 'Budget warning: $categoryName',
      body:
          "You've used $percentUsed% of your $budgetStr $categoryName budget this month.",
    );
  }

  /// Fires an over-budget notification when spending exceeds 100 %.
  /// Silent if already shown this session.
  Future<void> showBudgetOverspend({
    required int categoryId,
    required String categoryName,
    required double overBy,
    required double budgetAmount,
    required String currency,
  }) async {
    final id = _budgetIdBase + categoryId * 2 + 1;
    if (_shown.contains(id)) return;
    _shown.add(id);

    final overStr = CurrencyUtils.format(overBy, currency, decimalDigits: 0);
    final budgetStr =
        CurrencyUtils.format(budgetAmount, currency, decimalDigits: 0);
    await _show(
      id: id,
      title: 'Over budget: $categoryName',
      body:
          "You've exceeded your $budgetStr $categoryName budget by $overStr this month.",
    );
  }

  /// Fires a one-time notification when the stack goal is first reached.
  /// Silent if already shown this session.
  Future<void> showStackGoalReached({
    required int goalSats,
    required String currency,
    double? btcPrice,
  }) async {
    const id = _stackGoalId;
    if (_shown.contains(id)) return;
    _shown.add(id);

    final satsStr = _formatSats(goalSats);
    final fiatPart = btcPrice != null && btcPrice > 0
        ? ' ≈ ${CurrencyUtils.format(goalSats / 1e8 * btcPrice, currency, decimalDigits: 0)}'
        : '';
    await _show(
      id: id,
      title: 'Stack goal reached!',
      body: "You've stacked $satsStr sats$fiatPart. Incredible work.",
    );
  }

  // ── Private ────────────────────────────────────────────────────────────────

  String _formatSats(int sats) => sats
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  /// Asks for notification permission the first time there is something to
  /// show, and remembers the answer for the session.
  ///
  /// Every platform the app ships on needs asking, and each has its own
  /// implementation class: only macOS was handled, so iOS never prompted and
  /// Android 13+ (which made POST_NOTIFICATIONS a runtime permission) never
  /// did either. A false answer is honoured rather than retried per
  /// notification.
  Future<bool> _ensurePermission() async {
    final cached = _permissionGranted;
    if (cached != null) return cached;

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return _permissionGranted = await ios.requestPermissions(
            alert: true,
            badge: false,
            sound: true,
          ) ??
          false;
    }

    final macOS = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (macOS != null) {
      return _permissionGranted = await macOS.requestPermissions(
            alert: true,
            badge: false,
            sound: true,
          ) ??
          false;
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return _permissionGranted =
          await android.requestNotificationsPermission() ?? false;
    }

    // Linux and Windows need no runtime grant.
    return _permissionGranted = true;
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    try {
      if (!await _ensurePermission()) return;

      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
          android: AndroidNotificationDetails(
            'budget_alerts',
            'Budget Alerts',
            channelDescription: 'Notifies when spending approaches or exceeds budget limits',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }
}
