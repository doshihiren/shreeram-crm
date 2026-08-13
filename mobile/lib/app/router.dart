import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shreeram_crm/core/auth/auth_controller.dart';
import 'package:shreeram_crm/features/auth/login_screen.dart';
import 'package:shreeram_crm/features/dashboard/dashboard_screen.dart';
import 'package:shreeram_crm/features/follow_ups/follow_ups_screen.dart';
import 'package:shreeram_crm/features/leads/lead_detail_screen.dart';
import 'package:shreeram_crm/features/leads/leads_screen.dart';
import 'package:shreeram_crm/features/meta/meta_connection_screen.dart';
import 'package:shreeram_crm/features/shell/app_shell.dart';
import 'package:shreeram_crm/features/site_visits/site_visits_screen.dart';
import 'package:shreeram_crm/features/stages/stages_settings_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: RouterRefresh(ref),
    redirect: (context, state) {
      final loggedIn = auth.user != null;
      final onLogin = state.matchedLocation == '/login';
      final isAdmin = auth.user?.isStaffAdmin ?? false;
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/dashboard';
      if (loggedIn && state.matchedLocation.startsWith('/meta') && !isAdmin) {
        return '/dashboard';
      }
      if (loggedIn && state.matchedLocation.startsWith('/stages') && !isAdmin) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
          GoRoute(
            path: '/leads',
            builder: (context, state) => LeadsScreen(
              initialStageId: state.uri.queryParameters['stage_id'],
              openCreate: state.uri.queryParameters['create'] == '1',
            ),
          ),
          GoRoute(
            path: '/leads/:id',
            builder: (context, state) => LeadDetailScreen(leadId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/follow-ups', builder: (context, state) => const FollowUpsScreen()),
          GoRoute(path: '/site-visits', builder: (context, state) => const SiteVisitsScreen()),
          GoRoute(path: '/meta', builder: (context, state) => const MetaConnectionScreen()),
          GoRoute(path: '/stages', builder: (context, state) => const StagesSettingsScreen()),
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
