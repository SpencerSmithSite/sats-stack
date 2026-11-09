import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import 'widgets/about_section.dart';
import 'widgets/ai_provider_section.dart';
import 'widgets/bitcoin_servers_section.dart';
import 'widgets/danger_zone_section.dart';
import 'widgets/data_section.dart';
import 'widgets/general_section.dart';

/// Settings: five collapsible sections, each its own widget under
/// `widgets/` that owns its state and talks to its service directly.
///
/// It was one 1,900-line state class holding every section's controllers and
/// connection tests, so a keystroke in any field could rebuild all of it, and
/// nothing could be tested without the rest.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _Section(
            icon: Icons.tune_outlined,
            title: 'General',
            children: [GeneralSection()],
          ),
          _Section(
            icon: Icons.dns_outlined,
            title: 'Servers',
            children: [AiProviderSection(), BitcoinServersSection()],
          ),
          _Section(
            icon: Icons.storage_outlined,
            title: 'Data',
            children: [DataSection()],
          ),
          _Section(
            icon: Icons.info_outline,
            title: 'About',
            children: [AboutSection()],
          ),
          _Section(
            icon: Icons.warning_amber_outlined,
            title: 'Danger Zone',
            colour: AppColors.danger,
            children: [DangerZoneSection()],
          ),
        ],
      ),
    );
  }
}

/// One collapsible section, collapsed to start with.
class _Section extends StatefulWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
    this.colour,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final Color? colour;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  /// Whether the section has been opened. Its contents are built only from
  /// then on: kept alive while collapsed, they were also built while never
  /// opened, so every Settings visit ran the AI section's model-list request
  /// to the provider, with the user's key, and its platform probes (audit
  /// U-15).
  bool _opened = false;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(widget.icon, color: widget.colour),
      title: Text(widget.title, style: TextStyle(color: widget.colour)),
      childrenPadding: EdgeInsets.zero,
      // Each section's state lives in its own widget, which a collapsed tile
      // would otherwise dispose: what was typed, a test's result, and a fresh
      // probe of the AI server every time it was opened.
      maintainState: true,
      onExpansionChanged: (open) {
        if (open && !_opened) setState(() => _opened = true);
      },
      // Left, like the rows in them: the default centres the section headers
      // ("AI PROVIDER", "BITCOIN") and nothing else.
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: _opened ? widget.children : const [],
    );
  }
}
