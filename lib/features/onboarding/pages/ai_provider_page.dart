/// The AI backend chooser: the grouped list, the per-provider card, and the
/// configuration that appears under the selected one.
library;

import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../core/models/ai_backend_group.dart';
import '../../../core/models/ai_provider.dart';
import '../../../shared/constants/app_constants.dart';
import '../../../shared/utils/platform_utils.dart';
import '../../../shared/widgets/ai_privacy_disclosure.dart';

class AiProviderPage extends StatelessWidget {
  const AiProviderPage({
    super.key,
    required this.catalogue,
    required this.selected,
    required this.onChanged,
    required this.urlController,
    required this.apiKeyController,
    required this.cloudKeyControllers,
  });

  final AiBackendCatalogue catalogue;
  final AiProvider selected;
  final ValueChanged<AiProvider> onChanged;
  final TextEditingController urlController;
  final TextEditingController apiKeyController;
  final Map<String, TextEditingController> cloudKeyControllers;

  /// The one-line pitch and icon for a row.
  ///
  /// Derived from the provider rather than held in a parallel list, so adding a
  /// backend cannot leave a card with no description — the switch would not
  /// compile.
  static ({String subtitle, String description, IconData icon}) _card(
    AiProvider provider,
  ) =>
      switch (provider) {
        AiProvider.appleIntelligence => (
            subtitle: 'Built in',
            description:
                'The model already on this Mac or iPhone. No key, no download, '
                    'no network — and your figures never leave the device.',
            icon: Icons.auto_awesome_outlined,
          ),
        AiProvider.geminiNano => (
            subtitle: 'Built in',
            description:
                'The model built into this phone, run by Android. No key and '
                    'no account — your figures never leave the device.',
            icon: Icons.auto_awesome_outlined,
          ),
        AiProvider.localModel => (
            subtitle: 'Download once',
            description:
                'A small open model you download once, then run offline '
                    'anywhere. Sats Stack picks a size that fits this device.',
            icon: Icons.download_outlined,
          ),
        AiProvider.ollama => (
            subtitle: 'Self-hosted',
            description:
                'Runs on your own machine or home server. Install Ollama and '
                    'pull any model — nothing leaves your network.',
            icon: Icons.computer_outlined,
          ),
        AiProvider.lmStudio => (
            subtitle: 'Self-hosted',
            description:
                'Runs models on this machine through LM Studio\'s local '
                    'server. Nothing leaves your network.',
            icon: Icons.storage_outlined,
          ),
        AiProvider.maple => (
            subtitle: 'Bring your own',
            description:
                'A hosted OpenAI-compatible endpoint you point at yourself.',
            icon: Icons.shield_outlined,
          ),
        // Named by company and default model rather than by how good they are.
        // All four are strong, so a superlative repeated on four adjacent cards
        // reads as filler and helps nobody choose; what actually decides it is
        // which account the user already has. The group heading above already
        // carries both the "powerful" and the "your data goes there" halves.
        AiProvider.claude ||
        AiProvider.chatGpt ||
        AiProvider.gemini ||
        AiProvider.grok =>
          (
            subtitle: 'Your API key',
            description: '${provider.cloudProvider!.company}\'s models, using '
                'a key you provide. Defaults to '
                '${provider.cloudProvider!.defaultModel} — you pay '
                '${provider.cloudProvider!.company} directly for what you use.',
            icon: Icons.cloud_outlined,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 48, 36, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose your\nAI assistant.',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              catalogue.hasZeroConfigOption
                  ? 'This device has a model built in, so it is ready now. You '
                      'can point Sats Stack somewhere else instead.'
                  : 'Pick where answers come from. You can change this later '
                      'in Settings → Servers.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            for (final group in catalogue.nonEmptyGroups) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  group.title.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  group.blurb,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              for (final provider in catalogue.providersIn(group))
                ProviderCard(
                  provider: provider,
                  info: _card(provider),
                  isSelected: selected == provider,
                  onTap: () => onChanged(provider),
                ),
              const SizedBox(height: 14),
            ],
            // Per-provider config section
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: child,
                ),
              ),
              child: ProviderConfigSection(
                key: ValueKey(selected),
                provider: selected,
                urlController: urlController,
                apiKeyController: apiKeyController,
                cloudKeyControllers: cloudKeyControllers,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProviderCard extends StatelessWidget {
  const ProviderCard({
    super.key,
    required this.provider,
    required this.info,
    required this.isSelected,
    required this.onTap,
  });

  final AiProvider provider;
  final ({String subtitle, String description, IconData icon}) info;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.bitcoinOrange.withAlpha(26)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.bitcoinOrange
                  : theme.colorScheme.outlineVariant.withAlpha(80),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.bitcoinOrange.withAlpha(40)
                      : AppColors.bitcoinOrange.withAlpha(20),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  info.icon,
                  color: AppColors.bitcoinOrange,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            provider.label,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            info.subtitle,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: AppColors.bitcoinOrange,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoteBanner extends StatelessWidget {
  const NoteBanner({
    super.key,
    required this.isDark,
    required this.isWarning,
    required this.text,
  });

  final bool isDark;
  final bool isWarning;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isWarning ? const Color(0xFFF7931A) : const Color(0xFF6AC86A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.10 : 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(isDark ? 0.32 : 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.info_outline,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: color, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class ProviderConfigSection extends StatelessWidget {
  const ProviderConfigSection({
    super.key,
    required this.provider,
    required this.urlController,
    required this.apiKeyController,
    required this.cloudKeyControllers,
  });

  final AiProvider provider;
  final TextEditingController urlController;
  final TextEditingController apiKeyController;
  final Map<String, TextEditingController> cloudKeyControllers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // A hosted provider needs a key and nothing else — the endpoint is fixed,
    // and the model has a sensible default that Settings can change later. The
    // disclosure comes first, above the field: someone who would not accept it
    // should learn that before typing out a credential.
    if (provider.cloudProvider case final cloud?) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AiPrivacyDisclosure(provider: provider),
            const SizedBox(height: 14),
            TextField(
              controller: cloudKeyControllers[cloud.id],
              autocorrect: false,
              enableSuggestions: false,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '${cloud.label} API key',
                hintText: '${cloud.keyPrefix}…',
                helperText: 'Stored in this device\'s keychain. You can also '
                    'add it later in Settings → Servers.',
                helperMaxLines: 2,
              ),
            ),
            ApiKeyHelpLink(provider: provider),
            const SizedBox(height: 10),
            NoteBanner(
              isDark: isDark,
              isWarning: false,
              text: 'Defaults to ${cloud.defaultModel}. You can pick a '
                  'different model in Settings → Servers.',
            ),
          ],
        ),
      );
    }

    // The on-device backends have no server and no key. Rather than render an
    // empty URL box that would be ignored, say what will happen instead — and
    // for the downloadable model, say plainly that a download is still needed,
    // since selecting it here is not the same as having it.
    if (provider.isOnDevice) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: NoteBanner(
          isDark: isDark,
          isWarning: provider == AiProvider.localModel,
          text: switch (provider) {
            AiProvider.appleIntelligence =>
              'Nothing to configure. Sats Stack will use the model already on '
                  'this device, and your figures never leave it.',
            AiProvider.geminiNano =>
              'Nothing to configure. Sats Stack will use the model built into '
                  'this phone, and your figures never leave it.',
            _ => 'You will need to download a model before this works. Sats '
                'Stack will offer one sized to this device in Settings → '
                'Servers.',
          },
        ),
      );
    }

    // Per-provider hint config
    final (urlHint, urlHelper, urlLabel, note, noteIsWarning) = switch (provider) {
      AiProvider.ollama => (
          AppConstants.defaultOllamaUrl,
          'Default port — change only if you customised Ollama\'s port',
          'Ollama server URL',
          PlatformUtils.isDesktop
              ? 'Make sure Ollama is running: ollama serve'
              : 'On iPhone/iPad, localhost won\'t reach a Mac. Use your Mac\'s local network IP — e.g. http://192.168.1.x:11434',
          !PlatformUtils.isDesktop,
        ),
      AiProvider.lmStudio => (
          AppConstants.defaultLmStudioUrl,
          'Default port — requires LM Studio\'s Local Server to be running',
          'LM Studio server URL',
          PlatformUtils.isDesktop
              ? 'In LM Studio, open the Local Server tab and click Start Server before connecting.'
              : 'On iPhone/iPad, localhost won\'t reach a Mac. Use your Mac\'s local network IP — e.g. http://192.168.1.x:1234/v1',
          !PlatformUtils.isDesktop,
        ),
      AiProvider.maple => (
          AppConstants.defaultMapleUrl,
          'Your Maple server URL (cloud or self-hosted)',
          'Maple server URL',
          'Your API key is required to authenticate with the Maple server.',
          false,
        ),
      // Unreachable: the on-device backends return above, before this switch.
      _ => ('', '', '', '', false),
    };

    const accentInfo = Color(0xFF6AC86A);
    const accentWarn = Color(0xFFF7931A);

    final noteColor = noteIsWarning ? accentWarn : accentInfo;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: urlController,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: urlLabel,
            hintText: urlHint,
            helperText: urlHelper,
            helperMaxLines: 2,
          ),
        ),
        if (provider == AiProvider.maple) ...[
          const SizedBox(height: 16),
          TextField(
            controller: apiKeyController,
            autocorrect: false,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API key',
              hintText: 'sk-…',
              helperText: 'Required — get your key from your Maple dashboard',
            ),
          ),
        ],
        // Maple is hosted like the four major providers, so the same disclosure
        // applies. Driven off `isPrivate` rather than named explicitly, so a
        // backend added to this branch later cannot quietly skip it.
        if (!provider.isPrivate) ...[
          const SizedBox(height: 14),
          AiPrivacyDisclosure(provider: provider, compact: true),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: noteColor.withOpacity(isDark ? 0.10 : 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: noteColor.withOpacity(isDark ? 0.32 : 0.20)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                noteIsWarning ? Icons.warning_amber_rounded : Icons.info_outline,
                size: 15,
                color: noteColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: noteColor,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: accentInfo.withOpacity(isDark ? 0.10 : 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: accentInfo.withOpacity(isDark ? 0.32 : 0.20)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_outline, size: 15, color: accentInfo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'You can test the connection and change these settings later in Settings → Servers.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: accentInfo,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }
}
