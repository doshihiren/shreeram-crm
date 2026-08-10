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
        content: const Text('You edited this lead but have not tapped Save yet. Leave without saving?'),
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
      });
      if (_stageId != null) {
        await dio.patch('/leads/${widget.leadId}/stage', data: {
          'lead_stage_id': _stageId,
        });
      }
      ref.invalidate(leadDetailProvider(widget.leadId));
      ref.invalidate(leadsBoardProvider);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _hydrated = false;
        _banner = 'Lead saved successfully';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lead saved'),
          backgroundColor: AppTheme.brandGreenDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _banner = 'Could not save. Check the fields and try again.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: AppTheme.brandRed),
      );
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
      _remark.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remark added'),
          backgroundColor: AppTheme.brandGreenDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save remark: $e'), backgroundColor: AppTheme.brandRed),
      );
    } finally {
      if (mounted) setState(() => _savingRemark = false);
    }
  }

  Future<void> _scheduleFollowUp() async {
    final note = TextEditingController(text: 'Follow-up call');
    DateTime when = DateTime.now().add(const Duration(hours: 2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Schedule follow-up'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'What should we do?',
                  hintText: 'e.g. Call about site visit',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(DateFormat('EEE, d MMM · h:mm a').format(when)),
                subtitle: const Text('Tap to change date & time'),
                trailing: const Icon(Icons.event),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: when,
                  );
                  if (d == null || !ctx.mounted) return;
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(when),
                  );
                  if (t == null) return;
                  setLocal(() {
                    when = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Schedule')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dioProvider).post('/follow-ups', data: {
        'lead_id': int.parse(widget.leadId),
        'due_at': when.toUtc().toIso8601String(),
        'remarks': note.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow-up scheduled'), backgroundColor: AppTheme.brandGreenDark),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not schedule: $e'), backgroundColor: AppTheme.brandRed),
      );
    } finally {
      note.dispose();
    }
  }

  Future<void> _scheduleVisit() async {
    final when = DateTime.now().add(const Duration(days: 2, hours: 2));
    try {
      await ref.read(dioProvider).post('/site-visits', data: {
        'lead_id': int.parse(widget.leadId),
        'scheduled_at': when.toIso8601String(),
        'remarks': 'Site visit planned from lead detail',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Site visit planned'), backgroundColor: AppTheme.brandGreenDark),
      );
      ref.invalidate(leadDetailProvider(widget.leadId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not plan visit: $e'), backgroundColor: AppTheme.brandRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(leadDetailProvider(widget.leadId));
    final stagesAsync = ref.watch(stagesProvider);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) context.go('/leads');
      },
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to board',
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
                        _dirty ? 'Unsaved edits — tap Save' : 'Edit fields, then tap Save',
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
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.brandGold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'UNSAVED',
                        style: TextStyle(
                          color: AppTheme.brandGoldDeep,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _saving || async.asData == null ? null : _saveLead,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandGreenDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_banner != null)
            Material(
              color: _banner!.startsWith('Lead saved')
                  ? AppTheme.brandGreen.withValues(alpha: 0.12)
                  : AppTheme.brandRed.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _banner!.startsWith('Lead saved') ? Icons.check_circle : Icons.error_outline,
                      size: 18,
                      color: _banner!.startsWith('Lead saved') ? AppTheme.brandGreenDark : AppTheme.brandRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_banner!, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load lead: $e')),
              data: (lead) {
                _hydrate(lead);
                final stages = stagesAsync.asData?.value ?? const <Map<String, dynamic>>[];
                final mobile = _mobile.text.trim().isEmpty ? '${lead['mobile']}' : _mobile.text.trim();

                return Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                    children: [
                      Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: AppTheme.line),
                        ),
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
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Contact', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _SectionCard(
                        children: [
                          TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'Customer name *',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                            onChanged: (_) => _markDirty(),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _mobile,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Mobile *',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: (v) {
                              final t = v?.replaceAll(RegExp(r'\D'), '') ?? '';
                              if (t.length < 8) return 'Enter a valid mobile number';
                              return null;
                            },
                            onChanged: (_) => _markDirty(),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email (optional)',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                            onChanged: (_) => _markDirty(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Pipeline', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _SectionCard(
                        children: [
                          DropdownButtonFormField<int>(
                            value: _stageId,
                            decoration: const InputDecoration(
                              labelText: 'Stage',
                              prefixIcon: Icon(Icons.flag_outlined),
                            ),
                            items: [
                              for (final s in stages)
                                DropdownMenuItem(
                                  value: s['id'] as int,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: AppTheme.stageColor('${s['code']}'),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('${s['name']}'),
                                    ],
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              setState(() => _stageId = v);
                              _markDirty();
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _location,
                            decoration: const InputDecoration(
                              labelText: 'Preferred location',
                              hintText: 'e.g. Adajan, Surat',
                              prefixIcon: Icon(Icons.location_on_outlined),
                            ),
                            onChanged: (_) => _markDirty(),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Source: ${lead['source']?['name'] ?? '—'}'
                            '${lead['assigned_to'] != null ? ' · Owner: ${lead['assigned_to']?['name']}' : ''}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Add remark', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _SectionCard(
                        children: [
                          TextField(
                            controller: _remark,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'What did the buyer say? Budget, timing, next step…',
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              onPressed: _savingRemark ? null : _saveRemark,
                              icon: _savingRemark
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.notes_rounded, size: 18),
                              label: Text(_savingRemark ? 'Saving…' : 'Add remark'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _saveLead,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(_saving ? 'Saving…' : 'Save lead'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: AppTheme.brandGreenDark,
                        ),
                      ),
                      if (_dirty)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                            'Changes are not auto-saved. Tap Save lead when you are done.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: children),
      ),
    );
  }
}
