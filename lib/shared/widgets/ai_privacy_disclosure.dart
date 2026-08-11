import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/ai_provider.dart';
import '../theme/app_colors.dart';

/// Says plainly where the user's financial data goes.
///
/// Sats Stack's whole pitch is local-first: no account, no cloud, the database
/// on the device. Choosing a hosted model breaks that, and the app must say so
/// at the point of choosing rather than in a settings page nobody opens.
///
/// One widget, used by both Settings and onboarding, because two copies of a
/// privacy claim is two chances for one of them to go stale and start lying.
/// Renders nothing at all for a private backend — an "everything stays local"
/// reassurance next to Ollama would only train people to skip the banner that
/// matters.
class AiPrivacyDisclosure extends StatelessWidget {
  const AiPrivacyDisclosure({
    super.key,
    required this.provider,
    this.compact = false,
  });

  final AiProvider provider;

  /// Drops the "what this means" detail, for places with no room for it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final recipient = provider.dataRecipient;
    if (provider.isPrivate || recipient == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    const accent = AppColors.bitcoinOrange;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 17, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your financial data leaves this device',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  // Named, not "a server". A disclosure that does not say who
                  // receives the data is not a disclosure.
                  'To answer a question, ${provider.label} is sent your balances, '
                  'spending totals and category breakdown. These go to '
                  '$recipient, under their privacy policy and retention terms — '
                  'not this app\'s.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Nothing is sent until you ask a question, and your wallet '
                    'keys and xpubs are never included.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A link to where the user creates an API key for [provider].
///
/// "Where do I get this?" is the first question every time a key field appears,
/// and the answer is a different URL for each provider.
class ApiKeyHelpLink extends StatelessWidget {
  const ApiKeyHelpLink({super.key, required this.provider});

  final AiProvider provider;

  @override
  Widget build(BuildContext context) {
    final cloud = provider.cloudProvider;
    if (cloud == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => launchUrl(
          Uri.parse(cloud.keyUrl),
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Icons.open_in_new, size: 15),
        label: Text('Get a ${cloud.label} API key'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
          foregroundColor: AppColors.bitcoinOrange,
        ),
      ),
    );
  }
}
