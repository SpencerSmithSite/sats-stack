import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import 'app.dart';
import 'screens/splash_screen.dart';
import 'core/database/database.dart';
import 'shared/constants/app_constants.dart';
import 'core/services/transaction_service.dart';
import 'core/services/category_service.dart';
import 'core/services/wallet_service.dart';
import 'core/services/btc_price_service.dart';
import 'core/models/fx_rates.dart';
import 'core/services/dashboard_service.dart';
import 'core/services/xpub_service.dart';
import 'core/services/budget_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/ollama_service.dart';
import 'core/services/import_service.dart';

late AppDatabase db;
late TransactionService transactionService;
late CategoryService categoryService;
late WalletService walletService;
late BtcPriceService btcPriceService;
late DashboardService dashboardService;
late XpubService xpubService;
late BudgetService budgetService;
late OllamaService ollamaService;
late ImportService importService;
late NotificationService notificationService;
late ValueNotifier<ThemeMode> themeModeNotifier;
late ValueNotifier<String> currencyNotifier;
late ValueNotifier<bool> showBtcPriceNotifier;
late ValueNotifier<bool> aiEnabledNotifier;

/// Whether onboarding has been completed.
///
/// Read once here rather than per navigation. The router's redirect used to
/// query `app_settings` every time it ran — on each bottom-nav tap, each
/// `context.push`, and again on every one of GoRouter's redirect-resolution
/// passes — so a tab switch waited on a database round-trip.
late ValueNotifier<bool> onboardingCompleteNotifier;
late ValueNotifier<double> inflationRateNotifier;

/// Today's display currency and BTC prices, for converting stored amounts.
FxRates _currentRates() => FxRates(
  display: currencyNotifier.value,
  btcPrices: btcPriceService.allPrices,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Required before any downloadable-model call, and the engine must be passed
  // in explicitly — adding `flutter_gemma_litertlm` to pubspec.yaml is NOT
  // enough. `flutter_gemma` is only a core since 1.0 and registers nothing on
  // its own.
  //
  // The two failure modes are distinct and both were hit in testing:
  //   - omit this call entirely  → install fails, "FlutterGemma not initialized"
  //   - call it with no engines  → install SUCCEEDS, then the first question
  //                                fails with "No inference engine can handle
  //                                this model (ModelFileType.litertlm) …
  //                                Registered engines: ."
  // The second is the nastier one: a 2.7 GB download completes and looks
  // healthy, and only generation reveals the model can never run.
  //
  // Guarded because the plugin has no implementation on every platform this app
  // builds for, and a throw here would take the whole app down at launch over a
  // feature the user may never touch.
  try {
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
  } catch (e) {
    debugPrint('flutter_gemma unavailable on this platform: $e');
  }

  db = AppDatabase();
  transactionService = TransactionService(db);
  categoryService = CategoryService(db);
  walletService = WalletService(db);
  btcPriceService = BtcPriceService(db);
  // Both aggregate fiat across transactions, so both convert into the display
  // currency first. A closure rather than a snapshot: it reads the currency and
  // the latest prices at compute time, so a currency switch applies on the next
  // recompute. Wired before btcPriceService.initialize runs, which is fine — a
  // same-currency row needs no rate, and a foreign one is counted as
  // unconverted until prices land.
  dashboardService = DashboardService(db, rates: _currentRates);
  xpubService = XpubService(db);
  budgetService = BudgetService(db, rates: _currentRates);
  ollamaService = OllamaService(db);
  await ollamaService.loadSettings();
  importService = ImportService(db, ollamaService);
  // One rule, owned by OllamaService. Seeding this from
  // `isDesktop || isConnected` meant an on-device provider lost the tab on
  // every restart: its `isConnected` is a probe `loadSettings` only kicks off.
  aiEnabledNotifier = ValueNotifier(ollamaService.aiEnabled);
  await xpubService.loadSettings();
  // btcPriceService.loadSettings() is called inside initialize() below.

  // Onboarding state, for the router's redirect.
  final onboardingRows =
      await (db.select(db.appSettings)..where(
        (t) => t.key.equals(AppConstants.settingOnboardingComplete),
      )).get();
  onboardingCompleteNotifier = ValueNotifier(
    onboardingRows.isNotEmpty && onboardingRows.first.value == 'true',
  );

  // Load persisted theme mode
  final themeRows =
      await (db.select(db.appSettings)
        ..where((t) => t.key.equals(AppConstants.settingThemeMode))).get();
  final savedTheme = themeRows.isNotEmpty ? themeRows.first.value : null;
  final initialTheme = switch (savedTheme) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.dark,
  };
  themeModeNotifier = ValueNotifier(initialTheme);

  // Load persisted currency
  final currencyRows =
      await (db.select(db.appSettings)
        ..where((t) => t.key.equals(AppConstants.settingCurrency))).get();
  final savedCurrency =
      currencyRows.isNotEmpty ? currencyRows.first.value : 'USD';
  currencyNotifier = ValueNotifier(savedCurrency);

  // Load persisted show-BTC-price toggle (default: on)
  final showPriceRows =
      await (db.select(db.appSettings)
        ..where((t) => t.key.equals(AppConstants.settingShowBtcPrice))).get();
  final showPrice =
      showPriceRows.isEmpty || showPriceRows.first.value != 'false';
  showBtcPriceNotifier = ValueNotifier(showPrice);

  // Load persisted inflation rate (default: 3.5%)
  final inflationRows =
      await (db.select(db.appSettings)
        ..where((t) => t.key.equals(AppConstants.settingInflationRate))).get();
  final savedInflation =
      inflationRows.isNotEmpty
          ? double.tryParse(inflationRows.first.value) ??
              AppConstants.defaultInflationRate
          : AppConstants.defaultInflationRate;
  inflationRateNotifier = ValueNotifier(savedInflation);

  // Initialise local notifications (owned by NotificationService).
  notificationService = NotificationService();
  await notificationService.initialize();

  // Generate any recurring transactions that came due since last launch
  transactionService.generateDueRecurring().ignore();

  // Load cached BTC price before first frame; fetches fresh in background if stale
  await btcPriceService.initialize();

  // Check budgets at startup and on every subsequent transaction change.
  budgetService
      .checkAndNotify(
        notifications: notificationService,
        currency: currencyNotifier.value,
      )
      .ignore();
  transactionService.watchAll().listen((_) {
    budgetService
        .checkAndNotify(
          notifications: notificationService,
          currency: currencyNotifier.value,
        )
        .ignore();
  });

  runApp(const _AppWithSplash());
}

class _AppWithSplash extends StatefulWidget {
  const _AppWithSplash();

  @override
  State<_AppWithSplash> createState() => _AppWithSplashState();
}

class _AppWithSplashState extends State<_AppWithSplash> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          const SatsStackApp(),
          if (!_splashDone)
            Positioned.fill(
              child: SplashScreen(
                onComplete: () {
                  if (mounted) setState(() => _splashDone = true);
                },
              ),
            ),
        ],
      ),
    );
  }
}
