import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/network/lookup_providers.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

final leadsBoardProvider = FutureProvider.family<List<Map<String, dynamic>>, String?>((ref, stageId) async {
  final res = await ref.watch(dioProvider).get('/leads', queryParameters: {
    'per_page': 100,
    if (stageId != null && stageId.isNotEmpty) 'stage_id': stageId,
  });
  return (res.data['data'] as List<dynamic>? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
});

enum _LeadsView { board, table }

class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key, this.initialStageId, this.openCreate = false});

  final String? initialStageId;
  final bool openCreate;

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  String? _stageId;
  String _query = '';
  bool _createOpened = false;
  _LeadsView _view = _LeadsView.board;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _stageId = widget.initialStageId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.openCreate && !_createOpened) {
        _createOpened = true;
        _openCreateLead();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openCreateLead() async {
    final sources = await ref.read(sourcesProvider.future);
    final stages = await ref.read(stagesProvider.future);
    if (!mounted) return;

    final name = TextEditingController();
    final mobile = TextEditingController();
    final email = TextEditingController();
    final location = TextEditingController();
    final formKey = GlobalKey<FormState>();
    int? sourceId = sources.cast<Map<String, dynamic>?>().firstWhere(
          (s) => s?['code'] == 'OTHER',
          orElse: () => sources.isNotEmpty ? sources.first : null,
        )?['id'] as int?;
    String? error;
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Row(
                children: [
                  Container(
                    width: 10,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.brandGreen,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Add new lead')),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Enter name + mobile, then tap Save lead. Stage starts as New.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: name,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Customer name *',
                            hintText: 'e.g. Ravi Sharma',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: mobile,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Mobile number *',
                            hintText: 'e.g. 9876543210',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: (v) {
                            final t = v?.replaceAll(RegExp(r'\D'), '') ?? '';
                            if (t.length < 8) return 'Enter a valid mobile number';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email (optional)',
                            hintText: 'name@email.com',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: location,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Preferred location (optional)',
                            hintText: 'e.g. Adajan, Surat',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: sourceId,
                          decoration: const InputDecoration(
                            labelText: 'Lead source *',
                            prefixIcon: Icon(Icons.campaign_outlined),
                          ),
                          items: [
                            for (final s in sources)
                              DropdownMenuItem(value: s['id'] as int, child: Text('${s['name']}')),
                          ],
                          onChanged: saving ? null : (v) => setModal(() => sourceId = v),
                          validator: (v) => v == null ? 'Select a source' : null,
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.brandRed.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              error!,
                              style: const TextStyle(color: AppTheme.brandRed, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          stages.isEmpty
                              ? ''
                              : 'After save, the lead appears in “${stages.firstWhere((s) => s['code'] == 'NEW_LEAD', orElse: () => stages.first)['name']}”.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) return;
                          setModal(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await ref.read(dioProvider).post('/leads', data: {
                              'name': name.text.trim(),
                              'mobile': mobile.text.trim(),
                              'email': email.text.trim().isEmpty ? null : email.text.trim(),
                              'preferred_location':
                                  location.text.trim().isEmpty ? null : location.text.trim(),
                              'lead_source_id': sourceId,
                            });
                            if (context.mounted) Navigator.pop(context, true);
                          } catch (_) {
                            setModal(() {
                              saving = false;
                              error = 'Could not save lead. Check mobile/source and try again.';
                            });
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(saving ? 'Saving…' : 'Save lead'),
                ),
              ],
            );
          },
        );
      },
    );

    name.dispose();
    mobile.dispose();
    email.dispose();
    location.dispose();

    if (saved == true && mounted) {
      ref.invalidate(leadsBoardProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lead saved successfully — find it on the board'),
          backgroundColor: AppTheme.brandGreenDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _changeStage(Map<String, dynamic> lead, int stageId) async {
    try {
      await ref.read(dioProvider).patch('/leads/${lead['id']}/stage', data: {
        'lead_stage_id': stageId,
      });
      ref.invalidate(leadsBoardProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stage updated'),
          backgroundColor: AppTheme.brandGreenDark,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stage update failed: $e'), backgroundColor: AppTheme.brandRed),
      );
    }
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> leads) {
    if (_query.isEmpty) return leads;
    return leads.where((l) {
      final name = '${l['name']}'.toLowerCase();
      final mobile = '${l['mobile']}'.toLowerCase();
      return name.contains(_query) || mobile.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final stagesAsync = ref.watch(stagesProvider);
    final leadsAsync = ref.watch(leadsBoardProvider(_stageId));
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.brandGold,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Leads', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(width: 10),
                  leadsAsync.maybeWhen(
                    data: (leads) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.mist,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${_filter(leads).length}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  const Spacer(),
                  SegmentedButton<_LeadsView>(
                    segments: const [
                      ButtonSegment(value: _LeadsView.board, icon: Icon(Icons.view_kanban_outlined, size: 18), label: Text('Board')),
                      ButtonSegment(value: _LeadsView.table, icon: Icon(Icons.table_rows_outlined, size: 18), label: Text('Table')),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) => setState(() => _view = s.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return AppTheme.brandGreenDark;
                        return AppTheme.muted;
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: wide ? 260 : 140,
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search name or mobile',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _openCreateLead,
                    icon: const Icon(Icons.add),
                    label: Text(wide ? 'New lead' : 'New'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              stagesAsync.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (e, _) => Text('$e'),
                data: (stages) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'All',
                          selected: _stageId == null,
                          color: AppTheme.brandGreenDark,
                          onTap: () => setState(() => _stageId = null),
                        ),
                        for (final stage in stages) ...[
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: '${stage['name']}',
                            selected: _stageId == '${stage['id']}',
                            color: AppTheme.stageColor('${stage['code']}'),
                            onTap: () => setState(() => _stageId = '${stage['id']}'),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: leadsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load leads: $e')),
            data: (leads) {
              final filtered = _filter(leads);

              if (filtered.isEmpty) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.view_kanban_outlined, size: 42, color: AppTheme.brandGoldDeep),
                        const SizedBox(height: 12),
                        Text('No leads in this view', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text(
                          'Tap New lead to add one, or wait for Meta form submissions.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _openCreateLead,
                          icon: const Icon(Icons.add),
                          label: const Text('Add first lead'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return stagesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => Text('$e'),
                data: (stages) {
                  if (_view == _LeadsView.board) {
                    return _LeadsKanban(
                      leads: filtered,
                      stages: _stageId == null
                          ? stages
                          : stages.where((s) => '${s['id']}' == _stageId).toList(),
                      onOpen: (id) => context.go('/leads/$id'),
                      onStageChanged: _changeStage,
                    );
                  }
                  return _LeadsTable(
                    leads: filtered,
                    stages: stages,
                    onOpen: (id) => context.go('/leads/$id'),
                    onStageChanged: _changeStage,
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color.withValues(alpha: 0.45) : AppTheme.line),
        ),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w700, color: selected ? color : AppTheme.ink, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadsKanban extends StatelessWidget {
  const _LeadsKanban({
    required this.leads,
    required this.stages,
    required this.onOpen,
    required this.onStageChanged,
  });

  final List<Map<String, dynamic>> leads;
  final List<Map<String, dynamic>> stages;
  final void Function(String id) onOpen;
  final Future<void> Function(Map<String, dynamic> lead, int stageId) onStageChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        for (final stage in stages)
          _KanbanColumn(
            stage: stage,
            leads: leads.where((l) => l['stage']?['id'] == stage['id']).toList(),
            allStages: stages,
            onOpen: onOpen,
            onStageChanged: onStageChanged,
          ),
      ],
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.stage,
    required this.leads,
    required this.allStages,
    required this.onOpen,
    required this.onStageChanged,
  });

  final Map<String, dynamic> stage;
  final List<Map<String, dynamic>> leads;
  final List<Map<String, dynamic>> allStages;
  final void Function(String id) onOpen;
  final Future<void> Function(Map<String, dynamic> lead, int stageId) onStageChanged;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.stageColor('${stage['code']}');
    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${stage['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Text('${leads.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              itemCount: leads.length,
              itemBuilder: (context, i) {
                final lead = leads[i];
                return _LeadCard(
                  lead: lead,
                  stages: allStages,
                  accent: color,
                  onOpen: () => onOpen('${lead['id']}'),
                  onStageChanged: (id) => onStageChanged(lead, id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.lead,
    required this.stages,
    required this.accent,
    required this.onOpen,
    required this.onStageChanged,
  });

  final Map<String, dynamic> lead;
  final List<Map<String, dynamic>> stages;
  final Color accent;
  final VoidCallback onOpen;
  final ValueChanged<int> onStageChanged;

  @override
  Widget build(BuildContext context) {
    final name = '${lead['name']}';
    final mobile = '${lead['mobile']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 28,
                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Call',
                      onPressed: () => launchUrl(Uri(scheme: 'tel', path: mobile)),
                      icon: const Icon(Icons.call_rounded, size: 18, color: AppTheme.brandGreenDark),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(mobile, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w600)),
                if (lead['preferred_location'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${lead['preferred_location']}',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${lead['source']?['name'] ?? '—'}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PopupMenuButton<int>(
                      tooltip: 'Move stage',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18, color: AppTheme.brandGoldDeep),
                      onSelected: onStageChanged,
                      itemBuilder: (context) => [
                        for (final s in stages)
                          PopupMenuItem(
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
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeadsTable extends StatelessWidget {
  const _LeadsTable({
    required this.leads,
    required this.stages,
    required this.onOpen,
    required this.onStageChanged,
  });

  final List<Map<String, dynamic>> leads;
  final List<Map<String, dynamic>> stages;
  final void Function(String id) onOpen;
  final Future<void> Function(Map<String, dynamic> lead, int stageId) onStageChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                dataRowMinHeight: 58,
                dataRowMaxHeight: 68,
                headingRowHeight: 46,
                border: TableBorder(
                  horizontalInside: const BorderSide(color: AppTheme.line),
                  top: const BorderSide(color: AppTheme.line),
                  bottom: const BorderSide(color: AppTheme.line),
                  left: const BorderSide(color: AppTheme.line),
                  right: const BorderSide(color: AppTheme.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                columns: const [
                  DataColumn(label: Text('Lead')),
                  DataColumn(label: Text('Mobile')),
                  DataColumn(label: Text('Stage')),
                  DataColumn(label: Text('Source')),
                  DataColumn(label: Text('Location')),
                  DataColumn(label: Text('Created')),
                  DataColumn(label: Text('Quick actions')),
                ],
                rows: [
                  for (final lead in leads)
                    DataRow(
                      onSelectChanged: (_) => onOpen('${lead['id']}'),
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: AppTheme.brandGold.withValues(alpha: 0.2),
                                child: Text(
                                  '${lead['name']}'.isNotEmpty
                                      ? '${lead['name']}'.characters.first.toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: AppTheme.brandGoldDeep,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 180),
                                child: Text('${lead['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                        ),
                        DataCell(Text('${lead['mobile']}')),
                        DataCell(
                          DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: lead['stage']?['id'] as int?,
                              borderRadius: BorderRadius.circular(10),
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
                                if (v != null) onStageChanged(lead, v);
                              },
                            ),
                          ),
                        ),
                        DataCell(Text('${lead['source']?['name'] ?? '-'}')),
                        DataCell(Text('${lead['preferred_location'] ?? '-'}')),
                        DataCell(Text(
                          lead['created_at'] != null
                              ? DateFormat('dd MMM, hh:mm a').format(DateTime.parse(lead['created_at']).toLocal())
                              : '-',
                        )),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Call',
                                onPressed: () => launchUrl(Uri(scheme: 'tel', path: '${lead['mobile']}')),
                                icon: const Icon(Icons.call_rounded, color: AppTheme.brandGreenDark),
                              ),
                              IconButton(
                                tooltip: 'WhatsApp',
                                onPressed: () {
                                  final m = '${lead['mobile']}'.replaceAll(RegExp(r'\D'), '');
                                  launchUrl(Uri.parse('https://wa.me/$m'), mode: LaunchMode.externalApplication);
                                },
                                icon: const Icon(Icons.chat_rounded, color: AppTheme.brandGreen),
                              ),
                              IconButton(
                                tooltip: 'Open',
                                onPressed: () => onOpen('${lead['id']}'),
                                icon: const Icon(Icons.open_in_new_rounded, color: AppTheme.brandGoldDeep),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
