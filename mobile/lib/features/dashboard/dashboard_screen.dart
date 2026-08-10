import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shreeram_crm/core/auth/auth_controller.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/shared/widgets/ui_kit.dart';

final dashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ref.watch(dioProvider).get('/dashboard/summary');
  return Map<String, dynamic>.from(res.data['data'] as Map);
});

final metaStatusProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(authControllerProvider).user;
  if (user == null || !user.permissions.contains('meta.manage')) return null;
  try {
    final res = await ref.watch(dioProvider).get('/meta/connection');
    return Map<String, dynamic>.from(res.data['data'] as Map);
  } catch (_) {
    return null;
  }
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).user;
    final async = ref.watch(dashboardProvider);
    final metaAsync = ref.watch(metaStatusProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Dashboard unavailable: $e')),
      data: (data) {
        final stages = (data['stages'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final total = data['total_leads'] ?? 0;
        final isAdmin = auth?.isStaffAdmin ?? false;

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            ref.invalidate(metaStatusProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
            children: [
              FadeSlideIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAdmin ? 'Command center' : 'My workspace',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isAdmin
                          ? 'Live pipeline health across your sales team.'
                          : 'Focus on the leads assigned to you today.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              FadeSlideIn(
                delay: const Duration(milliseconds: 40),
                child: SoftPanel(
                  padding: const EdgeInsets.all(24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth > 640;
                      return Flex(
                        direction: wide ? Axis.horizontal : Axis.vertical,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: wide ? 2 : 0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Total leads', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Text(
                                  '$total',
                                  style: Theme.of(context).textTheme.displayMedium?.copyWith(color: AppTheme.forest),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  total == 0
                                      ? 'No leads yet. Connect Meta or add a lead to start the funnel.'
                                      : 'Excludes duplicate submissions from funnel totals.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          if (wide) const SizedBox(width: 24) else const SizedBox(height: 18),
                          Expanded(
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _MiniStat(label: "Today's new", value: '${data['today_new_leads']}'),
                                _MiniStat(label: 'Follow-ups', value: '${data['today_follow_ups']}'),
                                _MiniStat(label: 'Site visits', value: '${data['today_site_visits']}'),
                                _MiniStat(label: 'Overdue', value: '${data['overdue_follow_ups']}', alert: true),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(height: 18),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 80),
                  child: metaAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (meta) {
                      final connected = meta?['status'] == 'connected';
                      return SoftPanel(
                        onTap: () => context.go('/meta'),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.forest.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.hub_outlined, color: AppTheme.forest),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Meta Lead Ads', style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                    connected
                                        ? 'Webhook connected${meta?['page_name'] != null ? ' · ${meta!['page_name']}' : ''}'
                                        : 'Connect webhook to receive Facebook lead forms automatically.',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            StatusPill(label: connected ? 'Live' : 'Setup needed', positive: connected),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right_rounded, color: AppTheme.muted),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: SectionHeader(
                  title: 'Pipeline by stage',
                  subtitle: 'Counts refresh from your database.',
                  action: TextButton(
                    onPressed: () => context.go('/leads'),
                    child: const Text('Open leads'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 140),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final stage in stages)
                      _StageTile(
                        name: '${stage['name']}',
                        count: stage['count'] as int? ?? 0,
                        lost: stage['is_lost'] == true,
                        onTap: () => context.go('/leads?stage_id=${stage['id']}'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              FadeSlideIn(
                delay: const Duration(milliseconds: 180),
                child: SectionHeader(
                  title: 'Quick actions',
                  subtitle: isAdmin ? 'Operate the floor without leaving this screen.' : 'Stay on top of outreach.',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ActionTile(
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'Add lead',
                    onTap: () => context.go('/leads?create=1'),
                  ),
                  _ActionTile(
                    icon: Icons.event_available_rounded,
                    label: 'Follow-ups',
                    onTap: () => context.go('/follow-ups'),
                  ),
                  if (isAdmin)
                    _ActionTile(
                      icon: Icons.hub_outlined,
                      label: 'Meta webhook',
                      onTap: () => context.go('/meta'),
                    ),
                  _ActionTile(
                    icon: Icons.home_work_outlined,
                    label: 'Site visits',
                    onTap: () => context.go('/site-visits'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.alert = false});

  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.forest.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: alert && value != '0' ? AppTheme.danger : AppTheme.forest,
                ),
          ),
        ],
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.name,
    required this.count,
    required this.onTap,
    this.lost = false,
  });

  final String name;
  final int count;
  final bool lost;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Text(
              '$count',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: lost ? AppTheme.danger : AppTheme.forest,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftPanel(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: SizedBox(
        width: 160,
        child: Row(
          children: [
            Icon(icon, color: AppTheme.forest),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
          ],
        ),
      ),
    );
  }
}
