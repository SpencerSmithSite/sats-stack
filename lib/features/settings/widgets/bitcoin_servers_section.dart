import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/models/bitcoin_data_source.dart';
import '../../../main.dart' as app;
import '../../../shared/constants/app_constants.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/currency_utils.dart';
import '../../../shared/utils/sat_converter.dart';
import '../../../shared/utils/url_utils.dart';
import 'settings_widgets.dart';
import 'wallet_history_section.dart';

/// Settings → Servers → Bitcoin: where wallet history comes from, the
/// Mempool/Esplora server used for prices, and the routing banner.
class BitcoinServersSection extends StatefulWidget {
  const BitcoinServersSection({super.key});

  @override
  State<BitcoinServersSection> createState() => _BitcoinServersSectionState();
}

class _BitcoinServersSectionState extends State<BitcoinServersSection> {
  // Bitcoin servers
  late TextEditingController _esploraUrlCtrl;
  bool _testingEsplora = false;
  String? _esploraStatus;

  @override
  void initState() {
    super.initState();
    // Use empty string when the default server is active so the field shows
    // the placeholder hint instead of the literal mempool.space URL.
    final storedUrl = app.xpubService.esploraBaseUrl;
    _esploraUrlCtrl = TextEditingController(
      text: storedUrl == AppConstants.mempoolBaseUrl ? '' : storedUrl,
    );
  }

  @override
  void dispose() {
    _esploraUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveBitcoinServers() async {
    final typed = _esploraUrlCtrl.text.trim();
    final saved = await app.xpubService.saveSettings(url: typed);
    await app.btcPriceService.loadSettings(); // reload from the same key
    if (!mounted) return;
    // Show the normalised form, so the user sees what is actually in use.
    _esploraUrlCtrl.text = saved ?? '';
    setState(() {}); // refresh privacy warning
    if (typed.isNotEmpty && saved == null) {
      // Falling back silently would leave them thinking a typo was accepted
      // and their wallet scans were private.
      _showSnack("'$typed' isn't a usable server URL — using mempool.space");
    } else {
      _showSnack('Bitcoin server settings saved');
    }
  }

  Future<void> _testEsploraConnection() async {
    setState(() {
      _testingEsplora = true;
      _esploraStatus = null;
    });

    // The same normalisation Save applies, so what is tested is what would
    // be used. A bare `myserver.lan:3006/api` has no scheme: http.get threw
    // ArgumentError for it, which the Exception catch below let through, and
    // the spinner never stopped.
    final base =
        normalizeServerUrl(_esploraUrlCtrl.text) ?? AppConstants.mempoolBaseUrl;

    try {
      // ── 1. Block height — standard Esplora endpoint ──────────────────────
      final heightResp = await http
          .get(Uri.parse('$base/blocks/tip/height'))
          .timeout(const Duration(seconds: 8));

      if (heightResp.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _esploraStatus =
              'HTTP ${heightResp.statusCode} — '
              'is this a valid Esplora / Mempool URL?';
          _testingEsplora = false;
        });
        return;
      }

      final blockHeight = int.tryParse(heightResp.body.trim()) ?? 0;
      final heightStr =
          blockHeight > 0
              ? 'Block height: ${_fmtInt(blockHeight)}'
              : 'Connected';

      // ── 2. Price endpoint — Mempool-specific, optional ───────────────────
      String priceStr = '';
      try {
        final priceResp = await http
            .get(Uri.parse('$base/v1/prices'))
            .timeout(const Duration(seconds: 5));
        if (priceResp.statusCode == 200) {
          final json = jsonDecode(priceResp.body) as Map<String, dynamic>;
          final currency = app.currencyNotifier.value;
          final price = json[currency.toUpperCase()];
          if (price != null) {
            priceStr =
                ' · BTC price: ${CurrencyUtils.format((price as num).toDouble(), currency, decimalDigits: 0)}';
          } else {
            priceStr = ' · Price data available';
          }
        }
      } catch (_) {
        // Price endpoint absent — fine, not all Esplora nodes have it
      }

      if (mounted) {
        setState(() {
          _esploraStatus = '$heightStr$priceStr';
          _testingEsplora = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _esploraStatus =
              'Could not reach server — ${e.toString().replaceAll('Exception: ', '')}';
          _testingEsplora = false;
        });
      }
    }
  }

  String _fmtInt(int n) => SatConverter.formatSats(n);

  bool get _usingDefaultServer {
    final text = _esploraUrlCtrl.text.trim();
    return text.isEmpty || text.contains('mempool.space');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSectionHeader('Bitcoin'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WalletHistorySection(
                xpub: app.xpubService,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _esploraUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mempool / Esplora server',
                  hintText: 'http://server:3006/api',
                  helperText:
                      'Used for BTC prices, and for wallet sync when it '
                      'is chosen above. Leave blank to use '
                      'mempool.space.',
                  // It was cut off at one line: "Leave blank to us…".
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 10),
              // Listens to the field instead of `onChanged: setState`.
              // The only thing the text affects here is this banner, and
              // a setState rebuilt the whole 1,700-line Settings tree —
              // five ExpansionTiles, ten provider cards, four dropdowns
              // — on every keystroke.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _esploraUrlCtrl,
                builder:
                    (_, _, _) => DataRoutingBanner(
                      usingDefault: _usingDefaultServer,
                      electrumHost:
                          app.xpubService.dataSource ==
                                  BitcoinDataSource.electrum
                              ? app.xpubService.electrum.host
                              : null,
                    ),
              ),
              const SizedBox(height: 12),
              if (_esploraStatus != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _esploraStatus!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          _esploraStatus!.startsWith('Could not') ||
                                  _esploraStatus!.startsWith('HTTP')
                              ? context.legibleAccent(AppColors.danger)
                              : context.legibleAccent(AppColors.success),
                    ),
                  ),
                ),
              Wrap(
                // Wraps at a large text size rather than overflowing.
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _testingEsplora ? null : _testEsploraConnection,
                    icon:
                        _testingEsplora
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(
                              Icons.wifi_tethering_outlined,
                              size: 18,
                            ),
                    label: const Text('Test connection'),
                  ),
                  FilledButton(
                    onPressed: _saveBitcoinServers,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
