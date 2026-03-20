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

  /// Notification IDs already shown this session — keyed by category×2 (warning)
  /// or category×2+1 (overspend).
  final _shown = <int>{};

  bool _initialized = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      await _plugin.initialize(
        const InitializationSettings(
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
    final id = categoryId * 2;
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
    final id = categoryId * 2 + 1;
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
    const id = 9999;
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

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    try {
      // Request permission lazily on the first notification attempt.
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: false, sound: true);

      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
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
