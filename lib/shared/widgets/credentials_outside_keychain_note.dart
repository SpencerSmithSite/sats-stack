import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Says which credentials are stored unencrypted in the app's database
/// because the keychain refused them, or renders nothing.
///
/// That table is what Settings → Data exports, so this shows beside the AI
/// settings, where they are entered, and beside Export database (audit A-17).
class CredentialsOutsideKeychainNote extends StatelessWidget {
  const CredentialsOutsideKeychainNote({super.key, required this.items});

  /// What is stored unencrypted, named for a sentence — see
  /// `OllamaService.credentialsOutsideKeychain`.
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final what = switch (items) {
      [final only] => only,
      [...final rest, final last] => '${rest.join(', ')} and $last',
      _ => '',
    };
    final colour = context.legibleAccent(AppColors.danger);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 16, color: colour),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'The keychain would not store $what, so '
            '${items.length == 1 ? 'it is' : 'they are'} saved unencrypted in '
            "the app's database and included in any export. Saving "
            '${items.length == 1 ? 'it' : 'them'} again, or reopening the app, '
            'tries the keychain again.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}
