import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shreeram_crm/core/auth/auth_controller.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/shared/widgets/brand_logo.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  int _indexFor(String location, bool isAdmin) {
    if (location.startsWith('/leads')) return 1;
    if (location.startsWith('/follow-ups')) return 2;
    if (location.startsWith('/site-visits')) return 3;
    if (location.startsWith('/stages')) return isAdmin ? 4 : 0;
    if (location.startsWith('/meta')) return isAdmin ? 5 : 0;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final isAdmin = user?.isStaffAdmin ?? false;
    final location = GoRouterState.of(context).uri.toString();
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final destinations = <_NavItem>[
      const _NavItem('/dashboard', Icons.dashboard_outlined, 'Home'),
      const _NavItem('/leads', Icons.view_kanban_outlined, 'Leads'),
      const _NavItem('/follow-ups', Icons.event_available_outlined, 'Follow-ups'),
      const _NavItem('/site-visits', Icons.home_work_outlined, 'Site visits'),
      if (isAdmin) const _NavItem('/stages', Icons.tune_rounded, 'Statuses'),
      if (isAdmin) const _NavItem('/meta', Icons.hub_outlined, 'Meta'),
    ];
    final selected = _indexFor(location, isAdmin).clamp(0, destinations.length - 1);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF3F7F4), Color(0xFFE7F0E9), Color(0xFFF7F2E3)],
          ),
        ),
        child: Row(
          children: [
            if (wide)
              Container(
                width: 248,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppTheme.brandGreenDeep, AppTheme.brandGreenDark, Color(0xFF0F6B28)],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 22, 16, 8),
                        child: BrandLogo(height: 52, showWordmark: false),
                      ),
                      const SizedBox(height: 18),
                      for (var i = 0; i < destinations.length; i++)
                        _SideNavTile(
                          item: destinations[i],
                          selected: selected == i,
                          onTap: () => context.go(destinations[i].path),
                        ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.name ?? '',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.role ?? '',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                              icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
                              label: const Text('Sign out', style: TextStyle(color: Colors.white70)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  if (!wide)
                    SafeArea(
                      bottom: false,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        color: AppTheme.forest,
                        child: Row(
                          children: [
                            const Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: BrandLogo(height: 36, showWordmark: false, compact: true),
                              ),
                            ),
                            IconButton(
                              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                              icon: const Icon(Icons.logout, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(child: child),
                  if (!wide)
                    NavigationBar(
                      selectedIndex: selected,
                      onDestinationSelected: (i) => context.go(destinations[i].path),
                      destinations: [
                        for (final d in destinations)
                          NavigationDestination(icon: Icon(d.icon), label: d.label),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.path, this.icon, this.label);
  final String path;
  final IconData icon;
  final String label;
}

class _SideNavTile extends StatelessWidget {
  const _SideNavTile({required this.item, required this.selected, required this.onTap});

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(item.icon, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: selected ? 1 : 0.78),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
