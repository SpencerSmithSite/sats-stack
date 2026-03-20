import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../database/database.dart';
import '../../shared/constants/app_constants.dart';

class BtcPriceService {
  BtcPriceService(this._db);

  final AppDatabase _db;

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
    final rows = await (_db.select(_db.appSettings)
          ..where((t) => t.key.isIn([
                AppConstants.settingElectrumUrl,
                AppConstants.settingCurrency,
                AppConstants.settingBtcAllPrices,
              ])))
        .get();
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

    // Fall back to the single-currency DB cache for the timestamp.
    final cached = await _getLatestCached();
    if (cached != null) {
      lastFetchedAt = cached.fetchedAt;
      if (priceNotifier.value == null) priceNotifier.value = cached.priceUsd;
    }

    if (isPriceStale) {
      fetchAndCache().ignore();
    }
  }

  /// Switches the active currency and immediately updates [priceNotifier]
  /// from the in-memory price map — zero network requests if already fetched.
  void switchCurrency(String currency) {
    _currency = currency;
    final cached = _allPrices[currency.toUpperCase()];
    if (cached != null) {
      priceNotifier.value = cached;
    } else {
      // No data yet (first launch or custom server that doesn't return this
      // currency). Trigger a fresh fetch.
      _isFetching = false; // reset in case a stale lock is held
      fetchAndCache().ignore();
    }
  }

  double? get currentPrice => priceNotifier.value;

  /// The currently selected currency code (e.g. 'USD').
  String get currency => _currency;

  /// Fetches fresh prices for all supported currencies in one request, stores
  /// the active currency's price in the DB cache, and updates [priceNotifier].
  /// Pass [force] to bypass the in-progress guard (e.g. manual user refresh).
  Future<double?> fetchAndCache({bool force = false}) async {
    if (_isFetching && !force) return priceNotifier.value;
    _isFetching = false; // reset before re-entering
    _isFetching = true;
    try {
      final price = await _fetchFromApi();
      if (price != null) {
        final now = DateTime.now();

        // Persist the active-currency price in the legacy single-value cache.
        await _db.into(_db.btcPriceCache).insert(
              BtcPriceCacheCompanion.insert(
                priceUsd: price,
                fetchedAt: now,
              ),
            );

        // Persist the full multi-currency map so future launches don't need
        // a network call just to display the price in a different currency.
        await _db.into(_db.appSettings).insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: AppConstants.settingBtcAllPrices,
                value: jsonEncode(_allPrices),
              ),
            );

        priceNotifier.value = price;
        lastFetchedAt = now;
        await _pruneOldEntries();
      }
      return price;
    } catch (_) {
      return null;
    } finally {
      _isFetching = false;
    }
  }

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

  Future<double?> _fetchFromApi() async {
    final currencyKey = _currency.toUpperCase();

    final customBase = _esploraBaseUrl;
    final hasCustomServer = customBase != null &&
        customBase.isNotEmpty &&
        !customBase.contains('mempool.space');

    // When a custom server is configured, use it exclusively — no public fallback.
    if (hasCustomServer) {
      return _fetchMempoolPrices(customBase, currencyKey);
    }

    // Default: mempool.space prices API (same server used for xpub sync —
    // avoids CoinGecko as an additional third party).
    // Falls back to CoinGecko only if mempool.space is unreachable.
    final mempoolPrice =
        await _fetchMempoolPrices(AppConstants.mempoolBaseUrl, currencyKey);
    if (mempoolPrice != null) return mempoolPrice;

    // CoinGecko fallback (default path only, not for custom servers).
    return _fetchCoinGeckoPrices(currencyKey);
  }

  /// Fetches prices from a Mempool-compatible `/api/v1/prices` endpoint.
  /// Returns the price for [currencyKey] and populates [_allPrices].
  Future<double?> _fetchMempoolPrices(
      String baseUrl, String currencyKey) async {
    try {
      final uri = Uri.parse('$baseUrl/v1/prices');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _allPrices.clear();
        for (final entry in json.entries) {
          if (entry.value is num) {
            _allPrices[entry.key.toUpperCase()] =
                (entry.value as num).toDouble();
          }
        }
        return _allPrices[currencyKey];
      }
    } catch (_) {}
    return null;
  }

  /// CoinGecko fallback: fetches all supported currencies in one request.
  Future<double?> _fetchCoinGeckoPrices(String currencyKey) async {
    try {
      final vsParam = _supported.join(',');
      final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=$vsParam',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final btc = json['bitcoin'] as Map<String, dynamic>?;
        if (btc != null) {
          _allPrices.clear();
          for (final entry in btc.entries) {
            _allPrices[entry.key.toUpperCase()] =
                (entry.value as num).toDouble();
          }
          return _allPrices[currencyKey];
        }
      }
    } catch (_) {}
    return null;
  }

  // ── Historical prices ───────────────────────────────────────────────────────

  /// Returns the BTC price for [date] in [currency].
  /// Serves from the local cache if available; otherwise fetches from the API
  /// (mempool.space primary, CoinGecko fallback) and caches permanently.
  /// Network calls are throttled to at most 1 per second.
  Future<double?> getHistoricalPrice(DateTime date, String currency) async {
    final dateStr = _dateKey(date);
    final cur = currency.toUpperCase();

    // Cache hit
    final cached = await (_db.select(_db.btcPriceHistory)
          ..where((t) => t.date.equals(dateStr) & t.currency.equals(cur)))
        .getSingleOrNull();
    if (cached != null) return cached.price;

    // Throttle network calls to 1 req/sec.
    final now = DateTime.now();
    if (_lastHistoricalFetch != null) {
      final elapsed = now.difference(_lastHistoricalFetch!);
      if (elapsed < const Duration(seconds: 1)) {
        await Future.delayed(const Duration(seconds: 1) - elapsed);
      }
    }
    _lastHistoricalFetch = DateTime.now();

    return _fetchAndCacheHistorical(date, cur);
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<double?> _fetchAndCacheHistorical(DateTime date, String currency) async {
    final customBase = _esploraBaseUrl;
    final hasCustomServer = customBase != null &&
        customBase.isNotEmpty &&
        !customBase.contains('mempool.space');

    Map<String, double>? prices;
    if (hasCustomServer) {
      prices = await _fetchMempoolHistoricalPrices(customBase, date);
    } else {
      prices = await _fetchMempoolHistoricalPrices(AppConstants.mempoolBaseUrl, date);
      prices ??= await _fetchCoinGeckoHistoricalPrices(date);
    }

    if (prices == null || prices.isEmpty) return null;

    // Persist all returned currencies for this date (permanent cache).
    final dateStr = _dateKey(date);
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
      String baseUrl, DateTime date) async {
    try {
      final timestamp = date.millisecondsSinceEpoch ~/ 1000;
      final uri =
          Uri.parse('$baseUrl/v1/historical-price?timestamp=$timestamp');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final pricesList = json['prices'] as List<dynamic>?;
        if (pricesList != null && pricesList.isNotEmpty) {
          final priceData = pricesList.first as Map<String, dynamic>;
          final result = <String, double>{};
          for (final entry in priceData.entries) {
            if (entry.key != 'time' && entry.value is num) {
              result[entry.key.toUpperCase()] =
                  (entry.value as num).toDouble();
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
      DateTime date) async {
    try {
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final dateStr = '$day-$month-${date.year}';
      final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/coins/bitcoin/history'
        '?date=$dateStr&localization=false',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final marketData = json['market_data'] as Map<String, dynamic>?;
        final currentPrice =
            marketData?['current_price'] as Map<String, dynamic>?;
        if (currentPrice != null) {
          final result = <String, double>{};
          for (final entry in currentPrice.entries) {
            if (entry.value is num) {
              result[entry.key.toUpperCase()] =
                  (entry.value as num).toDouble();
            }
          }
          if (result.isNotEmpty) return result;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _pruneOldEntries() async {
    final all = await (_db.select(_db.btcPriceCache)
          ..orderBy([(t) => OrderingTerm.desc(t.fetchedAt)]))
        .get();
    if (all.length > 10) {
      final toDelete = all.skip(10).map((e) => e.id).toList();
      await (_db.delete(_db.btcPriceCache)
            ..where((t) => t.id.isIn(toDelete)))
          .go();
    }
  }
}
