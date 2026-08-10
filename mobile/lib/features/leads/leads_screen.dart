import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/network/lookup_providers.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/shared/widgets/ui_kit.dart';

final leadsProvider = FutureProvider.family<List<Map<String, dynamic>>, String?>((ref, stageId) async {
  final res = await ref.watch(dioProvider).get('/leads', queryParameters: {
    'per_page': 50,
    if (stageId != null && stageId.isNotEmpty) 'stage_id': stageId,
  });
  return (res.data['data'] as List<dynamic>? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
});

class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key, this.initialStageId, this.openCreate = false});

  final String? initialStageId;
  final bool openCreate;

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  String? _stageId;
  bool _createOpened = false;

  @override
  void initState() {
    super.initState();
    _stageId = widget.initialStageId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.openCreate && !_createOpened) {
        _createOpened = true;
        _openCreate();
      }
    });
  }

  Future<void> _openCreate() async {
    final sources = await ref.read(sourcesProvider.future);
    if (!mounted) return;
    final name = TextEditingController();
    final mobile = TextEditingController();
    final email = TextEditingController();
    final location = TextEditingController();
    int? sourceId = sources.isNotEmpty ? sources.first['id'] as int : null;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add lead', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text('Manual capture while Meta webhook is being connected.', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                  const SizedBox(height: 10),
                  TextField(controller: mobile, decoration: const InputDecoration(labelText: 'Mobile'), keyboardType: TextInputType.phone),
                  const SizedBox(height: 10),
                  TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 10),
                  TextField(controller: location, decoration: const InputDecoration(labelText: 'Preferred location')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: sourceId,
                    items: [
                      for (final s in sources)
                        DropdownMenuItem(value: s['id'] as int, child: Text('${s['name']}')),
                    ],
                    onChanged: (v) => setModalState(() => sourceId = v),
                    decoration: const InputDecoration(labelText: 'Lead source'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      if (name.text.trim().isEmpty || mobile.text.trim().isEmpty || sourceId == null) return;
                      await ref.read(dioProvider).post('/leads', data: {
                        'name': name.text.trim(),
                        'mobile': mobile.text.trim(),
                        'email': email.text.trim().isEmpty ? null : email.text.trim(),
                        'preferred_location': location.text.trim().isEmpty ? null : location.text.trim(),
                        'lead_source_id': sourceId,
                      });
                      if (context.mounted) Navigator.pop(context, true);
                    },
                    child: const Text('Save lead'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    name.dispose();
    mobile.dispose();
    email.dispose();
    location.dispose();
    if (saved == true) {
      ref.invalidate(leadsProvider(_stageId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stagesAsync = ref.watch(stagesProvider);
    final leadsAsync = ref.watch(leadsProvider(_stageId));

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      children: [
        SectionHeader(
          title: 'Leads',
          subtitle: 'Search, qualify, and move every enquiry through the funnel.',
          action: ElevatedButton.icon(
            onPressed: _openCreate,
            icon: const Icon(Icons.add),
            label: const Text('Add lead'),
          ),
        ),
        const SizedBox(height: 16),
        stagesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (stages) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _stageId == null,
                    onSelected: (_) => setState(() => _stageId = null),
                  ),
                  const SizedBox(width: 8),
                  for (final stage in stages) ...[
                    ChoiceChip(
                      label: Text('${stage['name']}'),
                      selected: _stageId == '${stage['id']}',
                      onSelected: (_) => setState(() => _stageId = '${stage['id']}'),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        leadsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Failed to load leads: $e'),
          data: (leads) {
            if (leads.isEmpty) {
              return SoftPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No leads in this view yet', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Connect Meta Lead Ads to receive forms automatically, or add a lead manually to test the pipeline.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      children: [
                        ElevatedButton(onPressed: _openCreate, child: const Text('Add lead')),
                        OutlinedButton(onPressed: () => context.go('/meta'), child: const Text('Connect Meta')),
                      ],
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                for (final lead in leads)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SoftPanel(
                      onTap: () => context.go('/leads/${lead['id']}'),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.forest.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '${lead['name']}'.isNotEmpty ? '${lead['name']}'.substring(0, 1).toUpperCase() : '?',
                              style: const TextStyle(color: AppTheme.forest, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${lead['name']}', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 4),
                                Text(
                                  '${lead['mobile']} · ${lead['source']?['name'] ?? 'Source'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          StatusPill(label: '${lead['stage']?['name'] ?? ''}'),
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
