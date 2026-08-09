import 'package:flutter/material.dart';

import '../../../core/services/inference/gemini_nano_backend.dart';
import '../../../core/services/inference/local_model_backend.dart';
import '../../../core/services/device_storage.dart';
import '../../../main.dart' as app;

/// Settings UI for the backends that run on the device itself.
///
/// Kept out of `settings_screen.dart` because the downloadable model needs more
/// than a URL field: a catalogue sized to this machine, a live download, a disk
/// check, and a way to reclaim the space afterwards. None of that fits the
/// two-text-fields shape the server-backed providers share.

/// Apple Intelligence and Gemini Nano have nothing to configure — the whole
/// section is a status line saying whether the model will answer, and if not,
/// what to do about it.
class PlatformModelStatus extends StatelessWidget {
  const PlatformModelStatus({
    super.key,
    required this.detail,
    required this.isReady,
    required this.onRecheck,
  });

  final String detail;
  final bool isReady;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isReady ? const Color(0xFF1D9E75) : const Color(0xFFF7931A);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.28)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isReady ? Icons.check_circle_outline : Icons.info_outline,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detail,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: color, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // The answer can change while this screen is open — the whole point
          // of the "switched off" message is that the user goes and switches it
          // on — so re-asking has to be one tap away rather than requiring a
          // relaunch.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRecheck,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Check again'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Gemini Nano download, which AICore performs on request.
///
/// Separate from [LocalModelSection] because nothing is chosen here: Android
/// serves one model and the only action is to fetch it. Progress arrives
/// without a total, so this is an indeterminate bar rather than a percentage —
/// see [GeminiNanoBackend.download].
class GeminiNanoDownloadSection extends StatefulWidget {
  const GeminiNanoDownloadSection({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<GeminiNanoDownloadSection> createState() =>
      _GeminiNanoDownloadSectionState();
}

class _GeminiNanoDownloadSectionState extends State<GeminiNanoDownloadSection> {
  bool _downloading = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await for (final _ in GeminiNanoBackend.download()) {
        // Progress is not expressible as a percentage; the bar is
        // indeterminate and only completion matters here.
      }
      await app.ollamaService.refreshOnDeviceReadiness();
      if (mounted) widget.onFinished();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_downloading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Android is downloading Gemini Nano. You can leave this screen — '
              'it continues in the background.',
              style: theme.textTheme.bodySmall,
            ),
          ] else
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Download Gemini Nano'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

/// The downloadable Qwen catalogue, filtered to what this device can hold.
class LocalModelSection extends StatefulWidget {
  const LocalModelSection({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<LocalModelSection> createState() => _LocalModelSectionState();
}

class _LocalModelSectionState extends State<LocalModelSection> {
  /// Download progress 0-100 for the model currently installing, keyed by id.
  /// Keyed rather than a single field so switching models mid-download cannot
  /// show one model's progress under another's name.
  final Map<String, int> _progress = {};
  String? _error;

  Future<void> _install(LocalModelChoice model) async {
    // Checked here rather than only at the button's `enabled`, because free
    // space can change between the screen being built and the tap.
    if (!await model.fitsOnDisk()) {
      final free = await DeviceStorage.freeMb();
      if (mounted) {
        setState(() => _error =
            '${model.name} needs ${model.downloadMb} MB and there '
            '${free == null ? "may not be room" : "is only $free MB free"}. '
            'Free some space and try again.');
      }
      return;
    }

    setState(() {
      _error = null;
      _progress[model.id] = 0;
    });

    try {
      await for (final pct in model.install()) {
        if (!mounted) return;
        setState(() => _progress[model.id] = pct);
      }
      await app.ollamaService.saveLocalModel(model);
      await app.ollamaService.refreshOnDeviceReadiness();
      if (mounted) widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _progress.remove(model.id));
    }
  }

  Future<void> _delete(LocalModelChoice model) async {
    await model.uninstall();
    await app.ollamaService.refreshOnDeviceReadiness();
    if (mounted) {
      setState(() {});
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<({LocalModelTier tier, LocalModelChoice model})>>(
      future: LocalModelChoice.tiersHere(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final tiers = snapshot.data!;
        final selectedId = app.ollamaService.localModel.id;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sized to this device — models that would not fit in memory are '
                'not listed.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (final entry in tiers)
                _ModelCard(
                  tier: entry.tier,
                  model: entry.model,
                  isSelected: entry.model.id == selectedId,
                  progress: _progress[entry.model.id],
                  onInstall: () => _install(entry.model),
                  onDelete: () => _delete(entry.model),
                  onSelect: () async {
                    await app.ollamaService.saveLocalModel(entry.model);
                    await app.ollamaService.refreshOnDeviceReadiness();
                    if (context.mounted) setState(() {});
                    widget.onChanged();
                  },
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.tier,
    required this.model,
    required this.isSelected,
    required this.progress,
    required this.onInstall,
    required this.onDelete,
    required this.onSelect,
  });

  final LocalModelTier tier;
  final LocalModelChoice model;
  final bool isSelected;
  final int? progress;
  final VoidCallback onInstall;
  final VoidCallback onDelete;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isInstalling = progress != null;

    return FutureBuilder<bool>(
      future: model.isInstalled(),
      builder: (context, snap) {
        final installed = snap.data ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.07)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.45)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                model.name,
                                style: theme.textTheme.titleSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (tier == LocalModelTier.recommended)
                              _Pill(text: tier.label, color: accent),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${model.approximateSize} download',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (installed && !isInstalling)
                    Icon(Icons.check_circle,
                        size: 18, color: const Color(0xFF1D9E75)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                tier.rationale,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                model.note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              if (isInstalling) ...[
                LinearProgressIndicator(
                  value: progress! <= 0 ? null : progress! / 100,
                ),
                const SizedBox(height: 6),
                Text(
                  progress! <= 0
                      ? 'Starting download…'
                      : 'Downloading — $progress%',
                  style: theme.textTheme.bodySmall,
                ),
              ] else
                Row(
                  children: [
                    if (!installed)
                      FilledButton.icon(
                        onPressed: onInstall,
                        icon: const Icon(Icons.download_outlined, size: 16),
                        label: const Text('Download'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                    else ...[
                      if (!isSelected)
                        FilledButton(
                          onPressed: onSelect,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Use this'),
                        )
                      else
                        Text(
                          'In use',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const Spacer(),
                      // Half a gigabyte the user cannot account for is not
                      // something to leave on a phone with no way to remove it,
                      // and "reinstall the app" is not an answer when that also
                      // discards their transactions.
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
