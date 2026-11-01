import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../main.dart' as app;
import '../../../shared/constants/app_constants.dart';
import '../../../shared/theme/app_colors.dart';

/// Settings → Danger Zone: reset everything to a fresh install.
class DangerZoneSection extends StatefulWidget {
  const DangerZoneSection({super.key});

  @override
  State<DangerZoneSection> createState() => _DangerZoneSectionState();
}

class _DangerZoneSectionState extends State<DangerZoneSection> {
  Future<void> _resetAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Reset all data?'),
            content: const Text(
              'This will permanently delete all transactions, wallets, budgets, AI conversations, settings, and any saved AI API keys.\n\nThis cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                child: const Text('Delete Everything'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    // Guarded: a failure partway left a half-reset app with no message
    // (audit U-6).
    try {
      await app.db.resetAndReseed();
      // Deleted rows stay in the file's free pages, and a restore leaves the
      // previous database beside it as a `.bak`; the dialog promised both were
      // gone. Best effort: a reset that has already emptied the tables carries
      // on to the defaults below either way.
      try {
        await eraseDeletedData(app.db, await databaseFile());
      } catch (_) {}
      // And any statement or photo the pickers copied into the app's cache.
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}
      // API keys live in the keychain, so `resetAndReseed` cannot reach them.
      // Leaving a user's credentials behind after "delete everything" would be a
      // genuine surprise — and on a shared or resold device, a real leak.
      await app.ollamaService.clearAllApiKeys();
      // Every service and notifier holds what it read at launch, and the table
      // they read it from is now empty. Only the theme and onboarding flag used
      // to be reset, so a turned-off price chip or a custom inflation rate, a
      // custom Esplora server and the old AI provider and URLs stayed in force
      // until the next launch — then silently flipped to the defaults.
      await app.ollamaService.loadSettings();
      await app.xpubService.loadSettings();
      await app.btcPriceService.loadSettings();
      app.currencyNotifier.value = 'USD';
      app.btcPriceService.switchCurrency('USD');
      app.showBtcPriceNotifier.value = true;
      app.inflationRateNotifier.value = AppConstants.defaultInflationRate;
      app.aiEnabledNotifier.value = app.ollamaService.aiEnabled;
      app.themeModeNotifier.value = ThemeMode.dark;
      // resetAndReseed empties app_settings, so the flag is gone from the
      // database; the notifier has to follow or the router will not let the user
      // back into onboarding.
      app.onboardingCompleteNotifier.value = false;
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Reset did not finish'),
              content: Text(
                'Some of your data may still be there. Try again, and if it '
                'keeps failing, delete and reinstall the app.\n\n$e',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
      return;
    }

    if (mounted) context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(
            Icons.delete_forever_outlined,
            color: AppColors.danger,
          ),
          title: const Text(
            'Reset all data',
            style: TextStyle(color: AppColors.danger),
          ),
          subtitle: const Text(
            'Permanently delete all transactions, wallets, budgets, and settings',
          ),
          onTap: _resetAllData,
        ),
      ],
    );
  }
}
