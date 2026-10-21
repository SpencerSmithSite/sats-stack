import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/ai_chat/ai_chat_screen.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/budgets/budgets_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/stack/stack_screen.dart';
import 'features/transactions/transactions_screen.dart';
import 'main.dart' as app;
import 'screens/import/import_file_screen.dart';
import 'shared/theme/app_theme.dart';

class SatsStackApp extends StatelessWidget {
  const SatsStackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: app.themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp.router(
          title: 'Sats Stack',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          routerConfig: _router,
        );
      },
    );
  }
}

/// Synchronous on purpose.
///
/// This used to be async and query `app_settings` for the onboarding flag every
/// time it ran, which is every navigation plus each of GoRouter's
/// redirect-resolution passes. `onboardingCompleteNotifier` is read once at
/// startup and kept current by the two places that change it, and it is in
/// `refreshListenable` below so a change re-runs this immediately.
String? _appRedirect(BuildContext context, GoRouterState state) {
  final path = state.uri.path;

  if (path != '/onboarding' && !app.onboardingCompleteNotifier.value) {
    return '/onboarding';
  }

  // The AI tab can go away while /ai is the current route — the user picks a
  // provider in Settings that cannot answer on this device. The path was only
  // dropped from the shell's tab list, so `_indexForLocation` fell back to 0
  // and the AI screen stayed rendered with Dashboard highlighted and no tab
  // matching it. `refreshListenable` below is what makes this re-run on the
  // toggle rather than waiting for the next navigation.
  if (path == '/ai' && !app.aiEnabledNotifier.value) return '/dashboard';

  return null;
}

final _router = GoRouter(
  initialLocation: '/dashboard',
  redirect: _appRedirect,
  refreshListenable: Listenable.merge([
    app.aiEnabledNotifier,
    app.onboardingCompleteNotifier,
  ]),
  routes: [
    GoRoute(
      path: '/onboarding',
      pageBuilder: (ctx, state) => _fadePage(state, const OnboardingScreen()),
    ),
    // One branch per tab, each with its own Navigator, kept alive in an
    // IndexedStack.
    //
    // This was a plain ShellRoute, which builds a different child *type* per
    // tab, so the element tree could not reconcile and every tab switch
    // destroyed the screen's State. Set a filter and a search on Transactions,
    // tap Dashboard, tap back: both were gone, the scroll position was lost,
    // and the whole table was re-queried behind a full-screen spinner. The
    // Stack period and DCA input, and the selected month on Budgets, went the
    // same way, and the Dashboard re-ran its insight reads on every visit.
    //
    // Branches are built lazily, on first visit, so this costs nothing up
    // front. The AI branch is always present; the nav bar hides it when no
    // provider can answer, and the redirect above moves off `/ai`.
    StatefulShellRoute.indexedStack(
      builder:
          (ctx, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (ctx, state) => const DashboardScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/transactions',
              builder: (ctx, state) => const TransactionsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/budgets',
              builder: (ctx, state) => const BudgetsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/stack',
              builder: (ctx, state) => const StackScreen(),
            ),
          ],
        ),
        // Last on purpose: it is the only tab that can be hidden, so keeping
        // it at the end means a branch index always equals its nav-bar index.
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/ai', builder: (ctx, state) => const AiChatScreen()),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (ctx, state) => _fadePage(state, const SettingsScreen()),
    ),
    GoRoute(
      path: '/analytics',
      pageBuilder: (ctx, state) => _fadePage(state, const AnalyticsScreen()),
    ),
    GoRoute(
      path: '/import',
      pageBuilder: (ctx, state) => _fadePage(state, const ImportFileScreen()),
    ),
  ],
);

class AppShell extends StatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    app.aiEnabledNotifier.addListener(_onAiEnabledChanged);
  }

  @override
  void dispose() {
    app.aiEnabledNotifier.removeListener(_onAiEnabledChanged);
    super.dispose();
  }

  void _onAiEnabledChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final aiEnabled = app.aiEnabledNotifier.value;
    final shell = widget.navigationShell;

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: 'Dashboard',
      ),
      const NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: 'Transactions',
      ),
      const NavigationDestination(
        icon: Icon(Icons.pie_chart_outline),
        selectedIcon: Icon(Icons.pie_chart),
        label: 'Budgets',
      ),
      const NavigationDestination(
        icon: Icon(Icons.trending_up_outlined),
        selectedIcon: Icon(Icons.trending_up),
        label: 'Stack',
      ),
      if (aiEnabled)
        const NavigationDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          selectedIcon: Icon(Icons.auto_awesome),
          label: 'AI',
        ),
    ];

    // Branch index equals destination index because the AI branch is last.
    // While it is hidden the redirect has already moved off it, so this only
    // guards the frame in between.
    final selected =
        shell.currentIndex < destinations.length ? shell.currentIndex : 0;

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        destinations: destinations,
        onDestinationSelected:
            (i) => shell.goBranch(
              i,
              // Tapping the tab you are already on returns it to its root.
              initialLocation: i == shell.currentIndex,
            ),
      ),
    );
  }
}

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, _, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}
