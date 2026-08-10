import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shreeram_crm/core/auth/auth_controller.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/shared/widgets/ui_kit.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController(text: 'owner@shreeram.local');
  final _password = TextEditingController();
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_bootstrapped) return;
      _bootstrapped = true;
      await ref.read(authControllerProvider.notifier).bootstrap();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
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
            colors: [AppTheme.limestone, AppTheme.mist, Color(0xFFD7E5DC)],
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
                        Expanded(child: _LoginForm(email: _email, password: _password, auth: auth, ref: ref)),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const _BrandPanel(compact: true),
                        const SizedBox(height: 22),
                        _LoginForm(email: _email, password: _password, auth: auth, ref: ref),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
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
          Text('ShreeRam', style: Theme.of(context).textTheme.displayMedium?.copyWith(color: AppTheme.forest)),
          const SizedBox(height: 10),
          Text(
            'A calm, focused lead floor for real estate teams.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'From Meta Lead Ads to site visit — one pipeline, clear ownership, zero clutter.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          const StatusPill(label: 'UI build 2026-08-10-C'),
        ],
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.email,
    required this.password,
    required this.auth,
    required this.ref,
  });

  final TextEditingController email;
  final TextEditingController password;
  final AuthState auth;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Sign in', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          TextField(controller: email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 12),
          TextField(controller: password, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
          if (auth.error != null) ...[
            const SizedBox(height: 12),
            Text(auth.error!, style: const TextStyle(color: AppTheme.danger)),
          ],
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: auth.loading
                ? null
                : () => ref.read(authControllerProvider.notifier).login(email.text.trim(), password.text),
            child: Text(auth.loading ? 'Signing in…' : 'Continue'),
          ),
        ],
      ),
    );
  }
}
