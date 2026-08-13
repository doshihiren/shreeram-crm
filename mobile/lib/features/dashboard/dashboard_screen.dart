import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shreeram_crm/core/auth/auth_controller.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/shared/widgets/brand_logo.dart';
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
    final isAdmin = auth?.isStaffAdmin ?? false;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Dashboard unavailable: $e')),
      data: (data) {
        final stages = (data['stages'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final total = data['total_leads'] ?? 0;

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            ref.invalidate(metaStatusProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.brandGreenDeep, AppTheme.brandGreenDark, Color(0xFF146B2C)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandLogo(height: 48, showWordmark: false),
                    const SizedBox(height: 16),
                    Text(
                      isAdmin ? 'Sales command center' : 'My pipeline',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Status overview · follow-ups · Meta leads',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _HeroMetric(label: 'Total leads', value: '$total'),
                        const SizedBox(width: 12),
                        _HeroMetric(label: "Today's new", value: '${data['today_new_leads']}'),
                        const SizedBox(width: 12),
                        _HeroMetric(label: 'Overdue', value: '${data['overdue_follow_ups']}', alert: true),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text('All statuses', style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  TextButton(onPressed: () => context.go('/leads'), child: const Text('Open board')),
                  if (isAdmin)
                    TextButton(onPressed: () => context.go('/stages'), child: const Text('Edit statuses')),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Tap a status to open those leads. Admin can rename/add statuses anytime.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final cross = w >= 1100 ? 4 : (w >= 700 ? 3 : 2);
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: stages.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cross,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.35,
                    ),
                    itemBuilder: (context, i) {
                      final stage = stages[i];
                      final code = '${stage['code'] ?? ''}';
                      final color = AppTheme.stageColor(code);
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => context.go('/leads?stage_id=${stage['id']}'),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                ),
                                const Spacer(),
                                Text(
                                  '${stage['count'] ?? 0}',
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${stage['name']}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              if (isAdmin) ...[
                const SizedBox(height: 22),
                metaAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (meta) {
                    final connected = meta?['status'] == 'connected';
                    return SoftPanel(
                      onTap: () => context.go('/meta'),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppTheme.brandGold.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.hub_outlined, color: AppTheme.brandGoldDeep),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Meta Lead Ads', style: Theme.of(context).textTheme.titleMedium),
                                Text(
                                  connected
                                      ? 'Live · ${meta?['page_name'] ?? 'connected'}'
                                      : 'Connect webhook to receive Facebook / Instagram leads',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          StatusPill(label: connected ? 'Live' : 'Setup', positive: connected),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 22),
              Text('Quick actions', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ActionChip(icon: Icons.person_add_alt_1_rounded, label: 'Add lead', onTap: () => context.go('/leads?create=1')),
                  _ActionChip(icon: Icons.event_available_rounded, label: 'Follow-ups', onTap: () => context.go('/follow-ups')),
                  _ActionChip(icon: Icons.home_work_outlined, label: 'Site visits', onTap: () => context.go('/site-visits')),
                  if (isAdmin) _ActionChip(icon: Icons.tune_rounded, label: 'Statuses', onTap: () => context.go('/stages')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value, this.alert = false});
  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.brandGold.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: alert && value != '0' ? const Color(0xFFFFCDD2) : AppTheme.brandGoldSoft,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 160,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.line),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.brandGreenDark, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
        ),
      ),
    );
  }
}
