import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/network/lookup_providers.dart';
import 'package:shreeram_crm/shared/widgets/ui_kit.dart';

final siteVisitsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.watch(dioProvider).get('/site-visits', queryParameters: {'per_page': 50});
  return mapPaginator(res.data);
});

class SiteVisitsScreen extends ConsumerWidget {
  const SiteVisitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(siteVisitsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      children: [
        const SectionHeader(
          title: 'Site visits',
          subtitle: 'Planned and completed property visits.',
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (items) {
            if (items.isEmpty) {
              return SoftPanel(
                child: Text(
                  'No site visits scheduled yet. Open a lead and plan a visit.',
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
                                  item['scheduled_at'] != null
                                      ? DateFormat('dd MMM, hh:mm a')
                                          .format(DateTime.parse(item['scheduled_at']).toLocal())
                                      : 'Unscheduled',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          StatusPill(label: '${item['status']?['name'] ?? 'Planned'}'),
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
