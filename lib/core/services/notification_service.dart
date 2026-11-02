import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/sat_converter.dart';
import '../database/database.dart';

/// Wraps [FlutterLocalNotificationsPlugin] and provides budget-specific
/// notification helpers.
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
  }

  final _plugin = FlutterLocalNotificationsPlugin();

  late final Future<bool> Function(String key) _claim;
  late final Future<void> Function(String key) _release;
  late final Future<bool> Function(int id, String title, String body) _deliver;

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

  /// Fires a warning notification when a budget reaches ≥ 80 %.
  /// Silent if already sent for this category in [month].
  Future<void> showBudgetWarning({
    required int categoryId,
    required String categoryName,
    required int percentUsed,
    required double budgetAmount,
    required String currency,
    required DateTime month,
  }) async {
    final budgetStr = CurrencyUtils.format(
      budgetAmount,
      currency,
      decimalDigits: 0,
    );
    await _sendOnce(
      'budget_warn_${categoryId}_${monthKey(month)}',
      _budgetIdBase + categoryId * 2,
      'Budget warning: $categoryName',
      "You've used $percentUsed% of your $budgetStr $categoryName budget this month.",
    );
  }

  /// Fires an over-budget notification when spending exceeds 100 %.
  /// Silent if already sent for this category in [month].
  Future<void> showBudgetOverspend({
    required int categoryId,
    required String categoryName,
    required double overBy,
    required double budgetAmount,
    required String currency,
    required DateTime month,
  }) async {
    final overStr = CurrencyUtils.format(overBy, currency, decimalDigits: 0);
    final budgetStr = CurrencyUtils.format(
      budgetAmount,
      currency,
      decimalDigits: 0,
    );
    await _sendOnce(
      'budget_over_${categoryId}_${monthKey(month)}',
      _budgetIdBase + categoryId * 2 + 1,
      'Over budget: $categoryName',
      "You've exceeded your $budgetStr $categoryName budget by $overStr this month.",
    );
  }

  /// Fires a one-time notification when the stack goal is first reached.
  /// Silent if already sent for this goal amount.
  Future<void> showStackGoalReached({
    required int goalSats,
    required String currency,
    double? btcPrice,
  }) async {
    final satsStr = _formatSats(goalSats);
    final fiatPart =
        btcPrice != null && btcPrice > 0
            ? ' ≈ ${CurrencyUtils.format(goalSats / 1e8 * btcPrice, currency, decimalDigits: 0)}'
            : '';
    // Per goal amount, so raising the goal and reaching it again alerts again.
    await _sendOnce(
      'stack_goal_$goalSats',
      _stackGoalId,
      'Stack goal reached!',
      "You've stacked $satsStr sats$fiatPart. Incredible work.",
    );
  }

  // ── Private ────────────────────────────────────────────────────────────────

  String _formatSats(int sats) => SatConverter.formatSats(sats);

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

  /// True only when the plugin accepted the notification.
  Future<bool> _show(int id, String title, String body) async {
    if (!_initialized) return false;
    try {
      if (!await _ensurePermission()) return false;

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
            channelDescription:
                'Notifies when spending approaches or exceeds budget limits',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
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
