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
    this.recipient,
  });

  final AiProvider provider;

  /// Overrides [AiProvider.dataRecipient].
  ///
  /// Ollama and LM Studio have no fixed recipient — it is whatever host the
  /// user typed — so the caller supplies it (see
  /// `OllamaService.activeDataRecipient`). Null falls back to the provider's
  /// own, which is right for the hosted four.
  final String? recipient;

  /// Drops the "what this means" detail, for places with no room for it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final recipient = this.recipient ?? provider.dataRecipient;
    if (recipient == null) return const SizedBox.shrink();

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
                  // The one banner that must be read: as raw orange on its
                  // own tint it was about 2.1:1 in light mode.
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.legibleAccent(accent),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  // Named, not "a server". A disclosure that does not say who
                  // receives the data is not a disclosure.
                  //
                  // It lists all three things that can be sent, because all
                  // three exist: a chat question, a monthly insight, and a
                  // statement handed to the import parser. An earlier version
                  // mentioned only questions, which read as a promise that the
                  // other two did not happen.
                  'When you ask a question, generate an insight, or have a '
                  'statement read, ${provider.label} receives what that needs — '
                  'your balances and spending totals, or the contents of the '
                  'statement itself. It goes to $recipient, under their privacy '
                  'policy and retention terms — not this app\'s.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  Text(
                    // True of every path: the monthly insight is only ever
                    // generated on an explicit tap for a provider like this
                    // one, and the import parser asks before it uploads a
                    // statement — once per provider, withdrawable in Settings,
                    // which is why imports are named here rather than implied.
                    // Keep it that way, or change this sentence.
                    'Nothing is sent unless you ask for it: a question you '
                    'type, an insight you tap for, or a statement import you '
                    'agreed to. No background analysis, and nothing on '
                    'launch. Your wallet keys and xpubs are never included.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.textSecondary,
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

/// A line about how the user's server is reached — see
/// `OllamaService.transportNoteFor`. Renders nothing for a null [note].
class TransportNote extends StatelessWidget {
  const TransportNote(this.note, {super.key});

  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = note;
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lan_outlined, size: 15, color: context.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.textSecondary,
                height: 1.4,
              ),
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
        onPressed:
            () => launchUrl(
              Uri.parse(cloud.keyUrl),
              mode: LaunchMode.externalApplication,
            ),
        icon: const Icon(Icons.open_in_new, size: 15),
        label: Text('Get a ${cloud.label} API key'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
          foregroundColor: context.bitcoinOrangeText,
        ),
      ),
    );
  }
}
