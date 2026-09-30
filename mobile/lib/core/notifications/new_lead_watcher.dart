import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shreeram_crm/core/auth/auth_controller.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/features/leads/leads_screen.dart';

/// Polls for newly arrived leads (~every 45s) and shows an in-app SnackBar alert.
/// Primary notification for Flutter web without push certificates.
class NewLeadWatcher extends ConsumerStatefulWidget {
  const NewLeadWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NewLeadWatcher> createState() => _NewLeadWatcherState();
}

class _NewLeadWatcherState extends ConsumerState<NewLeadWatcher> with WidgetsBindingObserver {
  static const _prefsKey = 'new_lead_last_seen_id';
  Timer? _timer;
  int? _lastSeenId;
  bool _ready = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
    }
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSeenId = prefs.getInt(_prefsKey);
    _ready = true;
    // Seed baseline quietly on first run so we don't alert for existing leads.
    await _check(seedOnly: _lastSeenId == null);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _check());
  }

  Future<void> _persist(int id) async {
    _lastSeenId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, id);
  }

  Future<void> _check({bool seedOnly = false}) async {
    if (!_ready || _checking) return;
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    _checking = true;
    try {
      final res = await ref.read(dioProvider).get('/leads', queryParameters: {
        'per_page': 8,
        'page': 1,
      });
      final list = (res.data['data'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (list.isEmpty) return;

      final newestId = (list.first['id'] as num).toInt();
      final previous = _lastSeenId;

      if (seedOnly || previous == null) {
        await _persist(newestId);
        return;
      }
      if (newestId <= previous) return;

      final fresh = list.where((l) => (l['id'] as num).toInt() > previous).toList();
      await _persist(newestId);
      ref.invalidate(leadsBoardProvider);

      if (!mounted || fresh.isEmpty) return;
      final first = fresh.first;
      final name = '${first['name'] ?? 'New lead'}';
      final count = fresh.length;
      final title = count == 1 ? 'New lead arrived: $name' : '$count new leads (latest: $name)';

      if (kDebugMode) {
        debugPrint('[NewLeadWatcher] $title');
      }

      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.clearSnackBars();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: AppTheme.brandGreenDark,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Open',
            textColor: const Color(0xFFF6EFDA),
            onPressed: () {
              if (!mounted) return;
              context.go('/leads/${first['id']}');
            },
          ),
        ),
      );
    } catch (_) {
      // Ignore transient poll errors.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
