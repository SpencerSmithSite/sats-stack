# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build commands

```bash
# Run on macOS
flutter run -d macos

# Run on iOS simulator
flutter run -d "iPhone 16e"

# Regenerate Drift code after any table change
dart run build_runner build --delete-conflicting-outputs

# Run tests
flutter test
```

## Architecture

**Global service singletons** are initialized in `main.dart` before `runApp()` and accessed throughout the app via `import '../../main.dart' as app;` then `app.transactionService`, etc. No Provider/Riverpod — kept simple.

**BTC price reactivity** uses `btcPriceService.priceNotifier` (`ValueNotifier<double?>`). Widgets subscribe with `ValueListenableBuilder` or `addListener`/`removeListener`.

**Dashboard data flow**: `DashboardService.watchDashboard(month)` → `StreamBuilder<DashboardData>` (outer) → `ValueListenableBuilder<String>` (currency) → `ValueListenableBuilder<double?>` (price) → `_DashboardContent`.

**Navigation**: GoRouter 16.3.0 with `ShellRoute` for 5-tab bottom nav (`/dashboard`, `/transactions`, `/budgets`, `/stack`, `/ai`). AI tab is conditionally included only when `PlatformUtils.isDesktop` (mobile AI support is planned — see backlog). `/settings` and `/analytics` are pushed modally via `context.push(...)`.

**AI/Ollama features** are currently gated behind `PlatformUtils.isDesktop` (`Platform.isMacOS || Platform.isWindows || Platform.isLinux`). Planned: `aiEnabledNotifier` (`ValueNotifier<bool>` in `main.dart`) will replace the hard `isDesktop` gate — true on desktop always, true on mobile when a non-localhost Ollama URL is configured.

**Transaction dedup**: SHA-256 of `"date|amount|description|salt"`. CSV re-imports use `salt=''` to deduplicate; manual entries use `salt=microsecondsSinceEpoch` to allow intentional duplicates; recurring instances use `salt='recurring_${anchorMs}_${nextDueMs}'`.

**Drift class names** (table → row → companion):
- `Wallets` → `Wallet` → `WalletsCompanion`
- `Transactions` → `Transaction` → `TransactionsCompanion`
- `Categories` → `Category` → `CategoriesCompanion`
- `Budgets` → `Budget` → `BudgetsCompanion`
- `AppSettings` → `AppSetting` → `AppSettingsCompanion`
- `BtcPriceCache` → `BtcPriceCacheData` → `BtcPriceCacheCompanion`
- `BtcPriceHistory` → `BtcPriceHistoryData` → `BtcPriceHistoryCompanion`
- `AiConversations` → `AiConversation` → `AiConversationsCompanion`

## Critical package version pins

| Package | Version | Reason |
|---|---|---|
| `drift_flutter` | `^0.2.8` | 0.3.0 requires sqlite3_flutter_libs 0.6, conflicts |
| `go_router` | `^16.3.0` | 17.x requires Dart 3.9 |
| `fl_chart` | `^0.71.0` | 1.x requires vector_math 2.2, conflicts with flutter_test |
| `flutter_local_notifications` | `^19.5.0` | 20+ requires Dart 3.8 |

Do not upgrade these without verifying Dart SDK compatibility.

**pointycastle note**: `pointy_castle` (underscore) does NOT exist. `pointycastle` (no underscore) v4.0.0 is the real package. `ECCurve_secp256k1` extends `ECDomainParametersImpl` — it IS the domain params object, no `.domainParams` getter.

## Platform notes

- macOS entitlements (`macos/Runner/DebugProfile.entitlements` + `Release.entitlements`) must include `com.apple.security.network.client = true` for HTTP calls.
- macOS Podfile `post_install`: sets `SKIP_INSTALL=YES` + `DEFINES_MODULE=YES` on the sqlite3 pod target to fix duplicate framework embedding warning.
- iOS Podfile (`ios/Podfile`): must have `platform :ios, '12.0'` (uncommented) and `use_modular_headers!` inside the `target 'Runner'` block. Required because `sqlite3_flutter_libs` (Swift) depends on `sqlite3` (C) and `file_picker` pulls in `DKPhotoGallery` (Swift) → `SDWebImage` (C), both of which need modular headers.
- Bitcoin crypto packages (`bs58check ^1.0.2`, `bech32 ^0.2.2`) are in pubspec.
- Current DB schemaVersion: **3** (v1→v2: adds `recurringPeriod` + `recurringAnchorDate` to Transactions; v2→v3: creates `BtcPriceHistory` table).

## Current state

All 12 original build steps complete, plus 12 backlog items:

**Original steps:**
1. Drift DB schema, theme (dark, Bitcoin orange #F7931A), GoRouter shell
2. Manual transaction entry, category chips, date-grouped list, delete on long-press
3. BTC price service (mempool.space primary, CoinGecko fallback, `ValueNotifier`, multi-currency)
4. Full Dashboard (hero card, 2×2 metric grid, spending bar chart, AI insight card, month selector)
5. CSV import — `CsvImportService` (bank format detection, auto-categorise, dedup), `CsvImportSheet`
6. xpub import — `XpubService` (BIP32/44/49/84 via pointycastle secp256k1, Mempool.space Esplora, gap-limit-20)
7. Budgets — `BudgetService`, `BudgetCard` (progress bar, sats opp cost), `SetBudgetSheet`, `flutter_local_notifications`
8. Stack tracker — fl_chart `LineChart` (cumulative sats, time filters, touch tooltip), stack goal, DCA simulator
9. Ollama AI chat (desktop only) — streaming chat, model selector, system prompt with financial context
10. Onboarding — 3-page `PageView`, GoRouter redirect guard
11. Settings — theme toggle, Ollama config, SQLite export/import, reset onboarding
12. Polish — `AnimatedSwitcher`, `TweenAnimationBuilder`, fade transitions, `EmptyState`, error states

**Backlog additions (all complete):**
1. ✓ Edit transactions
2. ✓ Reset all data (Danger Zone)
3. ✓ AI monthly insight auto-generation
4. ✓ Custom Electrum/Mempool server URL + data routing banner in Settings
5. ✓ Spending analytics screen (`/analytics` — pie chart, 6-month trend, YTD, CSV export)
6. ✓ Currency selection (USD/GBP/EUR/CAD/AUD, `currencyNotifier`)
7. ✓ App version in Settings
8. ✓ Recurring transactions (DB migration v1→v2, `generateDueRecurring()`, Repeat toggle in AddTransactionSheet)
9. ✓ Custom categories (CategoryService CRUD, CategoriesSheet with color + 28-icon picker)
10. ✓ Exportable spending summary (CSV via `DashboardService.exportMonthlySummary`)
11. ✓ Historical BTC price per transaction (`BtcPriceHistory` table, DB v2→v3, `getHistoricalPrice()`, XpubService 2-pass sync)
12. ✓ Settings grouped into expandable sections (General / Servers / Data / About / Danger Zone)
13. ✓ Budget overspend notifications (`NotificationService`, `BudgetService.checkAndNotify()`, stack goal notification at ID 9999)
14. ✓ Transaction search and filter (search bar + `_FilterSheet` with source/category `FilterChip`s, `Badge` on filter icon)
15. ✓ Stack goal progress enhancements (`_avgMonthlySats`, `_projectedDate()`, goal-reached notification)
16. ✓ Multi-wallet dashboard (`WalletSummary` model, `DashboardService.watchPerWallet()`, `_WalletBreakdownSection` — visible when ≥ 2 wallets have activity)
17. ✓ iOS support (Podfile fixes; Settings General overflow fixed — `_SettingsTile` uses Column layout, `_RouteRow` value wrapped in `Flexible`)

**Pending:**
- Mobile AI — Remote Ollama server: `aiEnabledNotifier` (`ValueNotifier<bool>`), ungate `/ai` route, reactive nav tab, mobile Ollama settings UI, platform-aware `_OfflineState`

## Seeded data (DB `onCreate`)

- 9 system categories: Food & Dining, Transport, Housing, Shopping, Subscriptions, Entertainment, Bitcoin, Income, Other
- 1 default manual wallet: label="My Account" (required as FK for manual transactions)

## Settings keys (`AppConstants`)

`currency`, `onboarding_complete`, `ollama_url`, `ollama_model`, `theme_mode`, `stack_goal_sats`, `monthly_insight`, `monthly_insight_date`, `electrum_url`, `btc_all_prices`, `show_btc_price`

## Settings screen structure

Five `ExpansionTile` sections (all collapsed by default):
- **General**: Theme · Currency · Show BTC price · Categories
- **Servers**: AI — Ollama (desktop only currently; mobile planned) · Bitcoin/Mempool server + data routing banner
- **Data**: Export database · Import database
- **About**: Sats Stack info/version · Show onboarding
- **Danger Zone**: Reset all data
