abstract final class AppConstants {
  // API endpoints
  static const mempoolBaseUrl = 'https://mempool.space/api';

  // Defaults
  static const defaultOllamaUrl = 'http://localhost:11434';
  static const defaultCurrency = 'USD';
  static const btcPriceCacheDurationHours = 1;

  // Database
  static const dbName = 'sats_stack_db';

  // Settings keys
  static const settingCurrency = 'currency';
  static const settingOnboardingComplete = 'onboarding_complete';
  static const settingOllamaUrl = 'ollama_url';
  static const settingOllamaModel = 'ollama_model';
  static const settingThemeMode = 'theme_mode';
  static const settingStackGoalSats = 'stack_goal_sats';
  static const settingMonthlyInsight = 'monthly_insight';
  static const settingMonthlyInsightDate = 'monthly_insight_date';
  static const settingElectrumUrl = 'electrum_url';
  // JSON-encoded map of all fetched currency prices e.g. '{"USD":97000,"EUR":89000}'
  static const settingBtcAllPrices = 'btc_all_prices';
  static const settingShowBtcPrice = 'show_btc_price';

  /// iOS only: whether the database goes into iCloud and device backups —
  /// see `ICloudBackup`.
  static const settingICloudBackup = 'icloud_backup';
  static const settingInflationRate = 'inflation_rate';
  static const defaultInflationRate = 3.5;
  static const settingOllamaConnected = 'ollama_connected';

  // AI provider selection
  static const settingAiProvider = 'ai_provider';

  // LM Studio settings
  static const defaultLmStudioUrl = 'http://localhost:1234/v1';
  static const settingLmStudioUrl = 'lm_studio_url';
  static const settingLmStudioModel = 'lm_studio_model';
  static const settingLmStudioConnected = 'lm_studio_connected';

  // Maple settings
  static const defaultMapleUrl = 'http://localhost:8080/v1';
  static const settingMapleUrl = 'maple_url';
  static const settingMapleModel = 'maple_model';

  /// Legacy location of the Maple API key.
  ///
  /// Read once at startup and migrated into `SecureKeyStore`, then the row is
  /// deleted. Kept as a constant only so the migration can find it; nothing
  /// writes here any more.
  static const settingMapleApiKey = 'maple_api_key';
  static const settingMapleConnected = 'maple_connected';

  // Hosted AI providers (Claude, ChatGPT, Gemini, Grok)
  //
  // Only the model choice and the last verified connection state live here.
  // The API key does NOT — it goes to `SecureKeyStore`, because this table is
  // ordinary SQLite that Settings → Data exports wholesale. Keyed by the
  // `CloudProvider.id` so a new provider needs no new constant.
  static String cloudModelKey(String providerId) => 'cloud_model_$providerId';
  static String cloudConnectedKey(String providerId) =>
      'cloud_connected_$providerId';

  // Which model the removed downloadable-model backend had selected. Nothing
  // writes it any more; `OllamaService.loadSettings` deletes it where an
  // earlier build left it.
  static const settingRemovedLocalModelId = 'local_model_id';

  /// How far a recurring series has been generated — a high-water mark.
  ///
  /// Without it, the resume point is the latest *surviving* instance, so
  /// deleting the most recent one lowers it and the next launch recreates the
  /// row the user just deleted (its hash is derived from the anchor and the
  /// due date, so it comes back identical). Deleting a middle instance never
  /// had that problem, which made the behaviour inconsistent as well as wrong.
  /// [seriesId] is the row's `recurringSeriesId`. Before schema v9 it was a
  /// fingerprint of the period, anchor, description and amount, which changed
  /// whenever an instance was edited — see
  /// `AppDatabase.adoptLegacyRecurringSeries`.
  /// The built-in categories' colours: what the database seeds and what
  /// `CategoryPalette` draws them in. One table, because there were two and
  /// they disagreed — the seed made Housing, Shopping, Subscriptions and Other
  /// the same grey (and Transport the Bitcoin orange), while the palette had
  /// them distinct, so the dashboard and Analytics drew them differently.
  static const seededCategoryColours = <String, String>{
    'Food & Dining': '#E24B4A',
    'Transport': '#3498DB',
    'Housing': '#B08A3E',
    'Shopping': '#9B59B6',
    'Subscriptions': '#4FA3A0',
    'Entertainment': '#C06C9E',
    'Bitcoin': '#F7931A',
    'Income': '#1D9E75',
    'Other': '#888780',
  };

  /// The category a row's spending is counted under: its own, or "Other"
  /// when it has none. The one rule for the dashboard, Analytics, the export
  /// and Budgets — Budgets skipped an uncategorised row, so an "Other" budget
  /// disagreed with the pie chart and the export (audit D-7).
  static String spendingCategory(String? category) => category ?? 'Other';

  /// Set once the API keys have been rewritten under the device-only keychain
  /// class — see `SecureKeyStore`.
  static const settingKeysDeviceOnly = 'keychain_keys_device_only';

  /// `AppSettings` key prefix recording what a built-in category is called
  /// now: `<prefix><seeded name>` → current name. Written by
  /// `CategoryService.updateCategory`, read by the import categoriser, whose
  /// keyword table uses the seeded names.
  static const systemCategoryNamePrefix = 'system_category_name:';

  static String recurringCursorKey(String seriesId) =>
      'recurring_cursor_$seriesId';

  /// Whether the user has agreed to let a named third party read their
  /// statements for the AI import tier.
  ///
  /// Keyed by `AiProvider.key` so switching provider asks again — consent to
  /// Anthropic reading a bank statement is not consent for OpenAI to. Only
  /// recorded for providers that actually send data off the device; a private
  /// backend needs no consent because nothing leaves.
  static String aiImportConsentKey(String providerKey) =>
      'ai_import_consent_$providerKey';

  // Bitcoin data source — where wallet history is read from
  //
  // `settingElectrumUrl` above predates this and is the Mempool/Esplora base
  // URL; the three keys below configure a user's own Electrum server
  // (electrs / Fulcrum), which speaks JSON-RPC over a raw TCP socket and so
  // needs host and port separately rather than a URL.
  static const settingBitcoinDataSource = 'bitcoin_data_source';
  static const settingElectrumHost = 'electrum_host';
  static const settingElectrumPort = 'electrum_port';
  static const settingElectrumSsl = 'electrum_ssl';

  /// SHA-256 of the self-signed Electrum certificate the user chose to trust.
  ///
  /// Empty means "verify normally". Without a pin the client accepted any
  /// certificate at all, which let anyone on the network read the full set of
  /// addresses a wallet scan asks about.
  static const settingElectrumCertPin = 'electrum_cert_pin';

  /// Electrum's standard plaintext TCP port.
  static const defaultElectrumPort = 50001;

  /// Electrum's standard TLS port — the default, since TLS is (audit B-2).
  static const defaultElectrumTlsPort = 50002;

  // Bitcoin Core / Knots JSON-RPC
  //
  // The RPC password is NOT here — it goes to `SecureKeyStore`, for the same
  // reason the AI keys do: this table is ordinary SQLite that Settings → Data
  // exports wholesale. This constant is the keychain entry name.
  static const settingBitcoinRpcUrl = 'bitcoin_rpc_url';
  static const settingBitcoinRpcUser = 'bitcoin_rpc_user';
  static const settingBitcoinRpcPassword = 'bitcoin_rpc_password';
  static const defaultBitcoinRpcUrl = 'http://127.0.0.1:8332';
}
