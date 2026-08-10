import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shreeram_crm/core/auth/auth_controller.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final location = GoRouterState.of(context).uri.toString();

    return Scaffold(
      body: Row(
        children: [
          if (MediaQuery.sizeOf(context).width >= 900)
            NavigationRail(
              backgroundColor: AppTheme.forest,
              selectedIndex: location.startsWith('/leads') ? 1 : 0,
              onDestinationSelected: (index) {
                context.go(index == 0 ? '/dashboard' : '/leads');
              },
              labelType: NavigationRailLabelType.all,
              selectedIconTheme: const IconThemeData(color: Colors.white),
              unselectedIconTheme: IconThemeData(color: Colors.white.withValues(alpha: 0.7)),
              selectedLabelTextStyle: const TextStyle(color: Colors.white),
              unselectedLabelTextStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'ShreeRam',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), label: Text('Dashboard')),
                NavigationRailDestination(icon: Icon(Icons.people_outline), label: Text('Leads')),
              ],
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      tooltip: 'Logout',
                      onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                      icon: const Icon(Icons.logout, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [AppTheme.sand, AppTheme.mist]),
                  ),
                  child: Row(
                    children: [
                      if (MediaQuery.sizeOf(context).width < 900) ...[
                        IconButton(
                          onPressed: () => context.go('/dashboard'),
                          icon: const Icon(Icons.dashboard_outlined),
                        ),
                        IconButton(
                          onPressed: () => context.go('/leads'),
                          icon: const Icon(Icons.people_outline),
                        ),
                      ],
                      const Spacer(),
                      Text(user?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Chip(label: Text(user?.role ?? '')),
                      if (MediaQuery.sizeOf(context).width < 900)
                        IconButton(
                          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                          icon: const Icon(Icons.logout),
                        ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
