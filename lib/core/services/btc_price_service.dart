import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../shared/constants/app_constants.dart';
import '../database/database.dart';

class BtcPriceService {
  /// [clock] is for tests that need "today" to be a known date.
  BtcPriceService(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  /// Reactive price notifier — always reflects the price in [_currency].
  final ValueNotifier<double?> priceNotifier = ValueNotifier(null);

  /// When the current prices were last fetched from the network.
  DateTime? lastFetchedAt;

  bool _isFetching = false;

  /// In-memory cache of all supported currency prices from the last fetch.
  /// Persisted to AppSettings so it survives app restarts without a network call.
  final Map<String, double> _allPrices = {};

  String? _esploraBaseUrl;
  String _currency = 'USD';

  /// Tracks the last time a historical price was fetched from the network,
  /// used to enforce the 1 req/sec rate limit.
  DateTime? _lastHistoricalFetch;

  static const _supported = ['usd', 'gbp', 'eur', 'cad', 'aud'];

  /// Loads Esplora URL, selected currency, and all persisted prices from DB.
  Future<void> loadSettings() async {
    final rows =
        await (_db.select(_db.appSettings)..where(
          (t) => t.key.isIn([
            AppConstants.settingElectrumUrl,
            AppConstants.settingCurrency,
            AppConstants.settingBtcAllPrices,
          ]),
        )).get();
    for (final row in rows) {
      switch (row.key) {
        case AppConstants.settingElectrumUrl:
          _esploraBaseUrl = row.value.isNotEmpty ? row.value : null;
        case AppConstants.settingCurrency:
          _currency = row.value.isNotEmpty ? row.value : 'USD';
        case AppConstants.settingBtcAllPrices:
          if (row.value.isNotEmpty) {
            try {
              final decoded = jsonDecode(row.value) as Map<String, dynamic>;
              _allPrices.clear();
              for (final e in decoded.entries) {
                if (e.value is num) {
                  _allPrices[e.key] = (e.value as num).toDouble();
                }
              }
            } catch (_) {}
          }
      }
    }
  }

  bool get isPriceStale {
    if (lastFetchedAt == null) return true;
    return DateTime.now().difference(lastFetchedAt!).inHours >=
        AppConstants.btcPriceCacheDurationHours;
  }

  /// Called at app startup: loads cached prices into memory, then fetches
  /// fresh data in the background if stale.
  Future<void> initialize() async {
    await loadSettings();

    // Seed priceNotifier from the persisted all-prices map first (instant, no network).
    final fromMap = _allPrices[_currency.toUpperCase()];
    if (fromMap != null) {
      priceNotifier.value = fromMap;
    }

    // The single-value cache is read for its timestamp only.
    //
    // Its `priceUsd` column holds whatever currency happened to be active when
    // it was written, which is not recorded anywhere — so using it as a
    // fallback showed, say, a USD figure to a user whose currency is EUR, with
    // every sats conversion on the dashboard out by the exchange rate and
    // nothing to indicate it. The all-prices map above is the real cache; when
    // it has no entry for the active currency the price stays null and the UI
    // shows its loading state until the fetch lands.
    final cached = await _getLatestCached();
    if (cached != null) lastFetchedAt = cached.fetchedAt;

    if (isPriceStale) {
      fetchAndCache().ignore();
    }
  }

  /// Switches the active currency and immediately updates [priceNotifier]
  /// from the in-memory price map — zero network requests if already fetched.
  void switchCurrency(String currency) {
    _currency = currency;
    final cached = _allPrices[currency.toUpperCase()];
    // Null rather than left alone: the getter already reports the new
    // currency, so holding the old currency's number meant every fiat figure
    // on the dashboard was relabelled rather than reconverted — wrong by the
    // exchange rate, with no error anywhere. Null renders as "loading".
    priceNotifier.value = cached;
    if (cached == null) {
      // First launch, or a custom server that does not carry this currency.
      // The in-flight guard is left alone: clearing it, as this used to, let
      // two fetches run at once and interleave their writes.
      fetchAndCache().ignore();
    }
  }

  double? get currentPrice => priceNotifier.value;

  /// The BTC price in [currency], or null if no fetch has returned it.
  ///
  /// Distinct from [priceNotifier], which is the price in the *active*
  /// currency only. Anything that converts a stored amount must use the price
  /// in that amount's own currency — using the active one is how a USD row
  /// edited while the app was in GBP got a GBP-derived figure labelled `$`.
  double? priceFor(String currency) => _allPrices[currency.toUpperCase()];

  /// Every currency's BTC price from the latest fetch, keyed by upper-case
  /// code. Read-only; the map is replaced wholesale on each successful fetch.
  Map<String, double> get allPrices => Map.unmodifiable(_allPrices);

  /// The currently selected currency code (e.g. 'USD').
  String get currency => _currency;

  /// Fetches fresh prices for all supported currencies in one request, stores
  /// the active currency's price in the DB cache, and updates [priceNotifier].
  /// Pass [force] to bypass the in-progress guard (e.g. manual user refresh).
  Future<double?> fetchAndCache({bool force = false}) async {
    if (_isFetching && !force) return priceNotifier.value;
    _isFetching = true;
    try {
      final fetched = await _fetchFromApi();
      if (fetched != null && fetched.isNotEmpty) {
        // Replaced in one step, and only once a response has actually been
        // parsed. The fetchers used to clear `_allPrices` before knowing
        // whether the response held anything, so a partial reply — or a
        // mempool failure followed by a CoinGecko failure — left the map
        // stripped of the currencies it already had, and that empty map was
        // then persisted.
        _allPrices
          ..clear()
          ..addAll(fetched);

        final price = _allPrices[_currency.toUpperCase()];
        final now = DateTime.now();

        // The legacy single-value cache. Written only when the active
        // currency is actually in the response, since the column records no
        // currency of its own.
        if (price != null) {
          await _db
              .into(_db.btcPriceCache)
              .insert(
                BtcPriceCacheCompanion.insert(priceUsd: price, fetchedAt: now),
              );
        }

        // Persist the full multi-currency map so future launches don't need
        // a network call just to display the price in a different currency.
        await _db
            .into(_db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: AppConstants.settingBtcAllPrices,
                value: jsonEncode(_allPrices),
              ),
            );

        // Assigned even when null: a server that does not carry this currency
        // must not leave the previous currency's number on screen.
        priceNotifier.value = price;
        lastFetchedAt = now;
        await _pruneOldEntries();
        return price;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      _isFetching = false;
    }
  }

  /// The last persisted price, in whichever currency was active when it was
  /// written. Only safe where the currency does not matter.
  Future<double?> getCachedPrice() async {
    return (await _getLatestCached())?.priceUsd;
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<BtcPriceCacheData?> _getLatestCached() {
    return (_db.select(_db.btcPriceCache)
          ..orderBy([(t) => OrderingTerm.desc(t.fetchedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Fetches every currency the active source offers, or null if it could not
  /// be reached. Never touches [_allPrices] — the caller swaps it in on
  /// success, so a failed fetch cannot destroy a good map.
  Future<Map<String, double>?> _fetchFromApi() async {
    final customBase = _esploraBaseUrl;
    final hasCustomServer =
        customBase != null &&
        customBase.isNotEmpty &&
        !customBase.contains('mempool.space');

    // When a custom server is configured, use it exclusively — no public fallback.
    if (hasCustomServer) {
      return _fetchMempoolPrices(customBase);
    }

    // Default: mempool.space prices API (same server used for xpub sync —
    // avoids CoinGecko as an additional third party).
    // Falls back to CoinGecko only if mempool.space is unreachable.
    final fromMempool = await _fetchMempoolPrices(AppConstants.mempoolBaseUrl);
    if (fromMempool != null && fromMempool.isNotEmpty) return fromMempool;

    // CoinGecko fallback (default path only, not for custom servers).
    return _fetchCoinGeckoPrices();
  }

  /// Keeps the currency entries and drops everything else.
  ///
  /// Visible for testing: the filtering is the whole defence against a
  /// non-price field being stored as a price.
  @visibleForTesting
  ///
  /// mempool's `/v1/prices` includes a `time` field alongside the currencies,
  /// which used to be stored as a price of "TIME" — a Unix timestamp, written
  /// into the persisted map.
  static Map<String, double> currencyEntries(Map<String, dynamic> json) {
    final out = <String, double>{};
    for (final entry in json.entries) {
      final key = entry.key.toUpperCase();
      final value = entry.value;
      if (value is! num) continue;
      if (key.length != 3 || !RegExp(r'^[A-Z]{3}$').hasMatch(key)) continue;
      out[key] = value.toDouble();
    }
    return out;
  }

  /// Fetches every price a Mempool-compatible `/v1/prices` endpoint offers.
  Future<Map<String, double>?> _fetchMempoolPrices(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/v1/prices');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return currencyEntries(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return null;
  }

  /// CoinGecko fallback: fetches all supported currencies in one request.
  Future<Map<String, double>?> _fetchCoinGeckoPrices() async {
    try {
      final vsParam = _supported.join(',');
      final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=$vsParam',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final btc = json['bitcoin'];
        if (btc is Map<String, dynamic>) return currencyEntries(btc);
      }
    } catch (_) {}
    return null;
  }

  // ── Historical prices ───────────────────────────────────────────────────────

  /// Returns the BTC price for [date] in [currency].
  /// Serves from the local cache if available; otherwise fetches from the API
  /// (mempool.space primary, CoinGecko fallback) and caches it.
  /// Network calls are throttled to at most 1 per second.
  ///
  /// Only a settled day — see [_isSettled] — is cached permanently. Today's
  /// figure is a moving intraday quote, and caching it the first time it was
  /// asked for meant every transaction dated today kept that mid-day price
  /// forever, including ones re-priced days later. An unsettled day is cached
  /// in memory for [_unsettledTtl] instead, so one import still fetches it
  /// once.
  Future<double?> getHistoricalPrice(DateTime date, String currency) async {
    final dateStr = _dateKey(date);
    final cur = currency.toUpperCase();
    final settled = _isSettled(date);

    if (settled) {
      final cached =
          await (_db.select(_db.btcPriceHistory)..where(
            (t) => t.date.equals(dateStr) & t.currency.equals(cur),
          )).getSingleOrNull();
      if (cached != null) return cached.price;
    } else {
      final recent = _unsettled[dateStr];
      if (recent != null && _now().difference(recent.at) < _unsettledTtl) {
        return recent.prices[cur];
      }
    }

    // Throttle network calls to 1 req/sec.
    final now = DateTime.now();
    if (_lastHistoricalFetch != null) {
      final elapsed = now.difference(_lastHistoricalFetch!);
      if (elapsed < const Duration(seconds: 1)) {
        await Future.delayed(const Duration(seconds: 1) - elapsed);
      }
    }
    _lastHistoricalFetch = DateTime.now();

    return _fetchAndCacheHistorical(date, cur, settled: settled);
  }

  /// Whether [date]'s price is final. A two-day margin rather than "before
  /// today": the key is a local date while the price sources bucket by UTC,
  /// so "yesterday" here can still be "today" there.
  bool _isSettled(DateTime date) =>
      _now().difference(DateTime(date.year, date.month, date.day)) >
      const Duration(days: 2);

  static const _unsettledTtl = Duration(minutes: 15);

  /// Prices for days that have not settled, by date key, with when fetched.
  final _unsettled = <String, ({Map<String, double> prices, DateTime at})>{};

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<double?> _fetchAndCacheHistorical(
    DateTime date,
    String currency, {
    required bool settled,
  }) async {
    final customBase = _esploraBaseUrl;
    final hasCustomServer =
        customBase != null &&
        customBase.isNotEmpty &&
        !customBase.contains('mempool.space');

    Map<String, double>? prices;
    if (hasCustomServer) {
      prices = await _fetchMempoolHistoricalPrices(customBase, date);
    } else {
      prices = await _fetchMempoolHistoricalPrices(
        AppConstants.mempoolBaseUrl,
        date,
      );
      prices ??= await _fetchCoinGeckoHistoricalPrices(date);
    }

    if (prices == null || prices.isEmpty) return null;

    final dateStr = _dateKey(date);
    if (!settled) {
      _unsettled[dateStr] = (prices: prices, at: _now());
      // A row an earlier build wrote for this date mid-day would otherwise be
      // served as final once the day settles.
      await (_db.delete(_db.btcPriceHistory)
        ..where((t) => t.date.equals(dateStr))).go();
      return prices[currency];
    }

    // Persist all returned currencies for this date (permanent cache).
    await _db.batch((b) {
      for (final entry in prices!.entries) {
        b.insert(
          _db.btcPriceHistory,
          BtcPriceHistoryCompanion.insert(
            date: dateStr,
            currency: entry.key,
            price: entry.value,
          ),
          onConflict: DoNothing(),
        );
      }
    });

    return prices[currency];
  }

  /// Fetches historical prices from a Mempool-compatible endpoint.
  /// The `/v1/historical-price?timestamp=...` endpoint returns all currencies
  /// in a single request.
  Future<Map<String, double>?> _fetchMempoolHistoricalPrices(
    String baseUrl,
    DateTime date,
  ) async {
    try {
      final timestamp = date.millisecondsSinceEpoch ~/ 1000;
      final uri = Uri.parse(
        '$baseUrl/v1/historical-price?timestamp=$timestamp',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final pricesList = json['prices'] as List<dynamic>?;
        if (pricesList != null && pricesList.isNotEmpty) {
          final priceData = pricesList.first as Map<String, dynamic>;
          final result = <String, double>{};
          for (final entry in priceData.entries) {
            if (entry.key != 'time' && entry.value is num) {
              result[entry.key.toUpperCase()] = (entry.value as num).toDouble();
            }
          }
          if (result.isNotEmpty) return result;
        }
      }
    } catch (_) {}
    return null;
  }

  /// CoinGecko fallback for historical prices.
  Future<Map<String, double>?> _fetchCoinGeckoHistoricalPrices(
    DateTime date,
  ) async {
    try {
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final dateStr = '$day-$month-${date.year}';
      final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/coins/bitcoin/history'
        '?date=$dateStr&localization=false',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final marketData = json['market_data'] as Map<String, dynamic>?;
        final currentPrice =
            marketData?['current_price'] as Map<String, dynamic>?;
        if (currentPrice != null) {
          final result = <String, double>{};
          for (final entry in currentPrice.entries) {
            if (entry.value is num) {
              result[entry.key.toUpperCase()] = (entry.value as num).toDouble();
            }
          }
          if (result.isNotEmpty) return result;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _pruneOldEntries() async {
    final all =
        await (_db.select(_db.btcPriceCache)
          ..orderBy([(t) => OrderingTerm.desc(t.fetchedAt)])).get();
    if (all.length > 10) {
      final toDelete = all.skip(10).map((e) => e.id).toList();
      await (_db.delete(_db.btcPriceCache)
        ..where((t) => t.id.isIn(toDelete))).go();
    }
  }
}
