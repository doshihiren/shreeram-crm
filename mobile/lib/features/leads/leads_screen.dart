import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';

final leadsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/leads', queryParameters: {'per_page': 50});
  final list = res.data['data'] as List<dynamic>? ?? [];
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

class LeadsScreen extends ConsumerWidget {
  const LeadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leadsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load leads: $e')),
      data: (leads) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Leads', style: Theme.of(context).textTheme.headlineMedium),
                ),
                IconButton(
                  onPressed: () => ref.invalidate(leadsProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (leads.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text('No leads yet. Meta webhook or manual create will appear here.'),
              ),
            for (final lead in leads)
              InkWell(
                onTap: () => context.go('/leads/${lead['id']}'),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.forest.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${lead['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('${lead['mobile']} · ${lead['source']?['name'] ?? ''}'),
                          ],
                        ),
                      ),
                      Chip(label: Text('${lead['stage']?['name'] ?? ''}')),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
