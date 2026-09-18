import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/network/lookup_providers.dart';
import 'package:shreeram_crm/shared/widgets/ui_kit.dart';

final followUpsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, due) async {
  final res = await ref.watch(dioProvider).get('/follow-ups', queryParameters: {
    'per_page': 50,
    if (due.isNotEmpty) 'due': due,
  });
  return mapPaginator(res.data);
});

class FollowUpsScreen extends ConsumerStatefulWidget {
  const FollowUpsScreen({super.key});

  @override
  ConsumerState<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends ConsumerState<FollowUpsScreen> {
  String _due = 'today';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(followUpsProvider(_due));

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      children: [
        const SectionHeader(
          title: 'Follow-ups',
          subtitle: 'Never miss a promised call-back.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(label: const Text('Today'), selected: _due == 'today', onSelected: (_) => setState(() => _due = 'today')),
            ChoiceChip(label: const Text('Overdue'), selected: _due == 'overdue', onSelected: (_) => setState(() => _due = 'overdue')),
            ChoiceChip(label: const Text('All'), selected: _due == '', onSelected: (_) => setState(() => _due = '')),
          ],
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (items) {
            if (items.isEmpty) {
              return SoftPanel(
                child: Text(
                  _due == 'overdue'
                      ? 'No overdue follow-ups. Nice work.'
                      : 'No follow-ups here yet. Open a lead and schedule one.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              );
            }
            return Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SoftPanel(
                      onTap: () {
                        final leadId = item['lead_id'] ?? item['lead']?['id'];
                        if (leadId != null) context.go('/leads/$leadId');
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  () {
                                    final leadName = item['lead']?['name'];
                                    return leadName != null ? '$leadName' : 'Lead #${item['lead_id']}';
                                  }(),
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item['due_at'] != null
                                      ? DateFormat('dd MMM, hh:mm a').format(DateTime.parse(item['due_at']).toLocal())
                                      : 'No due time',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          StatusPill(label: '${item['status']?['name'] ?? 'Pending'}'),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
