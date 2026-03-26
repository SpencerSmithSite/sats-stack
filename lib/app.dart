import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/dashboard/dashboard_screen.dart';
import 'features/transactions/transactions_screen.dart';
import 'features/budgets/budgets_screen.dart';
import 'features/stack/stack_screen.dart';
import 'features/ai_chat/ai_chat_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/analytics/analytics_screen.dart';
import 'screens/import/import_file_screen.dart';
import 'main.dart' as app;
import 'shared/constants/app_constants.dart';
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

Future<String?> _onboardingRedirect(
    BuildContext context, GoRouterState state) async {
  if (state.uri.path == '/onboarding') return null; // already there
  final rows = await (app.db.select(app.db.appSettings)
        ..where((t) => t.key.equals(AppConstants.settingOnboardingComplete)))
      .get();
  final done = rows.isNotEmpty && rows.first.value == 'true';
  return done ? null : '/onboarding';
}

final _router = GoRouter(
  initialLocation: '/dashboard',
  redirect: _onboardingRedirect,
  routes: [
    GoRoute(
      path: '/onboarding',
      pageBuilder: (ctx, state) => _fadePage(state, const OnboardingScreen()),
    ),
    ShellRoute(
      builder: (ctx, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (ctx, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/transactions',
          builder: (ctx, state) => const TransactionsScreen(),
        ),
        GoRoute(
          path: '/budgets',
          builder: (ctx, state) => const BudgetsScreen(),
        ),
        GoRoute(
          path: '/stack',
          builder: (ctx, state) => const StackScreen(),
        ),
        GoRoute(
          path: '/ai',
          builder: (ctx, state) => const AiChatScreen(),
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
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _allTabPaths = [
    '/dashboard',
    '/transactions',
    '/budgets',
    '/stack',
    '/ai',
  ];

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

  List<String> get _tabPaths => app.aiEnabledNotifier.value
      ? _allTabPaths
      : _allTabPaths.take(4).toList();

  @override
  Widget build(BuildContext context) {
    final aiEnabled = app.aiEnabledNotifier.value;
    // GoRouterState.of must use this widget's own context (scoped to ShellRoute).
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexForLocation(location, _tabPaths);

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

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        destinations: destinations,
        onDestinationSelected: (i) => context.go(_tabPaths[i]),
      ),
    );
  }

  static int _indexForLocation(String location, List<String> tabPaths) {
    for (var i = 0; i < tabPaths.length; i++) {
      if (location.startsWith(tabPaths[i])) return i;
    }
    return 0;
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
