import 'package:flutter/material.dart';

import '../../../core/models/ai_provider.dart';
import '../../../main.dart' as app;
import '../../../shared/theme/app_colors.dart';
import 'settings_widgets.dart';

/// Which AI providers may read imported statements, and a way to withdraw.
///
/// Consent to upload a statement is asked once per provider and then
/// remembered, and there used to be no way to take it back short of resetting
/// all data. This row is always shown — including when nothing is allowed —
/// so the answer to "does my bank statement get uploaded?" is visible
/// somewhere other than the dialog that asked.
class ImportConsentSection extends StatefulWidget {
  const ImportConsentSection({super.key});

  @override
  State<ImportConsentSection> createState() => _ImportConsentSectionState();
}

class _ImportConsentSectionState extends State<ImportConsentSection> {
  List<AiProvider>? _allowed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final allowed = await app.importService.providersAllowedToReadImports();
    if (mounted) setState(() => _allowed = allowed);
  }

  Future<void> _withdraw() async {
    await app.importService.revokeOffDeviceImportConsent();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You will be asked before any statement is sent again'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _allowed;
    if (allowed == null) return const SizedBox.shrink();
    final names = allowed.map((p) => p.label).join(', ');
    return SettingsTile(
      title: 'Statement imports',
      subtitle:
          allowed.isEmpty
              ? 'No hosted AI may read your imported statements. You are asked '
                  'before a file would be sent anywhere.'
              : '$names may read the statements you import — each file is sent '
                  'without asking again.',
      trailing:
          allowed.isEmpty
              ? null
              : OutlinedButton.icon(
                onPressed: _withdraw,
                icon: Icon(Icons.block, size: 18, color: context.textSecondary),
                label: const Text('Withdraw permission'),
              ),
    );
  }
}
