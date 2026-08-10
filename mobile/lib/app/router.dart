import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shreeram_crm/core/auth/auth_controller.dart';
import 'package:shreeram_crm/features/auth/login_screen.dart';
import 'package:shreeram_crm/features/dashboard/dashboard_screen.dart';
import 'package:shreeram_crm/features/leads/lead_detail_screen.dart';
import 'package:shreeram_crm/features/leads/leads_screen.dart';
import 'package:shreeram_crm/features/shell/app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: RouterRefresh(ref),
    redirect: (context, state) {
      final loggedIn = auth.user != null;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          GoRoute(path: '/leads', builder: (context, state) => const LeadsScreen()),
          GoRoute(
            path: '/leads/:id',
            builder: (context, state) => LeadDetailScreen(leadId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
});

class RouterRefresh extends ChangeNotifier {
  RouterRefresh(this.ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }

  final Ref ref;
}
