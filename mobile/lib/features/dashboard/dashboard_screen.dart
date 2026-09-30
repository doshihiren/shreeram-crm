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
    final isAdmin = auth?.isStaffAdmin ?? false;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Dashboard unavailable: $e')),
      data: (data) {
        final stages = (data['stages'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final total = data['total_leads'] ?? 0;
        final newLead = stages.cast<Map<String, dynamic>?>().firstWhere(
              (s) => s?['code'] == 'NEW_LEAD',
              orElse: () => stages.isNotEmpty ? stages.first : null,
            );

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            ref.invalidate(metaStatusProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ClickMetric(
                      label: 'Total leads',
                      value: '$total',
                      onTap: () => context.go('/leads'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ClickMetric(
                      label: "Today's new",
                      value: '${data['today_new_leads']}',
                      onTap: () {
                        if (newLead == null) {
                          context.go('/leads');
                        } else {
                          context.go('/leads?stage_id=${newLead['id']}');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ClickMetric(
                      label: 'Overdue',
                      value: '${data['overdue_follow_ups']}',
                      alert: true,
                      onTap: () => context.go('/follow-ups'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: Text('Statuses', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  TextButton(onPressed: () => context.go('/leads'), child: const Text('All leads')),
                  if (isAdmin) TextButton(onPressed: () => context.go('/stages'), child: const Text('Edit')),
                ],
              ),
              const SizedBox(height: 12),
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
                      return SoftPanel(
                        padding: const EdgeInsets.all(16),
                        onTap: () => context.go('/leads?stage_id=${stage['id']}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
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
                          const Icon(Icons.hub_outlined, color: AppTheme.brandGoldDeep),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              connected
                                  ? 'Meta · ${meta?['page_name'] ?? 'connected'}'
                                  : 'Meta · connect webhook',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ClickMetric extends StatelessWidget {
  const _ClickMetric({
    required this.label,
    required this.value,
    required this.onTap,
    this.alert = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return SoftPanel(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: alert ? AppTheme.brandRed : AppTheme.brandGreenDark,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
