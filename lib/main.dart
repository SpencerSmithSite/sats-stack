import 'package:flutter/material.dart';

import 'app.dart';
import 'core/database/database.dart';
import 'shared/constants/app_constants.dart';
import 'core/services/transaction_service.dart';
import 'core/services/category_service.dart';
import 'core/services/wallet_service.dart';
import 'core/services/btc_price_service.dart';
import 'core/services/dashboard_service.dart';
import 'core/services/csv_import_service.dart';
import 'core/services/xpub_service.dart';
import 'core/services/budget_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/ollama_service.dart';

late AppDatabase db;
late TransactionService transactionService;
late CategoryService categoryService;
late WalletService walletService;
late BtcPriceService btcPriceService;
late DashboardService dashboardService;
late CsvImportService csvImportService;
late XpubService xpubService;
late BudgetService budgetService;
late OllamaService ollamaService;
late NotificationService notificationService;
late ValueNotifier<ThemeMode> themeModeNotifier;
late ValueNotifier<String> currencyNotifier;
late ValueNotifier<bool> showBtcPriceNotifier;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  db = AppDatabase();
  transactionService = TransactionService(db);
  categoryService = CategoryService(db);
  walletService = WalletService(db);
  btcPriceService = BtcPriceService(db);
  dashboardService = DashboardService(db);
  csvImportService = CsvImportService(db);
  xpubService = XpubService(db);
  budgetService = BudgetService(db);
  ollamaService = OllamaService(db);
  await ollamaService.loadSettings();
  await xpubService.loadSettings();
  // btcPriceService.loadSettings() is called inside initialize() below.

  // Load persisted theme mode
  final themeRows = await (db.select(db.appSettings)
        ..where((t) => t.key.equals(AppConstants.settingThemeMode)))
      .get();
  final savedTheme = themeRows.isNotEmpty ? themeRows.first.value : null;
  final initialTheme = switch (savedTheme) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.dark,
  };
  themeModeNotifier = ValueNotifier(initialTheme);

  // Load persisted currency
  final currencyRows = await (db.select(db.appSettings)
        ..where((t) => t.key.equals(AppConstants.settingCurrency)))
      .get();
  final savedCurrency =
      currencyRows.isNotEmpty ? currencyRows.first.value : 'USD';
  currencyNotifier = ValueNotifier(savedCurrency);

  // Load persisted show-BTC-price toggle (default: on)
  final showPriceRows = await (db.select(db.appSettings)
        ..where((t) => t.key.equals(AppConstants.settingShowBtcPrice)))
      .get();
  final showPrice = showPriceRows.isEmpty || showPriceRows.first.value != 'false';
  showBtcPriceNotifier = ValueNotifier(showPrice);

  // Initialise local notifications (owned by NotificationService).
  notificationService = NotificationService();
  await notificationService.initialize();

  // Generate any recurring transactions that came due since last launch
  transactionService.generateDueRecurring().ignore();

  // Load cached BTC price before first frame; fetches fresh in background if stale
  await btcPriceService.initialize();

  // Check budgets at startup and on every subsequent transaction change.
  budgetService.checkAndNotify(
    notifications: notificationService,
    currency: currencyNotifier.value,
  ).ignore();
  transactionService.watchAll().listen((_) {
    budgetService.checkAndNotify(
      notifications: notificationService,
      currency: currencyNotifier.value,
    ).ignore();
  });

  runApp(const SatsStackApp());
}
