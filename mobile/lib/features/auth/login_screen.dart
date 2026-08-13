import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shreeram_crm/core/auth/auth_controller.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/shared/widgets/brand_logo.dart';
import 'package:shreeram_crm/shared/widgets/ui_kit.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _bootstrapped = false;
  String? _pendingRole;

  static const _demos = <_DemoLogin>[
    _DemoLogin(
      role: 'Owner',
      subtitle: 'Full access · Meta · statuses',
      email: 'owner@shreeram.local',
      password: 'ChangeMeOwner1!',
      icon: Icons.workspace_premium_rounded,
      color: AppTheme.brandGoldDeep,
    ),
    _DemoLogin(
      role: 'Admin',
      subtitle: 'Team + pipeline management',
      email: 'admin@shreeram.local',
      password: 'ChangeMeAdmin1!',
      icon: Icons.admin_panel_settings_rounded,
      color: AppTheme.brandGreenDark,
    ),
    _DemoLogin(
      role: 'Sales',
      subtitle: 'My leads · call · follow-ups',
      email: 'sales@shreeram.local',
      password: 'ChangeMeSales1!',
      icon: Icons.headset_mic_rounded,
      color: const Color(0xFF2391CB),
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_bootstrapped) return;
      _bootstrapped = true;
      await ref.read(authControllerProvider.notifier).bootstrap();
    });
  }

  Future<void> _quickLogin(_DemoLogin demo) async {
    setState(() => _pendingRole = demo.role);
    await ref.read(authControllerProvider.notifier).login(demo.email, demo.password);
    if (mounted) setState(() => _pendingRole = null);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.limestone, AppTheme.mist, Color(0xFFE8F0E9), Color(0xFFF6EFDA)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 980 : 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: wide
                  ? Row(
                      children: [
                        const Expanded(child: _BrandPanel()),
                        const SizedBox(width: 28),
                        Expanded(child: _QuickLoginPanel(auth: auth, pendingRole: _pendingRole, demos: _demos, onLogin: _quickLogin)),
                      ],
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        const _BrandPanel(compact: true),
                        const SizedBox(height: 22),
                        _QuickLoginPanel(auth: auth, pendingRole: _pendingRole, demos: _demos, onLogin: _quickLogin),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoLogin {
  const _DemoLogin({
    required this.role,
    required this.subtitle,
    required this.email,
    required this.password,
    required this.icon,
    required this.color,
  });

  final String role;
  final String subtitle;
  final String email;
  final String password;
  final IconData icon;
  final Color color;
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SoftPanel(
      padding: EdgeInsets.all(compact ? 24 : 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandLogo(height: compact ? 64 : 88, showWordmark: false),
          const SizedBox(height: 18),
          Text(
            'Lead CRM for your sales floor',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.ink),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap a role to enter — no password typing for now.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          const StatusPill(label: 'UI build 2026-08-13-QUICKLOGIN'),
        ],
      ),
    );
  }
}

class _QuickLoginPanel extends StatelessWidget {
  const _QuickLoginPanel({
    required this.auth,
    required this.pendingRole,
    required this.demos,
    required this.onLogin,
  });

  final AuthState auth;
  final String? pendingRole;
  final List<_DemoLogin> demos;
  final Future<void> Function(_DemoLogin demo) onLogin;

  @override
  Widget build(BuildContext context) {
    return SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Continue as', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Demo access — we will lock this down before go-live.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          for (final demo in demos) ...[
            _RoleButton(
              demo: demo,
              loading: auth.loading && pendingRole == demo.role,
              disabled: auth.loading,
              onTap: () => onLogin(demo),
            ),
            const SizedBox(height: 12),
          ],
          if (auth.error != null) ...[
            const SizedBox(height: 4),
            Text(auth.error!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({
    required this.demo,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  final _DemoLogin demo;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: demo.color.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              colors: [
                demo.color.withValues(alpha: 0.08),
                Colors.white,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: demo.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(demo.icon, color: demo.color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(demo.role, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: demo.color)),
                      const SizedBox(height: 2),
                      Text(demo.subtitle, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                if (loading)
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(Icons.arrow_forward_rounded, color: demo.color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
