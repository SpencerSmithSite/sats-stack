import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/services/import_service.dart';

class ImportSummaryScreen extends StatelessWidget {
  const ImportSummaryScreen({super.key, required this.summary});

  final ImportSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateRange = summary.startDate != null
        ? '${DateFormat('MMM d, yyyy').format(summary.startDate!)} – '
            '${DateFormat('MMM d, yyyy').format(summary.endDate!)}'
        : null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Import Complete'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Success icon
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF1D9E75).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 40,
                  color: Color(0xFF1D9E75),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Center(
              child: Text(
                summary.sourceName,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            if (dateRange != null) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  dateRange,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Stats grid
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Imported',
                    value: summary.imported.toString(),
                    color: const Color(0xFF1D9E75),
                    icon: Icons.download_done,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Skipped',
                    value: summary.duplicatesSkipped.toString(),
                    color: cs.onSurfaceVariant,
                    icon: Icons.content_copy_outlined,
                    subtitle: 'duplicates',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            _StatCard(
              label: 'Total found',
              value: summary.total.toString(),
              color: cs.onSurface,
              icon: Icons.receipt_long_outlined,
              wide: true,
            ),

            const Spacer(),

            // Actions
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.go('/transactions'),
                icon: const Icon(Icons.receipt_long),
                label: const Text('View Transactions'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import Another File'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.subtitle,
    this.wide = false,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final String? subtitle;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: wide
          ? Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: color, fontWeight: FontWeight.bold)),
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 8),
                Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                            color: color, fontWeight: FontWeight.bold)),
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
    );
  }
}
