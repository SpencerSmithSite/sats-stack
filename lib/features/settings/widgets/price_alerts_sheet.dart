import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/price_alert.dart';
import '../../../core/services/price_alert_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/utils/amount_input.dart';
import '../../../shared/utils/currency_utils.dart';

/// Settings → General → Price alerts: the list, and a form to add one in
/// the display currency.
class PriceAlertsSheet extends StatelessWidget {
  const PriceAlertsSheet({
    super.key,
    required this.service,
    required this.currency,
    required this.priceFor,
  });

  final PriceAlertService service;

  /// The display currency, which a new alert is set in.
  final String currency;

  /// The latest BTC price in a currency, or null if none has been fetched.
  final double? Function(String currency) priceFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      // A Material for the list tiles' ink, as in the categories sheet.
      child: Material(
        color: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            // Scrolls as a whole: with the keyboard up or a large text size,
            // the form below the list would otherwise be out of reach.
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Price alerts',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    // What it can and cannot do. Nothing runs in the
                    // background, so this must not read as if it watches the
                    // price around the clock.
                    child: Text(
                      'Checked only while Sats Stack is open: each time the '
                      'price refreshes, about every 10 minutes, and when you '
                      'come back to the app. Nothing checks in the background, '
                      'so a price that crosses and comes back while the app '
                      'is closed is missed. Each alert notifies once, without '
                      'saying the price.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ValueListenableBuilder<List<PriceAlert>>(
                    valueListenable: service.alerts,
                    builder: (context, alerts, _) {
                      if (alerts.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'No alerts yet.',
                            style: TextStyle(color: context.textSecondary),
                          ),
                        );
                      }
                      return Column(
                        children: [
                          for (final alert in alerts)
                            _AlertTile(alert: alert, service: service),
                        ],
                      );
                    },
                  ),
                  const Divider(height: 1),
                  _AddAlertForm(
                    service: service,
                    currency: currency,
                    currentPrice: priceFor(currency),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Above $100,000", in the alert's own currency.
String _describe(PriceAlert alert) {
  final level = CurrencyUtils.format(
    alert.price,
    alert.currency,
    decimalDigits: CurrencyUtils.decimalsFor([alert.price]),
  );
  return switch (alert.direction) {
    PriceAlertDirection.above => 'Above $level',
    PriceAlertDirection.below => 'Below $level',
  };
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, required this.service});

  final PriceAlert alert;
  final PriceAlertService service;

  @override
  Widget build(BuildContext context) {
    final triggeredAt = alert.triggeredAt;
    final label = _describe(alert);
    return ListTile(
      leading: Icon(
        alert.direction == PriceAlertDirection.above
            ? Icons.trending_up
            : Icons.trending_down,
        color:
            triggeredAt == null
                ? AppColors.bitcoinOrange
                : context.textSecondary,
      ),
      title: Text(label),
      subtitle: Text(
        triggeredAt == null
            ? 'Waiting'
            : 'Reached ${DateFormat('MMM d, yyyy').format(triggeredAt)}. '
                'It will not notify again.',
        style: TextStyle(fontSize: 12, color: context.textSecondary),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        tooltip: 'Delete alert ${label.toLowerCase()}',
        color: AppColors.danger,
        onPressed: () async {
          try {
            await service.remove(alert.id);
          } catch (_) {
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Could not delete the alert')),
            );
          }
        },
      ),
    );
  }
}

class _AddAlertForm extends StatefulWidget {
  const _AddAlertForm({
    required this.service,
    required this.currency,
    required this.currentPrice,
  });

  final PriceAlertService service;
  final String currency;
  final double? currentPrice;

  @override
  State<_AddAlertForm> createState() => _AddAlertFormState();
}

class _AddAlertFormState extends State<_AddAlertForm> {
  final _ctrl = TextEditingController();
  PriceAlertDirection _direction = PriceAlertDirection.above;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final price = parseUserAmount(_ctrl.text);
    if (price == null || !price.isFinite || price <= 0) {
      setState(() => _error = 'Enter a price above zero');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await widget.service.add(
        direction: _direction,
        price: price,
        currency: widget.currency,
        currentPrice: widget.currentPrice,
      );
      _ctrl.clear();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the alert');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Under the field: the price now, and what an alert at the typed level
  /// will do if the price is already past it.
  String? _hint() {
    final current = widget.currentPrice;
    if (current == null) return null;
    final now = CurrencyUtils.format(
      current,
      widget.currency,
      decimalDigits: 0,
    );
    final typed = parseUserAmount(_ctrl.text);
    if (typed != null && typed > 0) {
      final probe = PriceAlert(
        id: 0,
        direction: _direction,
        price: typed,
        currency: widget.currency,
        createdAt: DateTime(0),
      );
      if (probe.isBeyond(current)) {
        return switch (_direction) {
          PriceAlertDirection.above =>
            'Bitcoin is already above this ($now), so the alert waits until '
                'it drops back and rises past it again.',
          PriceAlertDirection.below =>
            'Bitcoin is already below this ($now), so the alert waits until '
                'it climbs back and falls past it again.',
        };
      }
    }
    return 'Bitcoin is $now now.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'New alert',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<PriceAlertDirection>(
            segments: const [
              ButtonSegment(
                value: PriceAlertDirection.above,
                icon: Icon(Icons.trending_up, size: 18),
                label: Text('Rises above'),
              ),
              ButtonSegment(
                value: PriceAlertDirection.below,
                icon: Icon(Icons.trending_down, size: 18),
                label: Text('Falls below'),
              ),
            ],
            selected: {_direction},
            onSelectionChanged: (s) => setState(() => _direction = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [amountInputFormatter],
            decoration: InputDecoration(
              labelText: 'Price in ${widget.currency}',
              prefixText: CurrencyUtils.symbolFor(widget.currency),
              helperText: _hint(),
              helperMaxLines: 3,
              errorText: _error,
            ),
            onSubmitted: (_) => _add(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _add,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            child: const Text('Add alert'),
          ),
        ],
      ),
    );
  }
}
