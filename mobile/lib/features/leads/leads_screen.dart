import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/network/lookup_providers.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/features/leads/stage_change_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class LeadsPageQuery {
  const LeadsPageQuery({this.stageId, this.page = 1});
  final String? stageId;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is LeadsPageQuery && other.stageId == stageId && other.page == page;

  @override
  int get hashCode => Object.hash(stageId, page);
}

final leadsBoardProvider = FutureProvider.family<Map<String, dynamic>, LeadsPageQuery>((ref, query) async {
  final res = await ref.watch(dioProvider).get('/leads', queryParameters: {
    'per_page': 50,
    'page': query.page,
    if (query.stageId != null && query.stageId!.isNotEmpty) 'stage_id': query.stageId,
  });
  final raw = res.data;
  final list = (raw['data'] as List<dynamic>? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  final meta = Map<String, dynamic>.from((raw['meta'] as Map?) ?? const {});
  return {'data': list, 'meta': meta};
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
  bool _defaultStageApplied = false;
  int _page = 1;
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
  void didUpdateWidget(covariant LeadsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStageId != oldWidget.initialStageId) {
      setState(() {
        _stageId = widget.initialStageId;
        _page = 1;
        _defaultStageApplied = widget.initialStageId != null;
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _applyDefaultNewLead(List<Map<String, dynamic>> stages) {
    if (_defaultStageApplied || widget.initialStageId != null || _stageId != null) return;
    _defaultStageApplied = true;
    Map<String, dynamic>? neu;
    for (final s in stages) {
      if (s['code'] == 'NEW_LEAD') {
        neu = s;
        break;
      }
    }
    neu ??= stages.isNotEmpty ? stages.first : null;
    if (neu == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _stageId = '${neu!['id']}';
        _page = 1;
      });
    });
  }

  Future<void> _changeStage(Map<String, dynamic> lead, int stageId) async {
    final stages = await ref.read(stagesProvider.future);
    if (!mounted) return;
    final result = await showStageChangeDialog(
      context,
      stages: stages,
      selectedStageId: stageId,
      leadName: '${lead['name'] ?? ''}',
    );
    if (result == null) return;
    try {
      await ref.read(dioProvider).patch('/leads/${lead['id']}/stage', data: {
        'lead_stage_id': result.stageId,
        if (result.followUpAt != null) 'next_follow_up_at': result.followUpAt!.toUtc().toIso8601String(),
        if (result.remarks != null) 'remarks': result.remarks,
      });
      ref.invalidate(leadsBoardProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status updated'),
          backgroundColor: AppTheme.brandGreenDark,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status update failed: $e'), backgroundColor: AppTheme.brandRed),
      );
    }
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
    int? sourceId;
    for (final s in sources) {
      if (s['code'] == 'OTHER') {
        sourceId = s['id'] as int?;
        break;
      }
    }
    sourceId ??= sources.isNotEmpty ? sources.first['id'] as int? : null;
    String? error;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return AlertDialog(
              title: const Text('Add new lead'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Customer name *'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: mobile,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Mobile *'),
                          validator: (v) {
                            final t = v?.replaceAll(RegExp(r'\D'), '') ?? '';
                            if (t.length < 8) return 'Enter a valid mobile';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Email (optional)')),
                        const SizedBox(height: 12),
                        TextFormField(controller: location, decoration: const InputDecoration(labelText: 'Location (optional)')),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: sourceId,
                          decoration: const InputDecoration(labelText: 'Source *'),
                          items: [
                            for (final s in sources)
                              DropdownMenuItem(value: s['id'] as int, child: Text('${s['name']}')),
                          ],
                          onChanged: saving ? null : (v) => setModal(() => sourceId = v),
                          validator: (v) => v == null ? 'Select a source' : null,
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(error!, style: const TextStyle(color: AppTheme.brandRed, fontWeight: FontWeight.w700)),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          stages.isEmpty
                              ? ''
                              : 'Saved leads start in “${stages.firstWhere((s) => s['code'] == 'NEW_LEAD', orElse: () => stages.first)['name']}”.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
                ElevatedButton(
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
                              'preferred_location': location.text.trim().isEmpty ? null : location.text.trim(),
                              'lead_source_id': sourceId,
                            });
                            if (context.mounted) Navigator.pop(context, true);
                          } catch (_) {
                            setModal(() {
                              saving = false;
                              error = 'Could not save lead.';
                            });
                          }
                        },
                  child: Text(saving ? 'Saving…' : 'Save lead'),
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
        const SnackBar(content: Text('Lead saved'), backgroundColor: AppTheme.brandGreenDark),
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
    final leadsAsync = ref.watch(leadsBoardProvider(LeadsPageQuery(stageId: _stageId, page: _page)));
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
                  Expanded(
                    child: leadsAsync.maybeWhen(
                      data: (page) {
                        final total = page['meta']?['total'] ?? (page['data'] as List).length;
                        final showing = _filter(List<Map<String, dynamic>>.from(page['data'] as List)).length;
                        return Text(
                          'Leads · $showing shown · $total total',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        );
                      },
                      orElse: () => Text('Leads', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  if (wide) ...[
                    SegmentedButton<_LeadsView>(
                      segments: const [
                        ButtonSegment(value: _LeadsView.board, icon: Icon(Icons.view_kanban_outlined, size: 18), label: Text('Board')),
                        ButtonSegment(value: _LeadsView.table, icon: Icon(Icons.table_rows_outlined, size: 18), label: Text('Table')),
                      ],
                      selected: {_view},
                      onSelectionChanged: (s) => setState(() => _view = s.first),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 240,
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name or mobile', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  ElevatedButton.icon(
                    onPressed: _openCreateLead,
                    icon: const Icon(Icons.add),
                    label: Text(wide ? 'New lead' : 'New'),
                  ),
                ],
              ),
              if (!wide) ...[
                const SizedBox(height: 10),
                SegmentedButton<_LeadsView>(
                  segments: const [
                    ButtonSegment(value: _LeadsView.board, icon: Icon(Icons.view_kanban_outlined, size: 18), label: Text('Board')),
                    ButtonSegment(value: _LeadsView.table, icon: Icon(Icons.table_rows_outlined, size: 18), label: Text('Table')),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name or mobile', isDense: true),
                ),
              ],
              const SizedBox(height: 12),
              stagesAsync.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (e, _) => Text('$e'),
                data: (stages) {
                  _applyDefaultNewLead(stages);
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'All',
                          selected: _stageId == null,
                          color: AppTheme.brandGreenDark,
                          onTap: () => setState(() {
                            _stageId = null;
                            _page = 1;
                            _defaultStageApplied = true;
                          }),
                        ),
                        for (final stage in stages) ...[
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: '${stage['name']}',
                            selected: _stageId == '${stage['id']}',
                            color: AppTheme.stageColor('${stage['code']}'),
                            onTap: () => setState(() {
                              _stageId = '${stage['id']}';
                              _page = 1;
                              _defaultStageApplied = true;
                            }),
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
            data: (page) {
              final leads = List<Map<String, dynamic>>.from(page['data'] as List? ?? const []);
              final meta = Map<String, dynamic>.from(page['meta'] as Map? ?? const {});
              final filtered = _filter(leads);
              final lastPage = (meta['last_page'] as num?)?.toInt() ?? 1;
              final currentPage = (meta['current_page'] as num?)?.toInt() ?? _page;
              final total = (meta['total'] as num?)?.toInt() ?? filtered.length;

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('No leads in this view', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(onPressed: _openCreateLead, icon: const Icon(Icons.add), label: const Text('Add lead')),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  Expanded(
                    child: stagesAsync.when(
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
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: AppTheme.line)),
                    ),
                    child: Row(
                      children: [
                        Text('Page $currentPage of $lastPage · $total leads', style: Theme.of(context).textTheme.bodyMedium),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: currentPage <= 1 ? null : () => setState(() => _page = currentPage - 1),
                          child: const Text('Previous'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: currentPage >= lastPage ? null : () => setState(() => _page = currentPage + 1),
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                  ),
                ],
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
                    if ('${lead['platform'] ?? ''}'.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.mist,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          AppTheme.platformLabel('${lead['platform']}'),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.brandGreenDark),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
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
