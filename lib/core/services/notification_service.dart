import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../database/database.dart';
import '../models/price_alert.dart';

/// Wraps [FlutterLocalNotificationsPlugin] and provides the budget, stack
/// goal and price alert notifications.
///
/// Each alert is sent once per occasion: a budget warning or overspend once
/// per category per month, the stack goal once per goal amount. [claim]
/// decides — in production a [NotificationLedger], so that survives a
/// restart. It used to be a per-session set of notification ids, which meant
/// every cold start re-sent every alert (the stack goal on every launch once
/// reached), while a new month could not alert at all until the app was
/// killed, because the id did not include the month.
///
/// An alert that does not reach the screen — not initialised, permission
/// refused, the plugin throwing — is handed back with [release], so it can
/// still be sent later. It used to stay claimed, which meant allowing
/// notifications in Settings brought nothing for the rest of the month, and
/// that stack goal's alert never at all (audit D-9).
class NotificationService {
  /// [claim] returns true the first time it sees a key, and [release] forgets
  /// one. Both default to an in-memory set, for tests. [deliver] stands in
  /// for the plugin in tests, returning whether the alert was shown.
  NotificationService({
    Future<bool> Function(String key)? claim,
    Future<void> Function(String key)? release,
    @visibleForTesting
    Future<bool> Function(int id, String title, String body)? deliver,
  }) {
    if (claim == null) {
      final seen = <String>{};
      _claim = (key) async => seen.add(key);
      _release = release ?? (key) async => seen.remove(key);
    } else {
      _claim = claim;
      _release = release ?? (_) async {};
    }
    _deliver = deliver ?? _show;
    _deliverPriceAlert =
        deliver ??
        (id, title, body) => _show(id, title, body, priceAlert: true);
  }

  final _plugin = FlutterLocalNotificationsPlugin();

  late final Future<bool> Function(String key) _claim;
  late final Future<void> Function(String key) _release;
  late final Future<bool> Function(int id, String title, String body) _deliver;
  late final Future<bool> Function(int id, String title, String body)
  _deliverPriceAlert;

  /// Sends the alert for [key] unless it has been sent, and gives the claim
  /// back if it could not be shown.
  Future<void> _sendOnce(String key, int id, String title, String body) async {
    if (!await _claim(key)) return;
    if (!await _deliver(id, title, body)) await _release(key);
  }

  /// The occasion key's month part, e.g. `2026-10`.
  static String monthKey(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  bool _initialized = false;

  /// Permission is asked for once, on the first notification, rather than on
  /// every one. Null until asked.
  bool? _permissionGranted;

  /// Budget IDs start above this so they cannot collide with
  /// [_stackGoalId]: `categoryId * 2 + 1` hit 9999 exactly at category 4999,
  /// which would have silently replaced the goal notification.
  static const _budgetIdBase = 100000;
  static const _stackGoalId = 9999;

  /// Price alerts take the ids from here up to [_budgetIdBase]: above the
  /// stack goal and below the lowest budget id (category ids start at 1), so
  /// neither can replace one. Room for [_priceAlertIdCount] alerts before an
  /// id repeats, which would only replace an alert's own long-gone banner.
  static const _priceAlertIdBase = 10000;
  static const _priceAlertIdCount = _budgetIdBase - _priceAlertIdBase;

  @visibleForTesting
  static int priceAlertNotificationId(int alertId) =>
      _priceAlertIdBase + alertId % _priceAlertIdCount;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
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
          // A white-on-transparent silhouette: Android draws the small icon
          // from its alpha alone, so the full-colour launcher icon was a
          // white square. Kept from resource shrinking by res/raw/keep.xml.
          android: AndroidInitializationSettings('ic_stat_notification'),
        ),
      );
      _initialized = true;
    } catch (_) {}
  }

  // ── Budget alerts ──────────────────────────────────────────────────────────
  //
  // No amounts in any notification: a budget, an overspend or a stack's worth
  // showed on a locked or shared screen, which for Bitcoin holdings is a
  // physical-security risk (audit P-8). The percentage and the category say
  // what to look at; the amounts are one tap away, behind the lock.

  /// Fires a warning notification when a budget reaches ≥ 80 %.
  /// Silent if already sent for this category in [month].
  Future<void> showBudgetWarning({
    required int categoryId,
    required String categoryName,
    required int percentUsed,
    required DateTime month,
  }) => _sendOnce(
    'budget_warn_${categoryId}_${monthKey(month)}',
    _budgetIdBase + categoryId * 2,
    'Budget warning: $categoryName',
    "You've used $percentUsed% of your $categoryName budget this month.",
  );

  /// Fires an over-budget notification when spending exceeds 100 %.
  /// Silent if already sent for this category in [month].
  Future<void> showBudgetOverspend({
    required int categoryId,
    required String categoryName,
    required DateTime month,
  }) => _sendOnce(
    'budget_over_${categoryId}_${monthKey(month)}',
    _budgetIdBase + categoryId * 2 + 1,
    'Over budget: $categoryName',
    "You've gone over your $categoryName budget this month.",
  );

  /// Fires a one-time notification when the stack goal is first reached.
  /// Silent if already sent for this goal amount.
  Future<void> showStackGoalReached({required int goalSats}) =>
  // Per goal amount, so raising the goal and reaching it again alerts
  // again.
  _sendOnce(
    'stack_goal_$goalSats',
    _stackGoalId,
    'Stack goal reached!',
    "You've reached your stack goal. Incredible work.",
  );

  // ── Price alerts ───────────────────────────────────────────────────────────

  /// Tells the user the price has crossed one of their alerts, and returns
  /// whether it reached the screen.
  ///
  /// Not through [_sendOnce]: the alert records that it has fired itself
  /// (`PriceAlert.triggeredAt`), and a ledger row per alert would outlive the
  /// alert. The answer comes back instead, so an alert that could not be
  /// shown stays waiting, as a budget alert's claim is released (audit D-9).
  ///
  /// No price in the text, as no amount is in any other notification (audit
  /// P-8): the level someone set alerts at says what they are watching for,
  /// and on a locked screen that is nobody else's business. The price is one
  /// tap away, in the app.
  Future<bool> showPriceAlert({
    required int alertId,
    required PriceAlertDirection direction,
  }) => _deliverPriceAlert(
    priceAlertNotificationId(alertId),
    'Bitcoin price alert',
    switch (direction) {
      PriceAlertDirection.above =>
        'Bitcoin has risen past a price you set an alert for.',
      PriceAlertDirection.below =>
        'Bitcoin has fallen past a price you set an alert for.',
    },
  );

  // ── Private ────────────────────────────────────────────────────────────────

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

    final ios =
        _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
    if (ios != null) {
      return _permissionGranted =
          await ios.requestPermissions(
            alert: true,
            badge: false,
            sound: true,
          ) ??
          false;
    }

    final macOS =
        _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
    if (macOS != null) {
      return _permissionGranted =
          await macOS.requestPermissions(
            alert: true,
            badge: false,
            sound: true,
          ) ??
          false;
    }

    final android =
        _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (android != null) {
      return _permissionGranted =
          await android.requestNotificationsPermission() ?? false;
    }

    // Linux and Windows need no runtime grant.
    return _permissionGranted = true;
  }

  /// True only when the plugin accepted the notification. [priceAlert] puts
  /// it on its own Android channel, so either kind can be silenced in the
  /// system settings without the other.
  Future<bool> _show(
    int id,
    String title,
    String body, {
    bool priceAlert = false,
  }) async {
    if (!_initialized) return false;
    try {
      if (!await _ensurePermission()) return false;

      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
          macOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
          android: priceAlert ? _priceAlertChannel : _budgetChannel,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static const _budgetChannel = AndroidNotificationDetails(
    'budget_alerts',
    'Budget Alerts',
    channelDescription:
        'Notifies when spending approaches or exceeds budget limits',
    importance: Importance.high,
    priority: Priority.high,
    // On a secure lock screen Android shows only that there is a
    // notification from the app, not its text (audit P-8).
    visibility: NotificationVisibility.private,
  );

  static const _priceAlertChannel = AndroidNotificationDetails(
    'price_alerts',
    'Price Alerts',
    channelDescription:
        'Notifies when the Bitcoin price crosses a level you set',
    importance: Importance.high,
    priority: Priority.high,
    visibility: NotificationVisibility.private,
  );
}

/// Remembers which alerts have been sent, in `AppSettings`, so a restart does
/// not send them again.
class NotificationLedger {
  NotificationLedger(this._db);

  final AppDatabase _db;

  static const _prefix = 'notified:';

  /// True, and recorded, the first time [key] is claimed; false after.
  ///
  /// Claiming a budget alert also forgets budget alerts from other months,
  /// which can never be claimed again, so the table holds one month's worth.
  Future<bool> claim(String key) {
    return _db.transaction(() async {
      final row =
          await (_db.select(_db.appSettings)
            ..where((t) => t.key.equals('$_prefix$key'))).getSingleOrNull();
      if (row != null) return false;
      final month = RegExp(r'^budget_\w+?_\d+_(\d{4}-\d{2})$').firstMatch(key);
      if (month != null) {
        await (_db.delete(_db.appSettings)..where(
          (t) =>
              t.key.like('${_prefix}budget_%') &
              t.key.like('%_${month.group(1)}').not(),
        )).go();
      }
      await _db
          .into(_db.appSettings)
          .insert(AppSettingsCompanion.insert(key: '$_prefix$key', value: '1'));
      return true;
    });
  }

  /// Forgets [key], so the next [claim] of it succeeds: the alert it stood
  /// for was not shown.
  Future<void> release(String key) async {
    await (_db.delete(_db.appSettings)
      ..where((t) => t.key.equals('$_prefix$key'))).go();
  }
}
