import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/network/lookup_providers.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/shared/widgets/ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';

final leadDetailProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ref.watch(dioProvider).get('/leads/$id');
  return Map<String, dynamic>.from(res.data['data'] as Map);
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
    await launchUrl(Uri(scheme: 'tel', path: mobile));
  }

  Future<void> _whatsapp(String mobile) async {
    final cleaned = mobile.replaceAll(RegExp(r'\D'), '');
    await launchUrl(Uri.parse('https://wa.me/$cleaned'), mode: LaunchMode.externalApplication);
  }

  Future<void> _scheduleFollowUp() async {
    final due = DateTime.now().add(const Duration(days: 1));
    await ref.read(dioProvider).post('/follow-ups', data: {
      'lead_id': int.parse(widget.leadId),
      'due_at': due.toIso8601String(),
      'remarks': 'Follow-up scheduled from lead detail',
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Follow-up scheduled for tomorrow')));
  }

  Future<void> _scheduleVisit() async {
    final when = DateTime.now().add(const Duration(days: 2, hours: 2));
    await ref.read(dioProvider).post('/site-visits', data: {
      'lead_id': int.parse(widget.leadId),
      'scheduled_at': when.toIso8601String(),
      'remarks': 'Site visit planned from lead detail',
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Site visit planned')));
    ref.invalidate(leadDetailProvider(widget.leadId));
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
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          children: [
            FadeSlideIn(
              child: SoftPanel(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${lead['name']}', style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text('${lead['mobile']}', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${lead['email'] ?? 'No email'} · ${lead['source']?['name'] ?? ''} · ${lead['stage']?['name'] ?? ''}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (lead['preferred_location'] != null) ...[
                      const SizedBox(height: 8),
                      Text('Prefers: ${lead['preferred_location']}', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _call('${lead['mobile']}'),
                          icon: const Icon(Icons.call_rounded),
                          label: const Text('Call'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _whatsapp('${lead['mobile']}'),
                          icon: const Icon(Icons.chat_rounded),
                          label: const Text('WhatsApp'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _scheduleFollowUp,
                          icon: const Icon(Icons.event_available_rounded),
                          label: const Text('Follow-up'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _scheduleVisit,
                          icon: const Icon(Icons.home_work_outlined),
                          label: const Text('Site visit'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text('Move stage', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
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
            Text('Remarks', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            SoftPanel(
              child: Column(
                children: [
                  TextField(
                    controller: _remark,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'What did the customer say?',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brass, foregroundColor: AppTheme.ink),
                      onPressed: () async {
                        if (_remark.text.trim().isEmpty) return;
                        final messenger = ScaffoldMessenger.of(context);
                        await ref.read(dioProvider).post(
                          '/leads/${widget.leadId}/remarks',
                          data: {'body': _remark.text.trim()},
                        );
                        _remark.clear();
                        messenger.showSnackBar(const SnackBar(content: Text('Remark saved')));
                      },
                      child: const Text('Save remark'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
