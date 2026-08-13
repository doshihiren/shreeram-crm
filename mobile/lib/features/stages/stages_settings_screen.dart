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

  Future<void> _rename(Map<String, dynamic> stage) async {
    final ctrl = TextEditingController(text: '${stage['name']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename status'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Status name')),
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
        'name': ctrl.text.trim(),
      });
      ref.invalidate(stagesProvider);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> stage, bool active) async {
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).patch('/lead-stages/${stage['id']}', data: {'is_active': active});
      ref.invalidate(stagesProvider);
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
        'sort_order': 50,
      });
      ref.invalidate(stagesProvider);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stagesAsync = ref.watch(stagesProvider);

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
                    Text('Lead statuses', style: Theme.of(context).textTheme.headlineMedium),
                    Text('Admin can rename, add, or hide statuses', style: Theme.of(context).textTheme.bodyMedium),
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
              // Show all including inactive? API only returns active from lookup.
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: stages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final s = stages[i];
                  final color = AppTheme.stageColor('${s['code']}');
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AppTheme.line),
                      ),
                      leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(Icons.flag, color: color, size: 18)),
                      title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${s['code']} · sort ${s['sort_order'] ?? '-'}'),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Rename',
                            onPressed: _busy ? null : () => _rename(s),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Hide status',
                            onPressed: _busy ? null : () => _toggleActive(s, false),
                            icon: const Icon(Icons.visibility_off_outlined),
                          ),
                        ],
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
