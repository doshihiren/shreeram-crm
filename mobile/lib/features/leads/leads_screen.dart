import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/network/lookup_providers.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/features/leads/stage_change_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

/// Loads ALL leads for the board (paginates until complete — never stops at 50).
final leadsBoardProvider = FutureProvider.family<Map<String, dynamic>, String?>((ref, stageId) async {
  final dio = ref.watch(dioProvider);
  final all = <Map<String, dynamic>>[];
  var page = 1;
  var lastPage = 1;
  var total = 0;
  // Ask for max page size the API allows (backend caps at 1000).
  const perPage = 1000;
  do {
    final res = await dio.get('/leads', queryParameters: {
      'per_page': perPage,
      'page': page,
      if (stageId != null && stageId.isNotEmpty) 'stage_id': stageId,
    });
    final raw = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    final list = (raw['data'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final meta = Map<String, dynamic>.from((raw['meta'] as Map?) ?? const {});
    final links = Map<String, dynamic>.from((raw['links'] as Map?) ?? const {});
    all.addAll(list);

    lastPage = (meta['last_page'] as num?)?.toInt()
        ?? (meta['lastPage'] as num?)?.toInt()
        ?? 1;
    total = (meta['total'] as num?)?.toInt() ?? all.length;

    // Fallback: if meta is missing, keep going while this page was full or links.next exists.
    final hasNextLink = links['next'] != null && '${links['next']}'.isNotEmpty && '${links['next']}' != 'null';
    if (meta.isEmpty) {
      if (list.length >= perPage || hasNextLink) {
        lastPage = page + 1;
      } else {
        lastPage = page;
      }
    }

    page += 1;
  } while (page <= lastPage && page <= 100);

  return {
    'data': all,
    'meta': {'total': total, 'loaded': all.length, 'last_page': lastPage},
  };
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
    // Board needs all columns for drag-drop; default All unless deep-linked.
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
      setState(() => _stageId = widget.initialStageId);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _changeStage(Map<String, dynamic> lead, int stageId) async {
    final stages = await ref.read(stagesProvider.future);
    if (!mounted) return;
    final currentId = lead['stage']?['id'];
    if ('$currentId' == '$stageId') return;

    final result = await showStageChangeDialog(
      context,
      stages: stages,
      selectedStageId: stageId,
      leadName: '${lead['name'] ?? ''}',
      lockStage: true,
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
          content: Text('Lead moved'),
          backgroundColor: AppTheme.brandGreenDark,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Move failed: $e'), backgroundColor: AppTheme.brandRed),
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
                  Expanded(
                    child: leadsAsync.maybeWhen(
                      data: (page) {
                        final total = page['meta']?['total'] ?? (page['data'] as List).length;
                        final showing = _filter(List<Map<String, dynamic>>.from(page['data'] as List)).length;
                        return Text(
                          'Leads · $showing / $total',
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Drag a lead card onto another status column · drop asks for follow-up date & remarks',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
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
            data: (page) {
              final leads = List<Map<String, dynamic>>.from(page['data'] as List? ?? const []);
              final filtered = _filter(leads);
              final total = (page['meta']?['total'] as num?)?.toInt() ?? filtered.length;

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
                        // Board always shows all stage columns so drag-drop works.
                        if (_view == _LeadsView.board) {
                          return _LeadsKanban(
                            leads: filtered,
                            stages: stages,
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.white,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Showing ${filtered.length} of $total leads', style: Theme.of(context).textTheme.bodyMedium),
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
            leads: leads.where((l) => '${l['stage']?['id']}' == '${stage['id']}').toList(),
            allStages: stages,
            onOpen: onOpen,
            onStageChanged: onStageChanged,
          ),
      ],
    );
  }
}

class _KanbanColumn extends StatefulWidget {
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
  State<_KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<_KanbanColumn> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.stageColor('${widget.stage['code']}');
    final stageId = widget.stage['id'] as int;
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) {
        final fromId = details.data['stage']?['id'];
        final ok = '$fromId' != '$stageId';
        setState(() => _hovering = ok);
        return ok;
      },
      onLeave: (_) => setState(() => _hovering = false),
      onAcceptWithDetails: (details) async {
        setState(() => _hovering = false);
        await widget.onStageChanged(details.data, stageId);
      },
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 300,
          margin: const EdgeInsets.only(right: 14),
          decoration: BoxDecoration(
            color: _hovering ? color.withValues(alpha: 0.10) : const Color(0xFFF0F3F8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hovering ? color : AppTheme.line, width: _hovering ? 2 : 1),
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
                        '${widget.stage['name']}',
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
                      child: Text('${widget.leads.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              if (_hovering)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Drop here', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  itemCount: widget.leads.length,
                  itemBuilder: (context, i) {
                    final lead = widget.leads[i];
                    return _LeadCard(
                      lead: lead,
                      stages: widget.allStages,
                      accent: color,
                      onOpen: () => widget.onOpen('${lead['id']}'),
                      onStageChanged: (id) => widget.onStageChanged(lead, id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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

  Widget _cardBody({required bool dragging}) {
    final name = '${lead['name']}';
    final mobile = '${lead['mobile']}';
    return Material(
      color: Colors.white,
      elevation: dragging ? 6 : 0,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: dragging ? null : onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dragging ? accent : AppTheme.line, width: dragging ? 1.5 : 1),
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
                  if (!dragging)
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
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.drag_indicator, size: 16, color: AppTheme.muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      dragging ? 'Drop on a status column' : 'Drag to another status',
                      style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!dragging)
                    PopupMenuButton<int>(
                      tooltip: 'Move stage',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18, color: AppTheme.brandGoldDeep),
                      onSelected: onStageChanged,
                      itemBuilder: (context) => [
                        for (final s in stages)
                          PopupMenuItem(
                            value: s['id'] as int,
                            child: Text('${s['name']}'),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // Immediate drag (desktop/web mouse) — no long-press required.
      child: Draggable<Map<String, dynamic>>(
        data: lead,
        affinity: Axis.horizontal,
        feedback: Material(
          color: Colors.transparent,
          elevation: 8,
          child: SizedBox(width: 260, child: _cardBody(dragging: true)),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: _cardBody(dragging: false)),
        child: _cardBody(dragging: false),
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
                        DataCell(Text('${lead['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                        DataCell(Text('${lead['mobile']}')),
                        DataCell(
                          DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: lead['stage']?['id'] as int?,
                              items: [
                                for (final s in stages)
                                  DropdownMenuItem(value: s['id'] as int, child: Text('${s['name']}')),
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
