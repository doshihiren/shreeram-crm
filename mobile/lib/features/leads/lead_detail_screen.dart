import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/network/lookup_providers.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/features/leads/leads_screen.dart';
import 'package:url_launcher/url_launcher.dart';

final leadDetailProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ref.watch(dioProvider).get('/leads/$id');
  return Map<String, dynamic>.from(res.data['data'] as Map);
});

final leadActivitiesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final res = await ref.watch(dioProvider).get('/leads/$id/activities', queryParameters: {'per_page': 30});
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
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _location = TextEditingController();
  final _remark = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  int? _stageId;
  DateTime? _nextFollowUp;
  bool _hydrated = false;
  bool _dirty = false;
  bool _saving = false;
  bool _savingRemark = false;
  String? _banner;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _location.dispose();
    _remark.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> lead) {
    if (_hydrated) return;
    _name.text = '${lead['name'] ?? ''}';
    _mobile.text = '${lead['mobile'] ?? ''}';
    _email.text = '${lead['email'] ?? ''}';
    _location.text = '${lead['preferred_location'] ?? ''}';
    _stageId = lead['stage']?['id'] as int?;
    if (lead['next_follow_up_at'] != null) {
      _nextFollowUp = DateTime.tryParse('${lead['next_follow_up_at']}')?.toLocal();
    }
    _hydrated = true;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
    if (_banner != null) setState(() => _banner = null);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Leave without saving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _saveLead() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _banner = null;
    });
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/leads/${widget.leadId}', data: {
        'name': _name.text.trim(),
        'mobile': _mobile.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'preferred_location': _location.text.trim().isEmpty ? null : _location.text.trim(),
        'next_follow_up_at': _nextFollowUp?.toUtc().toIso8601String(),
      });
      if (_stageId != null) {
        await dio.patch('/leads/${widget.leadId}/stage', data: {'lead_stage_id': _stageId});
      }
      if (_nextFollowUp != null && _remark.text.trim().isEmpty) {
        // optional: create follow-up record when date set
        try {
          await dio.post('/follow-ups', data: {
            'lead_id': int.parse(widget.leadId),
            'due_at': _nextFollowUp!.toUtc().toIso8601String(),
            'remarks': 'Next follow-up',
          });
        } catch (_) {}
      }
      ref.invalidate(leadDetailProvider(widget.leadId));
      ref.invalidate(leadActivitiesProvider(widget.leadId));
      ref.invalidate(leadsBoardProvider);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _hydrated = false;
        _banner = 'Lead saved successfully';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _banner = 'Could not save. Check fields and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveRemark() async {
    final body = _remark.text.trim();
    if (body.isEmpty) return;
    setState(() => _savingRemark = true);
    try {
      await ref.read(dioProvider).post('/leads/${widget.leadId}/remarks', data: {'body': body});
      if (_nextFollowUp != null) {
        await ref.read(dioProvider).post('/follow-ups', data: {
          'lead_id': int.parse(widget.leadId),
          'due_at': _nextFollowUp!.toUtc().toIso8601String(),
          'remarks': body,
        });
      }
      _remark.clear();
      ref.invalidate(leadActivitiesProvider(widget.leadId));
      ref.invalidate(leadDetailProvider(widget.leadId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note saved'), backgroundColor: AppTheme.brandGreenDark),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save note: $e'), backgroundColor: AppTheme.brandRed),
      );
    } finally {
      if (mounted) setState(() => _savingRemark = false);
    }
  }

  Future<void> _pickFollowUp() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _nextFollowUp ?? now.add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_nextFollowUp ?? now.add(const Duration(hours: 2))),
    );
    if (t == null) return;
    setState(() {
      _nextFollowUp = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
    _markDirty();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(leadDetailProvider(widget.leadId));
    final stagesAsync = ref.watch(stagesProvider);
    final activitiesAsync = ref.watch(leadActivitiesProvider(widget.leadId));

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) context.go('/leads');
      },
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white, Color(0xFFEEF7F0)],
              ),
              border: Border(bottom: BorderSide(color: AppTheme.line)),
            ),
            padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: () async {
                    if (await _confirmLeave() && context.mounted) context.go('/leads');
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lead details', style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        _dirty ? 'Unsaved edits — tap Save' : 'Edit, add notes, set next follow-up',
                        style: TextStyle(
                          color: _dirty ? AppTheme.brandGoldDeep : AppTheme.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_dirty)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.brandGold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('UNSAVED', style: TextStyle(color: AppTheme.brandGoldDeep, fontWeight: FontWeight.w800, fontSize: 11)),
                  ),
                FilledButton.icon(
                  onPressed: _saving || async.asData == null ? null : _saveLead,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ),
          if (_banner != null)
            Material(
              color: _banner!.startsWith('Lead saved')
                  ? AppTheme.brandGreen.withValues(alpha: 0.12)
                  : AppTheme.brandRed.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(_banner!, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (lead) {
                _hydrate(lead);
                final stages = stagesAsync.asData?.value ?? const <Map<String, dynamic>>[];
                final answers = (lead['form_answers'] as List<dynamic>? ?? [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                final platform = '${lead['platform'] ?? ''}';
                final mobile = _mobile.text.trim().isEmpty ? '${lead['mobile']}' : _mobile.text.trim();

                return Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                    children: [
                      Row(
                        children: [
                          _PlatformChip(platform: platform),
                          const SizedBox(width: 8),
                          if (lead['stage'] != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.stageColor('${lead['stage']?['code']}').withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${lead['stage']?['name']}',
                                style: TextStyle(
                                  color: AppTheme.stageColor('${lead['stage']?['code']}'),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () => launchUrl(Uri(scheme: 'tel', path: mobile)),
                                icon: const Icon(Icons.call_rounded),
                                label: const Text('Call'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  final m = mobile.replaceAll(RegExp(r'\D'), '');
                                  launchUrl(Uri.parse('https://wa.me/$m'), mode: LaunchMode.externalApplication);
                                },
                                icon: const Icon(Icons.chat_rounded),
                                label: const Text('WhatsApp'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Contact', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _name,
                                decoration: const InputDecoration(labelText: 'Customer name *', prefixIcon: Icon(Icons.person_outline)),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                onChanged: (_) => _markDirty(),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _mobile,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(labelText: 'Mobile *', prefixIcon: Icon(Icons.phone_outlined)),
                                validator: (v) => ((v?.replaceAll(RegExp(r'\D'), '') ?? '').length < 8) ? 'Invalid mobile' : null,
                                onChanged: (_) => _markDirty(),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _email,
                                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                                onChanged: (_) => _markDirty(),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _location,
                                decoration: const InputDecoration(labelText: 'City / location', prefixIcon: Icon(Icons.location_on_outlined)),
                                onChanged: (_) => _markDirty(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Status & follow-up', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              DropdownButtonFormField<int>(
                                value: _stageId,
                                decoration: const InputDecoration(labelText: 'Status', prefixIcon: Icon(Icons.flag_outlined)),
                                items: [
                                  for (final s in stages)
                                    DropdownMenuItem(
                                      value: s['id'] as int,
                                      child: Text('${s['name']}'),
                                    ),
                                ],
                                onChanged: (v) {
                                  setState(() => _stageId = v);
                                  _markDirty();
                                },
                              ),
                              const SizedBox(height: 12),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.event_available, color: AppTheme.brandGoldDeep),
                                title: Text(
                                  _nextFollowUp == null
                                      ? 'Set next follow-up date'
                                      : DateFormat('EEE, d MMM · h:mm a').format(_nextFollowUp!),
                                ),
                                subtitle: const Text('Tap to choose date & time'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _pickFollowUp,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (answers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('Form answers (Meta)', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                for (final a in answers)
                                  ListTile(
                                    dense: true,
                                    title: Text('${a['question']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                    subtitle: Text('${a['answer']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text('Notes', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              TextField(
                                controller: _remark,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  hintText: 'Call notes, buyer interest, next step…',
                                ),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.tonalIcon(
                                  onPressed: _savingRemark ? null : _saveRemark,
                                  icon: const Icon(Icons.notes_rounded, size: 18),
                                  label: Text(_savingRemark ? 'Saving…' : 'Add note'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Activity', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      activitiesAsync.when(
                        loading: () => const LinearProgressIndicator(minHeight: 2),
                        error: (e, _) => Text('$e'),
                        data: (items) {
                          if (items.isEmpty) {
                            return const Text('No notes yet.', style: TextStyle(color: AppTheme.muted));
                          }
                          return Card(
                            child: Column(
                              children: [
                                for (final a in items)
                                  ListTile(
                                    leading: Icon(
                                      a['type'] == 'remark' ? Icons.sticky_note_2_outlined : Icons.history,
                                      color: AppTheme.brandGreenDark,
                                    ),
                                    title: Text('${a['body'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    subtitle: Text(
                                      [
                                        if (a['user']?['name'] != null) '${a['user']['name']}',
                                        if (a['created_at'] != null)
                                          DateFormat('dd MMM, hh:mm a').format(DateTime.parse('${a['created_at']}').toLocal()),
                                      ].where((e) => e.toString().isNotEmpty).join(' · '),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _saveLead,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(_saving ? 'Saving…' : 'Save lead'),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.platform});
  final String platform;

  @override
  Widget build(BuildContext context) {
    final label = AppTheme.platformLabel(platform);
    final isIg = label == 'Instagram';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isIg ? const Color(0x14E1306C) : const Color(0x141877F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isIg ? const Color(0x55E1306C) : const Color(0x551877F2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isIg ? Icons.camera_alt_outlined : Icons.facebook, size: 14, color: isIg ? const Color(0xFFE1306C) : const Color(0xFF1877F2)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: isIg ? const Color(0xFFE1306C) : const Color(0xFF1877F2))),
        ],
      ),
    );
  }
}
