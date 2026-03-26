abstract final class AppConstants {
  static const appName = 'Sats Stack';

  // API endpoints
  static const coinGeckoPriceUrl =
      'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd';
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
  static const settingOllamaConnected = 'ollama_connected';
}
