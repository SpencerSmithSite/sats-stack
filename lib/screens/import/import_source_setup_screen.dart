import 'package:flutter/material.dart';

import '../../main.dart' as app;

class ImportSourceSetupScreen extends StatefulWidget {
  const ImportSourceSetupScreen({super.key});

  @override
  State<ImportSourceSetupScreen> createState() =>
      _ImportSourceSetupScreenState();
}

class _ImportSourceSetupScreenState extends State<ImportSourceSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _type = 'bank';
  String _currency = 'USD';
  final _currencyController = TextEditingController(text: 'USD');
  bool _saving = false;

  static const _types = <String, String>{
    'bank': 'Bank Account',
    'credit_card': 'Credit Card',
    'loan': 'Loan',
    'bitcoin_exchange': 'Bitcoin Exchange',
    'bitcoin_wallet': 'Bitcoin Wallet',
    'other': 'Other',
  };

  static const _currencies = ['USD', 'EUR', 'GBP', 'CAD', 'AUD', 'BTC', 'SATS'];

  @override
  void dispose() {
    _nameController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = await app.importService.createSource(
        name: _nameController.text.trim(),
        type: _type,
        currency: _currency,
      );
      if (mounted) Navigator.of(context).pop(id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Import Source'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Name
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Source Name',
                hintText: 'e.g. Chase Checking, Coinbase',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 20),

            // Account type
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Account Type'),
              items: _types.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Row(
                          children: [
                            Icon(_typeIcon(e.key),
                                size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text(e.value),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 20),

            // Currency — dropdown + manual entry
            DropdownButtonFormField<String>(
              value: _currencies.contains(_currency) ? _currency : 'other',
              decoration: const InputDecoration(labelText: 'Currency'),
              items: [
                ..._currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                const DropdownMenuItem(value: 'other', child: Text('Other…')),
              ],
              onChanged: (v) {
                if (v == 'other') {
                  setState(() => _currency = _currencyController.text);
                } else {
                  setState(() {
                    _currency = v!;
                    _currencyController.text = v;
                  });
                }
              },
            ),
            if (!_currencies.contains(_currency)) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _currencyController,
                decoration: const InputDecoration(
                  labelText: 'Custom Currency Code',
                  hintText: 'e.g. CHF, JPY',
                ),
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) => setState(() => _currency = v.toUpperCase()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],

            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Create Source'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    return switch (type) {
      'bank' => Icons.account_balance,
      'credit_card' => Icons.credit_card,
      'loan' => Icons.paid,
      'bitcoin_exchange' => Icons.currency_bitcoin,
      'bitcoin_wallet' => Icons.account_balance_wallet,
      _ => Icons.receipt,
    };
  }
}
