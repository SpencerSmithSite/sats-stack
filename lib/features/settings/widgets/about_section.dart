import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../main.dart' as app;
import '../../../shared/constants/app_constants.dart';

/// Settings → About: the version, the licences, and the way back into
/// onboarding.
class AboutSection extends StatefulWidget {
  const AboutSection({super.key});

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = 'v${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      // Plugin not available in this build configuration — version stays hidden.
    }
  }

  Future<void> _resetOnboarding() async {
    await (app.db.delete(
      app.db.appSettings,
    )..where((t) => t.key.equals(AppConstants.settingOnboardingComplete))).go();
    if (!mounted) return;
    // Says it is a revisit, then clears the flag, which onboarding used to
    // read for that and so always saw a first run (audit U-1).
    context.go('/onboarding?revisit=1');
    app.onboardingCompleteNotifier.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Sats Stack'),
          subtitle: Text(
            'Local-first Bitcoin budgeting. No cloud. No accounts.'
            '${_appVersion.isNotEmpty ? '\n$_appVersion' : ''}',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Licences'),
          subtitle: const Text('Open-source software and fonts used'),
          onTap:
              () => showLicensePage(
                context: context,
                applicationName: 'Sats Stack',
                applicationVersion: _appVersion,
              ),
        ),
        ListTile(
          leading: const Icon(Icons.replay_outlined),
          title: const Text('Show onboarding'),
          subtitle: const Text('Revisit the welcome screens'),
          onTap: _resetOnboarding,
        ),
      ],
    );
  }
}
