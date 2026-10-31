import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../main.dart' as app;
import '../../../shared/constants/app_constants.dart';
import '../../../shared/utils/currency_utils.dart';
import 'categories_sheet.dart';
import 'settings_widgets.dart';

/// Settings → General: theme, currency, the price chip, categories and the
/// expected inflation rate.
class GeneralSection extends StatefulWidget {
  const GeneralSection({super.key});

  @override
  State<GeneralSection> createState() => _GeneralSectionState();
}

class _GeneralSectionState extends State<GeneralSection> {
  ThemeMode _themeMode = ThemeMode.dark;
  String _currency = 'USD';
  bool _showBtcPrice = true;
  String? _inflationRateError;
  late TextEditingController _inflationRateCtrl;

  @override
  void initState() {
    super.initState();
    _themeMode = app.themeModeNotifier.value;
    _currency = app.currencyNotifier.value;
    _showBtcPrice = app.showBtcPriceNotifier.value;
    _inflationRateCtrl = TextEditingController(
      text: app.inflationRateNotifier.value.toString(),
    );
  }

  @override
  void dispose() {
    _inflationRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveInflationRate() async {
    final raw = double.tryParse(_inflationRateCtrl.text.trim());
    if (raw == null || raw < 0 || raw > 100) {
      setState(
        () => _inflationRateError = 'Please enter a value between 0 and 100',
      );
      return;
    }
    setState(() => _inflationRateError = null);
    app.inflationRateNotifier.value = raw;
    await app.db
        .into(app.db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingInflationRate,
            value: raw.toString(),
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Inflation rate saved')));
    }
  }

  Future<void> _saveTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    app.themeModeNotifier.value = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await app.db
        .into(app.db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingThemeMode,
            value: value,
          ),
        );
  }

  Future<void> _saveCurrency(String code) async {
    setState(() => _currency = code);
    app.currencyNotifier.value = code;
    await app.db
        .into(app.db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingCurrency,
            value: code,
          ),
        );
    // Switch currency in price service — uses cached in-memory prices when
    // available so no extra network request is needed.
    app.btcPriceService.switchCurrency(code);
  }

  Future<void> _saveShowBtcPrice(bool value) async {
    setState(() => _showBtcPrice = value);
    app.showBtcPriceNotifier.value = value;
    await app.db
        .into(app.db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppConstants.settingShowBtcPrice,
            value: value.toString(),
          ),
        );
  }

  String _themeName(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsTile(
          title: 'Theme',
          subtitle: _themeName(_themeMode),
          trailing: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined, size: 18),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined, size: 18),
                label: Text('Dark'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined, size: 18),
                label: Text('System'),
              ),
            ],
            selected: {_themeMode},
            onSelectionChanged: (s) => _saveTheme(s.first),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ),
        SettingsTile(
          title: 'Currency',
          subtitle: '${CurrencyUtils.symbolFor(_currency)} $_currency',
          trailing: Wrap(
            spacing: 6,
            children:
                CurrencyUtils.supported
                    .map(
                      (code) => ChoiceChip(
                        label: Text(code),
                        selected: _currency == code,
                        onSelected: (_) => _saveCurrency(code),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.currency_bitcoin),
          title: const Text('Show BTC price'),
          // It hides the chip, and that is all: every sats figure in the
          // app is worked out from the live price, so it is fetched
          // either way. This used to promise that turning it off made
          // no price requests to any server.
          subtitle: const Text(
            'Shows the live price in the top bar. Sats figures still '
            'need it, so the price is fetched either way.',
          ),
          value: _showBtcPrice,
          onChanged: _saveShowBtcPrice,
        ),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Categories'),
          subtitle: const Text('Add, edit, or remove spending categories'),
          trailing: const Icon(Icons.chevron_right),
          onTap:
              () => showModalBottomSheet(
                context: context,
                useRootNavigator: true,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder:
                    (_) =>
                        CategoriesSheet(categoryService: app.categoryService),
              ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingsSectionHeader('Expected Inflation Rate'),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inflationRateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        suffixText: '%',
                        errorText: _inflationRateError,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (_inflationRateError != null) {
                          setState(() => _inflationRateError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saveInflationRate,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Used to calculate the real purchasing power loss of '
                'your fiat holdings over time.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
