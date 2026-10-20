<img width="833" height="663" alt="image" src="https://github.com/user-attachments/assets/b00517e0-c16c-4b08-bebb-552bce9170ef" />
<img width="833" height="648" alt="image" src="https://github.com/user-attachments/assets/4b6601c5-229e-4933-aad5-33295237d48c" />

# Sats Stack

A local-first, Bitcoin-native personal finance app built with Flutter. No cloud. No accounts. No tracking.

Track your fiat spending and your Bitcoin stack in the same place — understand what you're spending, what you're saving, and how much you're losing to inflation.

## Features

### Transactions
- Manual transaction entry with categories and notes
- CSV import with automatic bank format detection and auto-categorisation
- Bitcoin wallet import from an xpub, ypub or zpub (BIP44/49/84, mainnet and testnet) — syncs via Mempool.space Esplora or your own server
- Bank statement import from CSV, PDF or a photo
- Edit and delete transactions
- Recurring transactions (weekly / monthly / yearly)
- Transaction search and filter (by keyword, category, source)
- Historical BTC price recorded per transaction at time of import

### Dashboard
- Monthly income / spending / surplus overview
- Fiat "leak rate" and inflation cost metrics
- Spending breakdown by category (bar chart)
- Per-wallet breakdown (when multiple wallets are active)
- AI monthly insight — automatic with a private model, on request with a hosted one
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
- AI provider — on device, your own server, or hosted (see below)
- SQLite database export and import
- Custom spending categories with colour and icon picker
- Data routing banner showing exactly which servers are contacted

## Privacy

There is no Sats Stack account and no Sats Stack server. Your records are
stored on your device in a SQLite database via
[Drift](https://drift.simonbinder.eu/). The app does not encrypt that database
itself; it relies on your device's storage encryption (on by default on iOS and
Android, FileVault on a Mac).

What leaves the device, and when:

- **Wallet sync and BTC prices** go to **mempool.space** by default, with
  **CoinGecko** as a price fallback. A wallet sync sends your wallet's
  addresses. Point Settings → Servers at your own Mempool/Esplora server and
  everything goes there instead; the routing banner in Settings shows which
  servers are contacted.
- **AI** depends on the provider you choose — see below. A hosted provider is
  sent your figures only when you ask: a question, an insight you tap for, or
  a statement import you have agreed to. The import asks first, the preview
  says when a file was sent, and Settings → Servers can withdraw the
  permission.

## AI Features

Pick one provider in Settings or during onboarding:

- **On this device** — Apple Intelligence, Gemini Nano, or a downloadable
  model. Nothing leaves the device.
- **Your own server** — [Ollama](https://ollama.com/) or LM Studio, on this
  machine or your network. A server on the internet is shown as such.
- **Hosted, needs your API key** — Claude, ChatGPT, Gemini, Grok or Maple. Your
  figures go to that company to answer.

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

- Flutter 3.47.2 (the version CI builds with)
- For macOS: Xcode
- For iOS: Xcode + CocoaPods (`brew install cocoapods`)
- For Android: JDK 21 (not 25 — see `.github/workflows/ci.yml`)

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

The minimum is iOS 16, set in `ios/Podfile` and the Xcode project; the
on-device model package requires it. `pod install` needs a UTF-8 locale
(`LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`).

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
    ai_chat/         # AI chat screen
    analytics/       # Analytics screen (charts + CSV export)
    settings/        # Settings screen + categories sheet
    onboarding/      # Onboarding flow
  screens/
    import/          # Statement import: source setup, parsing, preview
  shared/
    constants/       # AppConstants (settings keys, defaults)
    theme/           # AppColors, ThemeData
    utils/           # CurrencyUtils, PlatformUtils
```

## License

[Apache-2.0](LICENSE). See [NOTICE](NOTICE) for third-party components.

One of those matters if you build this yourself: `syncfusion_flutter_pdf`,
used to extract text from PDF statements, is **not** open source. Apache-2.0
permits linking it, but it is not covered by this project's license — you need
your own Syncfusion Community or commercial license. Everything else is
permissively licensed.

This was GPL-3.0 until 2026-10-19. It changed because GPLv3 cannot carry a
proprietary dependency — §10 forbids imposing further restrictions on
recipients, and Syncfusion's revenue and headcount limits are exactly that — and
because GPLv3's terms conflict with App Store distribution, which is how this
app ships.
