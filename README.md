<img width="833" height="663" alt="image" src="https://github.com/user-attachments/assets/b00517e0-c16c-4b08-bebb-552bce9170ef" />
<img width="833" height="648" alt="image" src="https://github.com/user-attachments/assets/4b6601c5-229e-4933-aad5-33295237d48c" />

# Sats Stack

A local-first, Bitcoin-native personal finance app built with Flutter. No cloud. No accounts. No tracking.

Track your fiat spending and your Bitcoin stack in the same place — understand what you're spending, what you're saving, and how much you're losing to inflation.

## Features

### Transactions
- Manual transaction entry with categories and notes
- CSV import with automatic bank format detection and auto-categorisation
- xpub wallet import (BIP44/49/84) — syncs via Mempool.space Esplora
- Edit and delete transactions
- Recurring transactions (daily / weekly / monthly / yearly)
- Transaction search and filter (by keyword, category, source)
- Historical BTC price recorded per transaction at time of import

### Dashboard
- Monthly income / spending / surplus overview
- Fiat "leak rate" and inflation cost metrics
- Spending breakdown by category (bar chart)
- Per-wallet breakdown (when multiple wallets are active)
- AI monthly insight (requires Ollama — desktop)
- Month selector for historical browsing

### Budgets
- Per-category monthly budgets with progress bars
- Sats opportunity cost display ("this category cost you X sats")
- Overspend notifications (≥ 80% warning, > 100% alert)

### Bitcoin Stack
- All-time cumulative sats chart with time filters (1M / 3M / 6M / 1Y / All)
- DCA simulator — model future stack growth
- Stack goal with progress bar, projected completion date, and average sats/month
- Goal-reached notification

### Analytics
- Spending pie chart by category
- 6-month income vs spending trend chart
- Year-to-date summary
- CSV export of monthly spending vs budget

### Settings
- Dark / Light / System theme
- Currency: USD, GBP, EUR, CAD, AUD
- Custom Mempool/Esplora server (for privacy — routes all wallet sync and price data through your own node)
- AI — Ollama server configuration (desktop)
- SQLite database export and import
- Custom spending categories with colour and icon picker
- Data routing banner showing exactly which servers are contacted

## Privacy

By default the app contacts **mempool.space** (wallet sync, BTC price) and **CoinGecko** (price fallback). If you configure a self-hosted Mempool/Esplora server, all data is routed through it exclusively — no third-party servers are contacted.

All data is stored locally in a SQLite database via [Drift](https://drift.simonbinder.eu/). Nothing is ever uploaded.

## AI Features

AI features use [Ollama](https://ollama.com/) running locally (desktop) or on a remote server (mobile — coming soon). No data leaves your machine unless you point it at an external Ollama instance.

Supported: macOS, Windows, Linux. iOS/Android support with a remote server URL is in development.

## Tech Stack

| Concern | Package |
|---|---|
| Database | [Drift](https://pub.dev/packages/drift) (SQLite, type-safe, reactive) |
| Navigation | [go_router](https://pub.dev/packages/go_router) 16.x |
| Charts | [fl_chart](https://pub.dev/packages/fl_chart) |
| Bitcoin crypto | [pointycastle](https://pub.dev/packages/pointycastle), [bs58check](https://pub.dev/packages/bs58check), [bech32](https://pub.dev/packages/bech32) |
| Notifications | [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) |
| File I/O | [file_picker](https://pub.dev/packages/file_picker), [path_provider](https://pub.dev/packages/path_provider) |

No state management library (Provider/Riverpod/Bloc) — services are plain Dart singletons initialized at startup, with `ValueNotifier` for reactive UI updates.

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.7
- For macOS: Xcode
- For iOS: Xcode + CocoaPods (`brew install cocoapods`)
- For AI features: [Ollama](https://ollama.com/) with at least one model pulled (e.g. `ollama pull llama3.2`)

### Run

```bash
# macOS
flutter run -d macos

# iOS simulator
flutter run -d "iPhone 16e"

# List available devices
flutter devices
```

### After changing the database schema

```bash
dart run build_runner build --delete-conflicting-outputs
```

### iOS note

The iOS `Podfile` requires `platform :ios, '12.0'` and `use_modular_headers!` inside the `target 'Runner'` block. These are already set — if you see CocoaPods errors about modular headers, ensure both lines are present in `ios/Podfile`.

## Project Structure

```
lib/
  core/
    database/        # Drift schema, tables, migrations
    models/          # Plain data classes (DashboardData, WalletSummary, etc.)
    services/        # Business logic (BudgetService, XpubService, OllamaService, etc.)
  features/
    dashboard/       # Dashboard screen + widgets
    transactions/    # Transaction list, add/edit sheets
    budgets/         # Budget cards + set budget sheet
    stack/           # Stack chart, DCA simulator, goal card
    ai_chat/         # Ollama chat screen (desktop)
    analytics/       # Analytics screen (charts + CSV export)
    settings/        # Settings screen + categories sheet
    onboarding/      # 3-page onboarding flow
  shared/
    constants/       # AppConstants (settings keys, defaults)
    theme/           # AppColors, ThemeData
    utils/           # CurrencyUtils, PlatformUtils
```

## License

[GPL-3.0](LICENSE)
