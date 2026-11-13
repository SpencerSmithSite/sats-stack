/// BTC price alerts: once per crossing, in their own currency, kept across a
/// restart.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/price_alert.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/notification_service.dart';
import 'package:sats_stack/core/services/price_alert_service.dart';
import 'package:sats_stack/shared/constants/app_constants.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late List<({int id, String text})> sent;
  late bool deliverable;
  late PriceAlertService alerts;

  NotificationService notifications() => NotificationService(
    deliver: (id, title, body) async {
      if (!deliverable) return false;
      sent.add((id: id, text: '$title\n$body'));
      return true;
    },
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sent = [];
    deliverable = true;
    alerts = PriceAlertService(
      db,
      notifications: notifications(),
      clock: () => DateTime(2026, 11, 12, 9),
    );
  });
  tearDown(() => db.close());

  Future<PriceAlert> above(double price, {double? now, String cur = 'USD'}) =>
      alerts.add(
        direction: PriceAlertDirection.above,
        price: price,
        currency: cur,
        currentPrice: now,
      );

  group('crossing', () {
    test('fires once when the price rises past the level', () async {
      await above(100000, now: 95000);

      await alerts.check({'USD': 99000});
      expect(sent, isEmpty);
      await alerts.check({'USD': 100500});
      expect(sent, hasLength(1));
      expect(sent.single.text, contains('risen'));

      // Still above, then back and over again: spent, so silent.
      await alerts.check({'USD': 101000});
      await alerts.check({'USD': 98000});
      await alerts.check({'USD': 102000});
      expect(sent, hasLength(1));
      expect(alerts.alerts.value.single.triggeredAt, DateTime(2026, 11, 12, 9));
    });

    test('a below alert fires as the price falls to it', () async {
      await alerts.add(
        direction: PriceAlertDirection.below,
        price: 80000,
        currency: 'USD',
        currentPrice: 90000,
      );
      await alerts.check({'USD': 80000});
      expect(sent.single.text, contains('fallen'));
    });

    test(
      'set where the price already is, it waits for a real crossing',
      () async {
        await above(90000, now: 95000);
        await alerts.check({'USD': 96000});
        expect(sent, isEmpty);
        await alerts.check({'USD': 89000});
        expect(sent, isEmpty);
        await alerts.check({'USD': 91000});
        expect(sent, hasLength(1));
      },
    );

    test('with no price known when set, the first one seen only records '
        'the side', () async {
      await above(90000);
      await alerts.check({'USD': 95000});
      expect(sent, isEmpty);
      expect(alerts.alerts.value.single.wasBeyond, isTrue);
    });

    test('one that could not be shown is tried again, not spent', () async {
      await above(100000, now: 95000);
      deliverable = false;
      await alerts.check({'USD': 101000});
      expect(alerts.alerts.value.single.isTriggered, isFalse);

      deliverable = true;
      await alerts.check({'USD': 101500});
      expect(sent, hasLength(1));
      expect(alerts.alerts.value.single.isTriggered, isTrue);
    });

    test('two checks at once fire it once', () async {
      await above(100000, now: 95000);
      await Future.wait([
        alerts.check({'USD': 101000}),
        alerts.check({'USD': 101000}),
      ]);
      expect(sent, hasLength(1));
    });
  });

  group('currency', () {
    test('is compared with the price in its own currency only', () async {
      await above(90000, now: 85000, cur: 'EUR');

      // The USD price is past the level; the EUR one is not.
      await alerts.check({'USD': 95000, 'EUR': 88000});
      expect(sent, isEmpty);
      // No EUR price at all: nothing to compare with, so nothing changes.
      await alerts.check({'USD': 99000});
      expect(sent, isEmpty);
      expect(alerts.alerts.value.single.wasBeyond, isFalse);

      await alerts.check({'USD': 99000, 'EUR': 90500});
      expect(sent, hasLength(1));
    });

    test('is stored upper-case, as the price map is keyed', () async {
      final alert = await above(1, cur: 'gbp');
      expect(alert.currency, 'GBP');
    });
  });

  group('storage', () {
    test('survives a restart, crossing and all', () async {
      await above(100000, now: 95000);
      await above(120000, now: 95000);

      // The app closes; the price rises past the first level meanwhile.
      final next = PriceAlertService(db, notifications: notifications());
      await next.load();
      expect(next.alerts.value.map((a) => a.price), [100000, 120000]);
      await next.check({'USD': 105000});
      expect(sent, hasLength(1));

      final third = PriceAlertService(db, notifications: notifications());
      await third.load();
      await third.check({'USD': 106000});
      expect(sent, hasLength(1), reason: 'spent, and that was saved');
    });

    test('a delete is saved, and ids are not shared', () async {
      final a = await above(100000);
      final b = await above(110000);
      expect(a.id, isNot(b.id));
      await alerts.remove(a.id);
      final c = await above(120000);
      expect(c.id, isNot(b.id));

      final next = PriceAlertService(db, notifications: notifications());
      await next.load();
      expect(next.alerts.value.map((x) => x.id), [b.id, c.id]);
    });

    test('a price of zero or less is refused', () async {
      await expectLater(above(0), throwsArgumentError);
      await expectLater(above(-5), throwsArgumentError);
      expect(alerts.alerts.value, isEmpty);
    });

    test('a malformed entry is dropped, not thrown', () {
      final good =
          PriceAlert(
            id: 1,
            direction: PriceAlertDirection.below,
            price: 50000,
            currency: 'USD',
            createdAt: DateTime(2026),
          ).toJson();
      final stored = jsonEncode([
        good,
        {...good, 'id': 2, 'direction': 'sideways'},
        {...good, 'id': 3, 'price': -1},
        {...good, 'id': 4, 'currency': 7},
        {...good}, // a repeated id
        'not an alert',
      ]);
      final decoded = PriceAlertService.decode(stored);
      expect(decoded.single.id, 1);
      expect(PriceAlertService.decode('{not json'), isEmpty);
      expect(PriceAlertService.decode('{"a":1}'), isEmpty);
      expect(PriceAlertService.decode(null), isEmpty);
    });

    test('a reset empties them', () async {
      await above(100000);
      await db.resetAndReseed();
      await alerts.load();
      expect(alerts.alerts.value, isEmpty);
    });
  });

  test('a fetched price that crosses a level notifies', () async {
    final prices = BtcPriceService(
      db,
      client: MockClient(
        (_) async => http.Response('{"USD": 101000, "EUR": 93000}', 200),
      ),
    );
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: AppConstants.settingBtcAllPrices,
            value: '{"USD": 95000, "EUR": 88000}',
          ),
        );
    await prices.initialize();
    await above(100000, now: prices.priceFor('USD'));

    alerts.watch(prices);
    await prices.fetchAndCache(force: true);
    // Queued behind the listener's own check, and does nothing itself: so
    // once it is done, the listener's has run.
    await alerts.check(const {});
    expect(sent, hasLength(1));
  });

  group('the notification', () {
    // Audit P-8: no amount in any notification, the level included.
    final amount = RegExp(r'[$€£₿]|\bsats?\b|\d');

    test('says which way, and no price', () async {
      final service = notifications();
      for (final direction in PriceAlertDirection.values) {
        await service.showPriceAlert(alertId: 1, direction: direction);
      }
      expect(sent, hasLength(2));
      for (final s in sent) {
        expect(s.text, contains('Bitcoin'));
        expect(s.text, isNot(matches(amount)), reason: s.text);
      }
    });

    test('ids stay clear of the stack goal and every budget', () {
      for (final id in [1, 2, 89999, 90000, 1 << 40]) {
        final n = NotificationService.priceAlertNotificationId(id);
        expect(n, isNot(9999));
        expect(n, greaterThanOrEqualTo(10000));
        // Budget ids are `100000 + categoryId * 2 (+ 1)`.
        expect(n, lessThan(100000));
      }
    });
  });

  test('a crossing that waited behind an add does not undo it', () async {
    // The check awaits the notification; an add landing in that gap must
    // survive the check's save.
    final gate = Completer<void>();
    final slow = PriceAlertService(
      db,
      notifications: NotificationService(
        deliver: (id, title, body) async {
          await gate.future;
          return true;
        },
      ),
    );
    await slow.add(
      direction: PriceAlertDirection.above,
      price: 100000,
      currency: 'USD',
      currentPrice: 95000,
    );
    final checking = slow.check({'USD': 101000});
    final adding = slow.add(
      direction: PriceAlertDirection.below,
      price: 50000,
      currency: 'USD',
    );
    gate.complete();
    await Future.wait([checking, adding]);
    expect(slow.alerts.value, hasLength(2));

    final reloaded = PriceAlertService(db, notifications: notifications());
    await reloaded.load();
    expect(reloaded.alerts.value, hasLength(2));
    expect(reloaded.alerts.value.first.isTriggered, isTrue);
  });
}
