import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/network/lookup_providers.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';

class StagesSettingsScreen extends ConsumerStatefulWidget {
  const StagesSettingsScreen({super.key});

  @override
  ConsumerState<StagesSettingsScreen> createState() => _StagesSettingsScreenState();
}

class _StagesSettingsScreenState extends ConsumerState<StagesSettingsScreen> {
  bool _busy = false;

  Future<void> _edit(Map<String, dynamic> stage) async {
    final name = TextEditingController(text: '${stage['name']}');
    final sort = TextEditingController(text: '${stage['sort_order'] ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Status name *')),
            const SizedBox(height: 12),
            TextField(
              controller: sort,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sort order *',
                hintText: 'Lower number = earlier in pipeline',
                helperText: 'e.g. 1 = first, 100 = last',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Code: ${stage['code']}', style: Theme.of(ctx).textTheme.bodyMedium),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).patch('/lead-stages/${stage['id']}', data: {
        'name': name.text.trim(),
        'sort_order': int.tryParse(sort.text.trim()) ?? 0,
      });
      ref.invalidate(stagesProvider);
      ref.invalidate(stagesAdminProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status updated'), backgroundColor: AppTheme.brandGreenDark),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.brandRed),
        );
      }
    } finally {
      name.dispose();
      sort.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> stage, bool active) async {
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).patch('/lead-stages/${stage['id']}', data: {'is_active': active});
      ref.invalidate(stagesProvider);
      ref.invalidate(stagesAdminProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.brandRed),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addStatus() async {
    final name = TextEditingController();
    final code = TextEditingController();
    final sort = TextEditingController(text: '50');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *', hintText: 'e.g. Negotiation')),
            const SizedBox(height: 12),
            TextField(controller: code, decoration: const InputDecoration(labelText: 'Code *', hintText: 'e.g. NEGOTIATION')),
            const SizedBox(height: 12),
            TextField(
              controller: sort,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sort order *',
                hintText: 'Lower = earlier',
                helperText: 'Controls pipeline position',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post('/lead-stages', data: {
        'name': name.text.trim(),
        'code': code.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '_'),
        'sort_order': int.tryParse(sort.text.trim()) ?? 50,
      });
      ref.invalidate(stagesProvider);
      ref.invalidate(stagesAdminProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status added'), backgroundColor: AppTheme.brandGreenDark),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.brandRed),
        );
      }
    } finally {
      name.dispose();
      code.dispose();
      sort.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stagesAsync = ref.watch(stagesAdminProvider);

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Row(
            children: [
              Container(width: 8, height: 28, decoration: BoxDecoration(color: AppTheme.brandGold, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Statuses', style: Theme.of(context).textTheme.headlineMedium),
                    Text('Rename, sort order, add, or hide', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _addStatus,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: stagesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (stages) {
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: stages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final s = stages[i];
                  final active = s['is_active'] != false;
                  final color = AppTheme.stageColor('${s['code']}');
                  return Opacity(
                    opacity: active ? 1 : 0.55,
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: AppTheme.line),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.15),
                          child: Text('${s['sort_order'] ?? '-'}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                        ),
                        title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('${s['code']}${active ? '' : ' · hidden'}'),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Edit name / sort order',
                              onPressed: _busy ? null : () => _edit(s),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: active ? 'Hide status' : 'Show status',
                              onPressed: _busy ? null : () => _toggleActive(s, !active),
                              icon: Icon(active ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
