import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';

final dashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/dashboard/summary');
  return Map<String, dynamic>.from(res.data['data'] as Map);
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load dashboard: $e')),
      data: (data) {
        final stages = (data['stages'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Owner dashboard', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            const Text('Live counters from your database — not demo placeholders.'),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Metric(label: 'Total Leads', value: '${data['total_leads']}'),
                _Metric(label: "Today's New", value: '${data['today_new_leads']}'),
                _Metric(label: "Today's Follow-ups", value: '${data['today_follow_ups']}'),
                _Metric(label: "Today's Site Visits", value: '${data['today_site_visits']}'),
                _Metric(label: 'Overdue Follow-ups', value: '${data['overdue_follow_ups']}'),
                _Metric(label: 'Duplicates', value: '${data['duplicate_submissions']}'),
              ],
            ),
            const SizedBox(height: 28),
            Text('By stage', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final stage in stages)
                  _Metric(
                    label: '${stage['name']}',
                    value: '${stage['count']}',
                    compact: true,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.compact = false});

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 150 : 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, AppTheme.mist],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.forest.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.forest,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
