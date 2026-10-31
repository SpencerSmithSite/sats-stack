import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/models/bitcoin_data_source.dart';
import '../../../core/services/ollama_service.dart';
import '../../../core/services/xpub_service.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../shared/theme/app_colors.dart';

/// Where wallet history is read from: a Mempool/Esplora server, or the user's
/// own Electrum server (TODO item 11).
///
/// Its own widget rather than more state in `settings_screen.dart`, which item
/// 14 is about taking apart. It holds the Electrum fields and talks to
/// [xpub] directly; [onChanged] tells the screen to redraw the routing banner.
class WalletHistorySection extends StatefulWidget {
  const WalletHistorySection({
    super.key,
    required this.xpub,
    required this.onChanged,
  });

  final XpubService xpub;
  final VoidCallback onChanged;

  @override
  State<WalletHistorySection> createState() => _WalletHistorySectionState();
}

class _WalletHistorySectionState extends State<WalletHistorySection> {
  late BitcoinDataSource _source = widget.xpub.dataSource;
  late final _host = TextEditingController(text: widget.xpub.electrum.host);
  late final _port = TextEditingController(
    text: widget.xpub.electrum.port.toString(),
  );
  late bool _ssl = widget.xpub.electrum.ssl;
  String? _status;
  bool _statusIsError = false;
  bool _busy = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _choose(BitcoinDataSource source) async {
    setState(() => _source = source);
    // Electrum is switched to once its server answers — on Save — or at once
    // if one is already set up. Mempool needs nothing.
    if (source == BitcoinDataSource.mempool ||
        widget.xpub.electrum.isConfigured) {
      await widget.xpub.saveDataSource(source);
      widget.onChanged();
    }
  }

  void _say(String status, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _statusIsError = error;
      _busy = false;
    });
  }

  /// Saves what is typed — keeping a pinned certificate only for the same
  /// server — tests it, and on success makes it the source. A self-signed
  /// TLS certificate is offered for trust rather than failing outright.
  Future<void> _saveAndTest() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty) return _say('Enter the server’s address', error: true);
    if (port == null || port < 1 || port > 65535) {
      return _say('Enter a port from 1 to 65535', error: true);
    }
    // Plain TCP beyond the user's own network is readable and forgeable by
    // anyone on the way, so it is a choice made on purpose (audit B-2).
    if (!_ssl &&
        !OllamaService.isLocalEndpoint('http://$host') &&
        !await _confirmPlainTcp(host)) {
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });

    final electrum = widget.xpub.electrum;
    final sameServer =
        host == electrum.host && port == electrum.port && _ssl == electrum.ssl;
    await electrum.saveSettings(
      host: host,
      port: port,
      ssl: _ssl,
      certificateFingerprint: sameServer ? electrum.pinnedFingerprint : '',
    );

    try {
      await _connected();
    } on HandshakeException {
      // An unverified certificate. Only TLS gets here.
      final fingerprint = await electrum.fetchCertificateFingerprint();
      if (fingerprint == null || !mounted) {
        return _say(
          'The server’s certificate could not be checked',
          error: true,
        );
      }
      if (!await _askToTrust(fingerprint)) {
        return _say('Not switched — the certificate was not trusted');
      }
      await electrum.saveSettings(
        host: host,
        port: port,
        ssl: _ssl,
        certificateFingerprint: fingerprint,
      );
      try {
        await _connected();
      } catch (e) {
        _say('Could not connect — $e', error: true);
      }
    } catch (e) {
      _say('Could not connect — $e', error: true);
    }
  }

  Future<bool> _confirmPlainTcp(String host) async {
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Connect without TLS?'),
            content: Text(
              '$host is outside your own network. Without TLS, anyone on the '
              'way can read every address your wallets use, and can answer '
              'with false history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Connect anyway'),
              ),
            ],
          ),
    );
    return yes ?? false;
  }

  /// Turns TLS on or off, moving the port between the standard two when it
  /// is still on one of them.
  void _setTls(bool on) {
    setState(() {
      _ssl = on;
      final port = _port.text.trim();
      final from =
          on
              ? AppConstants.defaultElectrumPort
              : AppConstants.defaultElectrumTlsPort;
      if (port.isEmpty || port == '$from') {
        _port.text =
            '${on ? AppConstants.defaultElectrumTlsPort : AppConstants.defaultElectrumPort}';
      }
    });
  }

  Future<void> _connected() async {
    final status = await widget.xpub.electrum.testConnection();
    await widget.xpub.saveDataSource(BitcoinDataSource.electrum);
    widget.onChanged();
    _say(status);
  }

  Future<bool> _askToTrust(String fingerprint) async {
    final grouped = [
      for (var i = 0; i < fingerprint.length; i += 2)
        fingerprint.substring(i, i + 2).toUpperCase(),
    ].join(':');
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Trust this server’s certificate?'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'It is not signed by an authority this device trusts, '
                    'which is usual for a server you run yourself. Trust it '
                    'only if this SHA-256 fingerprint matches the one your '
                    'server shows. Afterwards, only this exact certificate is '
                    'accepted.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    grouped,
                    style: const TextStyle(
                      fontFamily: 'RobotoMono',
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Trust'),
              ),
            ],
          ),
    );
    return yes ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Wallet history from', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<BitcoinDataSource>(
          segments: const [
            ButtonSegment(
              value: BitcoinDataSource.mempool,
              label: Text('Mempool / Esplora'),
            ),
            ButtonSegment(
              value: BitcoinDataSource.electrum,
              label: Text('My Electrum server'),
            ),
          ],
          selected: {_source},
          onSelectionChanged: (s) => _choose(s.first),
        ),
        if (_source == BitcoinDataSource.electrum) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _host,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Electrum server',
              hintText: 'umbrel.local or 192.168.1.5',
              helperText: 'electrs or Fulcrum. Prices still come from below.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Port',
              hintText:
                  '${_ssl ? AppConstants.defaultElectrumTlsPort : AppConstants.defaultElectrumPort}',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _ssl,
            onChanged: _setTls,
            title: const Text('Use TLS'),
            subtitle: const Text(
              'Usually port 50002. Without it, your addresses cross the '
              'network readable, and the history could be altered on the way.',
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _status!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.legibleAccent(
                    _statusIsError ? AppColors.danger : AppColors.success,
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : _saveAndTest,
              icon:
                  _busy
                      ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.wifi_tethering_outlined, size: 18),
              label: const Text('Save and test'),
            ),
          ),
        ],
      ],
    );
  }
}
