import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../shared/constants/app_constants.dart';
import '../database/database.dart';
import '../models/price_alert.dart';
import 'btc_price_service.dart';
import 'notification_service.dart';

/// The user's BTC price alerts: kept, checked against each new price, and
/// announced through [NotificationService].
///
/// Checked only while the app runs — on each price refresh, which
/// [BtcPriceService] makes about every ten minutes and on a return to the
/// foreground. There is no background fetch. Because the side the price was
/// last seen on is saved, a crossing that happened while the app was closed
/// still fires when it next opens, provided the price is still past the
/// level then.
///
/// Stored as JSON under [AppConstants.settingPriceAlerts] rather than in a
/// table of their own: a handful of rows that nothing joins against, and
/// `AppSettings` already travels with an export and is emptied by a reset.
class PriceAlertService {
  PriceAlertService(
    this._db, {
    required NotificationService notifications,
    DateTime Function()? clock,
  }) : _notifications = notifications,
       _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final NotificationService _notifications;
  final DateTime Function() _now;

  /// Every alert, oldest first. Replaced, never mutated, on each change.
  final ValueNotifier<List<PriceAlert>> alerts = ValueNotifier(const []);

  /// Every read and write goes through here in turn. A check awaits the
  /// notification plugin, and an add or a delete landing in that gap would
  /// otherwise be overwritten by the check's save of the list it started
  /// with — or two checks would both see the same crossing and fire twice.
  Future<void> _queue = Future.value();

  Future<T> _serially<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Reads the saved alerts, replacing whatever is in memory.
  Future<void> load() => _serially(() async {
    final row =
        await (_db.select(_db.appSettings)..where(
          (t) => t.key.equals(AppConstants.settingPriceAlerts),
        )).getSingleOrNull();
    alerts.value = decode(row?.value);
  });

  /// Adds an alert at [price] in [currency].
  ///
  /// [currentPrice], the price in [currency] now, records the side it starts
  /// on, so an alert set where the price already is fires only after the
  /// price has gone back and crossed it again. Without one the first price
  /// seen records the side instead.
  Future<PriceAlert> add({
    required PriceAlertDirection direction,
    required double price,
    required String currency,
    double? currentPrice,
  }) => _serially(() async {
    if (!price.isFinite || price <= 0) {
      throw ArgumentError.value(price, 'price', 'must be above zero');
    }
    final list = alerts.value;
    final alert = PriceAlert(
      id: list.fold(0, (max, a) => a.id > max ? a.id : max) + 1,
      direction: direction,
      price: price,
      currency: currency.toUpperCase(),
      createdAt: _now(),
    );
    final added = alert.copyWith(
      wasBeyond: currentPrice == null ? null : alert.isBeyond(currentPrice),
    );
    final next = [...list, added];
    await _save(next);
    alerts.value = next;
    return added;
  });

  /// Deletes the alert with [id], if there is one.
  Future<void> remove(int id) => _serially(() async {
    final next = [
      for (final a in alerts.value)
        if (a.id != id) a,
    ];
    if (next.length == alerts.value.length) return;
    await _save(next);
    alerts.value = next;
  });

  /// Compares each waiting alert with the price in its own currency, from
  /// [prices] (upper-case code → price), and notifies on a crossing.
  ///
  /// An alert whose currency has no price — a custom server that does not
  /// carry it — is left as it was: there is nothing to compare it with, and
  /// it is never compared with another currency's price.
  ///
  /// An alert whose notification did not reach the screen stays waiting and
  /// short of the level, so the next check tries again while the price is
  /// still past it.
  Future<void> check(Map<String, double> prices) => _serially(() async {
    var changed = false;
    final next = <PriceAlert>[];
    for (final alert in alerts.value) {
      final current = prices[alert.currency];
      if (alert.isTriggered || current == null) {
        next.add(alert);
        continue;
      }
      if (alert.isCrossedBy(current)) {
        final shown = await _notifications.showPriceAlert(
          alertId: alert.id,
          direction: alert.direction,
        );
        if (shown) {
          next.add(alert.copyWith(wasBeyond: true, triggeredAt: _now()));
          changed = true;
        } else {
          next.add(alert);
        }
        continue;
      }
      final beyond = alert.isBeyond(current);
      if (alert.wasBeyond != beyond) changed = true;
      next.add(alert.copyWith(wasBeyond: beyond));
    }
    if (!changed) return;
    alerts.value = next;
    // Best effort: kept in memory regardless, so this session does not fire
    // the same alert twice. A failed save at worst repeats one after a
    // restart.
    try {
      await _save(next);
    } catch (_) {}
  });

  /// Checks the alerts now and on every later change to [prices]' price.
  ///
  /// The listener is on [BtcPriceService.priceNotifier], which changes on
  /// each refresh that brings a new price, and each check reads every
  /// currency's price from that same fetch.
  void watch(BtcPriceService prices) {
    void run() => check(prices.allPrices).ignore();
    prices.priceNotifier.addListener(run);
    run();
  }

  Future<void> _save(List<PriceAlert> list) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: AppConstants.settingPriceAlerts,
          value: jsonEncode([for (final a in list) a.toJson()]),
        ),
      );

  /// The alerts in [stored], skipping any entry that is not a whole alert
  /// (and any repeat of an id, which would make two alerts share a
  /// notification).
  @visibleForTesting
  static List<PriceAlert> decode(String? stored) {
    if (stored == null || stored.isEmpty) return const [];
    Object? json;
    try {
      json = jsonDecode(stored);
    } on FormatException {
      return const [];
    }
    if (json is! List) return const [];
    final seen = <int>{};
    return [
      for (final entry in json)
        if (PriceAlert.fromJson(entry) case final alert?)
          if (seen.add(alert.id)) alert,
    ];
  }
}
