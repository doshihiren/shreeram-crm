import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

final leadDetailProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/leads/$id');
  return Map<String, dynamic>.from(res.data['data'] as Map);
});

final stagesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/lead-stages');
  final list = res.data['data'] as List<dynamic>? ?? [];
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

class LeadDetailScreen extends ConsumerStatefulWidget {
  const LeadDetailScreen({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends ConsumerState<LeadDetailScreen> {
  final _remark = TextEditingController();

  @override
  void dispose() {
    _remark.dispose();
    super.dispose();
  }

  Future<void> _call(String mobile) async {
    final uri = Uri(scheme: 'tel', path: mobile);
    await launchUrl(uri);
  }

  Future<void> _whatsapp(String mobile) async {
    final cleaned = mobile.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/$cleaned');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(leadDetailProvider(widget.leadId));
    final stagesAsync = ref.watch(stagesProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load lead: $e')),
      data: (lead) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('${lead['name']}', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text('${lead['mobile']} · ${lead['email'] ?? 'No email'}'),
            const SizedBox(height: 8),
            Text('Stage: ${lead['stage']?['name'] ?? ''} · Source: ${lead['source']?['name'] ?? ''}'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _call('${lead['mobile']}'),
                  icon: const Icon(Icons.call),
                  label: const Text('Call'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _whatsapp('${lead['mobile']}'),
                  icon: const Icon(Icons.chat),
                  label: const Text('WhatsApp'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Update stage', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            stagesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (stages) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final stage in stages)
                      ActionChip(
                        label: Text('${stage['name']}'),
                        onPressed: () async {
                          await ref.read(dioProvider).patch(
                            '/leads/${widget.leadId}/stage',
                            data: {'lead_stage_id': stage['id']},
                          );
                          ref.invalidate(leadDetailProvider(widget.leadId));
                        },
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text('Add remark', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _remark,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Notes from the conversation'),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.clay),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (_remark.text.trim().isEmpty) return;
                  await ref.read(dioProvider).post(
                    '/leads/${widget.leadId}/remarks',
                    data: {'body': _remark.text.trim()},
                  );
                  _remark.clear();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Remark saved')),
                  );
                },
                child: const Text('Save remark'),
              ),
            ),
          ],
        );
      },
    );
  }
}
