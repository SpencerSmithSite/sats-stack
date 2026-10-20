import 'package:flutter/material.dart';

import '../../../core/services/inference/gemini_nano_backend.dart';
import '../../../main.dart' as app;
import '../../../shared/theme/app_colors.dart';

/// Settings UI for the backends that run on the device itself.
///
/// Kept out of `settings_screen.dart` because neither fits the two-text-fields
/// shape the server-backed providers share: one is a status line, the other a
/// download Android performs on request.

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
                    // Legible accent: the raw one over a tint of itself was
                    // ~2:1 in light mode.
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.legibleAccent(color),
                      height: 1.45,
                    ),
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
/// Nothing is chosen here: Android serves one model and the only action is to
/// fetch it. Progress arrives
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
