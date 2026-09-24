import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/network/lookup_providers.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/core/utils/phone_links.dart';
import 'package:shreeram_crm/features/leads/stage_change_dialog.dart';

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
  bool _searchOpen = false;
  final ValueNotifier<bool> _dragging = ValueNotifier(false);

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
    _dragging.dispose();
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
    return leads.where((l) {
      if (_stageId != null && '${l['stage']?['id']}' != _stageId) return false;
      if (_query.isEmpty) return true;
      final name = '${l['name']}'.toLowerCase();
      final mobile = '${l['mobile']}'.toLowerCase();
      final id = '${l['id']}';
      return name.contains(_query) || mobile.contains(_query) || id.contains(_query) || '#$id'.contains(_query);
    }).toList();
  }

  Map<String, int> _stageCounts(List<Map<String, dynamic>> leads) {
    final counts = <String, int>{};
    for (final l in leads) {
      final sid = '${l['stage']?['id']}';
      counts[sid] = (counts[sid] ?? 0) + 1;
    }
    return counts;
  }

  void _setDragging(bool value) {
    if (_dragging.value == value) return;
    _dragging.value = value;
  }

  @override
  Widget build(BuildContext context) {
    final stagesAsync = ref.watch(stagesProvider);
    final leadsAsync = ref.watch(leadsBoardProvider(null));
    // Force the proven compact renderer for Leads on all viewport sizes.
    // Opening DevTools reduced the viewport below this breakpoint and made
    // the page render correctly; use that same rendering path directly.
    const compact = true;

    return Column(
      children: [
        Material(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.fromLTRB(compact ? 12 : 20, compact ? 8 : 14, compact ? 12 : 20, compact ? 8 : 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: leadsAsync.maybeWhen(
                        data: (page) {
                          final all = List<Map<String, dynamic>>.from(page['data'] as List);
                          final total = page['meta']?['total'] ?? all.length;
                          final showing = _filter(all).length;
                          return Text(
                            compact ? 'Leads · $showing' : 'Leads · $showing / $total',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: compact ? 18 : null,
                                ),
                          );
                        },
                        orElse: () => Text(
                          'Leads',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    if (!compact) ...[
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
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search ID, name or mobile',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ] else ...[
                      IconButton(
                        tooltip: _view == _LeadsView.board ? 'Switch to table' : 'Switch to board',
                        onPressed: () => setState(() {
                          _view = _view == _LeadsView.board ? _LeadsView.table : _LeadsView.board;
                        }),
                        icon: Icon(_view == _LeadsView.board ? Icons.table_rows_outlined : Icons.view_kanban_outlined),
                      ),
                      IconButton(
                        tooltip: 'Search',
                        onPressed: () => setState(() {
                          _searchOpen = !_searchOpen;
                          if (!_searchOpen && _query.isEmpty) _search.clear();
                        }),
                        icon: Icon(_searchOpen || _query.isNotEmpty ? Icons.search_off_rounded : Icons.search_rounded),
                        color: _searchOpen || _query.isNotEmpty ? AppTheme.brandGreenDark : null,
                      ),
                    ],
                    ElevatedButton.icon(
                      onPressed: _openCreateLead,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(compact ? 'New' : 'New lead'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: compact ? 10 : 12),
                        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
                      ),
                    ),
                  ],
                ),
                if (compact && (_searchOpen || _query.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    autofocus: _searchOpen && _query.isEmpty,
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search ID, name or mobile',
                      isDense: true,
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                            ),
                    ),
                  ),
                ],
                SizedBox(height: compact ? 8 : 10),
                stagesAsync.when(
                  loading: () => const LinearProgressIndicator(minHeight: 2),
                  error: (e, _) => Text('$e'),
                  data: (stages) {
                    final allLeads = leadsAsync.maybeWhen(
                      data: (page) => List<Map<String, dynamic>>.from(page['data'] as List? ?? const []),
                      orElse: () => const <Map<String, dynamic>>[],
                    );
                    final counts = _stageCounts(allLeads);
                    return SizedBox(
                      height: compact ? 36 : 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _FilterChip(
                            label: 'All',
                            count: allLeads.length,
                            selected: _stageId == null,
                            color: AppTheme.brandGreenDark,
                            compact: compact,
                            onTap: () => setState(() => _stageId = null),
                          ),
                          for (final stage in stages) ...[
                            SizedBox(width: compact ? 6 : 8),
                            _FilterChip(
                              label: '${stage['name']}',
                              count: counts['${stage['id']}'] ?? 0,
                              selected: _stageId == '${stage['id']}',
                              color: AppTheme.stageColor('${stage['code']}'),
                              compact: compact,
                              onTap: () => setState(() {
                                _stageId = _stageId == '${stage['id']}' ? null : '${stage['id']}';
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
        ),
        const Divider(height: 1),
        Expanded(
          child: leadsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load leads: $e')),
            data: (page) {
              final leads = List<Map<String, dynamic>>.from(page['data'] as List? ?? const []);
              final filtered = _filter(leads);
              final total = (page['meta']?['total'] as num?)?.toInt() ?? leads.length;

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _stageId == null ? 'No leads yet' : 'No leads in this status',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      if (_stageId != null)
                        TextButton(
                          onPressed: () => setState(() => _stageId = null),
                          child: const Text('Show all statuses'),
                        ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(onPressed: _openCreateLead, icon: const Icon(Icons.add), label: const Text('Add lead')),
                    ],
                  ),
                );
              }

              return Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: stagesAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (e, _) => Text('$e'),
                          data: (stages) {
                            if (_view == _LeadsView.board) {
                              return _LeadsKanban(
                                leads: filtered,
                                allLeads: leads,
                                stages: stages,
                                focusStageId: _stageId,
                                compact: compact,
                                onDragChanged: _setDragging,
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
                      if (!compact)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: Colors.white,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Showing ${filtered.length} of $total leads · drag a card to change status',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (compact)
                    ValueListenableBuilder<bool>(
                      valueListenable: _dragging,
                      builder: (context, dragging, _) {
                        if (!dragging) return const SizedBox.shrink();
                        return stagesAsync.maybeWhen(
                          data: (stages) {
                            final others = _stageId == null
                                ? stages
                                : stages.where((s) => '${s['id']}' != _stageId).toList();
                            return Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _MobileDropBar(
                                stages: others,
                                allLeads: leads,
                                onAccept: (lead, stageId) async {
                                  _setDragging(false);
                                  await _changeStage(lead, stageId);
                                },
                              ),
                            );
                          },
                          orElse: () => const SizedBox.shrink(),
                        );
                      },
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

String _leadIdLabel(Map<String, dynamic> lead) => '#${lead['id']}';

String? _followUpLabel(Map<String, dynamic> lead) {
  final raw = lead['next_follow_up_at'];
  if (raw == null) return null;
  try {
    return DateFormat('d MMM · h:mm a').format(DateTime.parse('$raw').toLocal());
  } catch (_) {
    return null;
  }
}

String? _formAnswerMatching(Map<String, dynamic> lead, List<String> needles) {
  final answers = lead['form_answers'];
  if (answers is! List) return null;
  for (final raw in answers) {
    if (raw is! Map) continue;
    final q = '${raw['question'] ?? ''}'.toLowerCase();
    if (!needles.any(q.contains)) continue;
    final a = '${raw['answer'] ?? ''}'.trim();
    if (a.isNotEmpty) return a;
  }
  return null;
}

/// 2/3 BHK, Shop, etc. — structured fields first, then Meta form answers.
String? _leadConfigLabel(Map<String, dynamic> lead) {
  final cfg = '${lead['property_configuration']?['name'] ?? ''}'.trim();
  final type = '${lead['property_type']?['name'] ?? ''}'.trim();
  if (cfg.isNotEmpty && type.isNotEmpty) {
    final typeLower = type.toLowerCase();
    if (typeLower == 'shop' || typeLower == 'office' || typeLower == 'plot') {
      return type;
    }
    return cfg;
  }
  if (cfg.isNotEmpty) return cfg;
  if (type.isNotEmpty) return type;
  return _formAnswerMatching(lead, [
    'bhk',
    'configuration',
    'unit type',
    'property type',
    'looking for',
    'interested in',
    'requirement',
    'shop',
  ]);
}

String? _leadBudgetLabel(Map<String, dynamic> lead) {
  return _formAnswerMatching(lead, ['budget', 'price range', 'investment', 'afford']);
}

class _LeadInfoChip extends StatelessWidget {
  const _LeadInfoChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.count,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final int? count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 6 : 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color.withValues(alpha: 0.45) : AppTheme.line),
        ),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            SizedBox(width: compact ? 6 : 8),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w700, color: selected ? color : AppTheme.ink, fontSize: compact ? 11 : 12),
            ),
            if (count != null) ...[
              SizedBox(width: compact ? 6 : 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? color.withValues(alpha: 0.18) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected ? color : AppTheme.muted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MobileDropBar extends StatelessWidget {
  const _MobileDropBar({
    required this.stages,
    required this.allLeads,
    required this.onAccept,
  });

  final List<Map<String, dynamic>> stages;
  final List<Map<String, dynamic>> allLeads;
  final Future<void> Function(Map<String, dynamic> lead, int stageId) onAccept;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      color: const Color(0xFF0C3D32),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Drop on a status',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: stages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final stage = stages[i];
                    final count = allLeads.where((l) => '${l['stage']?['id']}' == '${stage['id']}').length;
                    return _StageDropChip(
                      stage: stage,
                      count: count,
                      dark: true,
                      onAccept: (lead) => onAccept(lead, stage['id'] as int),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadsKanban extends StatelessWidget {
  const _LeadsKanban({
    required this.leads,
    required this.allLeads,
    required this.stages,
    required this.focusStageId,
    required this.compact,
    required this.onDragChanged,
    required this.onOpen,
    required this.onStageChanged,
  });

  final List<Map<String, dynamic>> leads;
  final List<Map<String, dynamic>> allLeads;
  final List<Map<String, dynamic>> stages;
  final String? focusStageId;
  final bool compact;
  final ValueChanged<bool> onDragChanged;
  final void Function(String id) onOpen;
  final Future<void> Function(Map<String, dynamic> lead, int stageId) onStageChanged;

  @override
  Widget build(BuildContext context) {
    // Mobile focused status: flat full-width list — max space for cards.
    if (focusStageId != null && compact) {
      final focused = stages.firstWhere(
        (s) => '${s['id']}' == focusStageId,
        orElse: () => stages.isNotEmpty ? stages.first : <String, dynamic>{},
      );
      if (focused.isEmpty) return const SizedBox.shrink();
      final color = AppTheme.stageColor('${focused['code']}');
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        itemCount: leads.length,
        itemBuilder: (context, i) {
          final lead = leads[i];
          return _LeadCard(
            lead: lead,
            stages: stages,
            accent: color,
            compact: true,
            onDragChanged: onDragChanged,
            onOpen: () => onOpen('${lead['id']}'),
            onStageChanged: (id) => onStageChanged(lead, id),
          );
        },
      );
    }

    // Desktop/tablet focused: drop chips on desktop only (always visible), wide column.
    if (focusStageId != null) {
      final focused = stages.firstWhere(
        (s) => '${s['id']}' == focusStageId,
        orElse: () => stages.isNotEmpty ? stages.first : <String, dynamic>{},
      );
      if (focused.isEmpty) return const SizedBox.shrink();
      final others = stages.where((s) => '${s['id']}' != focusStageId).toList();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (others.isNotEmpty) ...[
              Text(
                'Drop on a status to move',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                      fontSize: 12,
                    ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: others.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final stage = others[i];
                    final count = allLeads.where((l) => '${l['stage']?['id']}' == '${stage['id']}').length;
                    return _StageDropChip(
                      stage: stage,
                      count: count,
                      onAccept: (lead) => onStageChanged(lead, stage['id'] as int),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: _KanbanColumn(
                stage: focused,
                leads: leads,
                allStages: stages,
                wide: true,
                compact: compact,
                onDragChanged: onDragChanged,
                onOpen: onOpen,
                onStageChanged: onStageChanged,
              ),
            ),
          ],
        ),
      );
    }

    // All statuses
    final visible = stages.where((s) {
      return leads.any((l) => '${l['stage']?['id']}' == '${s['id']}');
    }).toList();
    final empty = stages.where((s) => !visible.any((v) => v['id'] == s['id'])).toList();

    // Use the proven vertical card layout on normal desktop widths too.
    // The wide horizontal Kanban remains available only on very large displays.
    // This avoids the desktop canvas/layout issue where cards appeared only
    // after DevTools reduced the viewport width.
    // Production stability: use the same proven card-list renderer on every
    // viewport. The old wide horizontal Kanban branch can render blank on
    // desktop CanvasKit while the data is present.
    const useVerticalLayout = true;
    if (useVerticalLayout) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final stage = visible[i];
          final stageLeads = leads.where((l) => '${l['stage']?['id']}' == '${stage['id']}').toList();
          final color = AppTheme.stageColor('${stage['code']}');
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 2),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text('${stage['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(width: 8),
                      Text('${stageLeads.length}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.muted)),
                    ],
                  ),
                ),
                for (final lead in stageLeads)
                  _LeadCard(
                    lead: lead,
                    stages: stages,
                    accent: color,
                    compact: true,
                    onDragChanged: onDragChanged,
                    onOpen: () => onOpen('${lead['id']}'),
                    onStageChanged: (id) => onStageChanged(lead, id),
                  ),
              ],
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (empty.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: empty.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final stage = empty[i];
                  return _StageDropChip(
                    stage: stage,
                    count: 0,
                    compact: true,
                    onAccept: (lead) => onStageChanged(lead, stage['id'] as int),
                  );
                },
              ),
            ),
          ),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              for (final stage in visible)
                _KanbanColumn(
                  stage: stage,
                  leads: leads.where((l) => '${l['stage']?['id']}' == '${stage['id']}').toList(),
                  allStages: stages,
                  compact: false,
                  onDragChanged: onDragChanged,
                  onOpen: onOpen,
                  onStageChanged: onStageChanged,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StageDropChip extends StatefulWidget {
  const _StageDropChip({
    required this.stage,
    required this.count,
    required this.onAccept,
    this.compact = false,
    this.dark = false,
  });

  final Map<String, dynamic> stage;
  final int count;
  final Future<void> Function(Map<String, dynamic> lead) onAccept;
  final bool compact;
  final bool dark;

  @override
  State<_StageDropChip> createState() => _StageDropChipState();
}

class _StageDropChipState extends State<_StageDropChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.stageColor('${widget.stage['code']}');
    final stageId = widget.stage['id'];
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
        await widget.onAccept(details.data);
      },
      builder: (context, candidate, rejected) {
        final bg = widget.dark
            ? (_hovering ? Colors.white : Colors.white.withValues(alpha: 0.12))
            : (_hovering ? color.withValues(alpha: 0.16) : Colors.white);
        final fg = widget.dark
            ? (_hovering ? AppTheme.brandGreenDark : Colors.white)
            : (_hovering ? color : AppTheme.ink);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovering ? color : (widget.dark ? Colors.white24 : AppTheme.line),
              width: _hovering ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(
                _hovering ? 'Drop · ${widget.stage['name']}' : '${widget.stage['name']}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: fg),
              ),
              if (!widget.compact || widget.count > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: widget.dark ? Colors.white70 : AppTheme.muted,
                  ),
                ),
              ],
            ],
          ),
        );
      },
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
    required this.onDragChanged,
    this.wide = false,
    this.compact = false,
  });

  final Map<String, dynamic> stage;
  final List<Map<String, dynamic>> leads;
  final List<Map<String, dynamic>> allStages;
  final void Function(String id) onOpen;
  final Future<void> Function(Map<String, dynamic> lead, int stageId) onStageChanged;
  final ValueChanged<bool> onDragChanged;
  final bool wide;
  final bool compact;

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
          width: widget.wide ? null : 300,
          margin: widget.wide ? EdgeInsets.zero : const EdgeInsets.only(right: 14),
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
                child: widget.wide && !widget.compact
                    ? GridView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 340,
                          mainAxisExtent: 156,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: widget.leads.length,
                        itemBuilder: (context, i) {
                          final lead = widget.leads[i];
                          return _LeadCard(
                            lead: lead,
                            stages: widget.allStages,
                            accent: color,
                            compact: false,
                            onDragChanged: widget.onDragChanged,
                            onOpen: () => widget.onOpen('${lead['id']}'),
                            onStageChanged: (id) => widget.onStageChanged(lead, id),
                          );
                        },
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                        itemCount: widget.leads.length,
                        itemBuilder: (context, i) {
                          final lead = widget.leads[i];
                          return _LeadCard(
                            lead: lead,
                            stages: widget.allStages,
                            accent: color,
                            compact: widget.compact,
                            onDragChanged: widget.onDragChanged,
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
    required this.onDragChanged,
    this.compact = false,
  });

  final Map<String, dynamic> lead;
  final List<Map<String, dynamic>> stages;
  final Color accent;
  final VoidCallback onOpen;
  final ValueChanged<int> onStageChanged;
  final ValueChanged<bool> onDragChanged;
  final bool compact;

  Widget _cardBody({required bool dragging}) {
    final name = '${lead['name']}';
    final mobile = '${lead['mobile']}';
    final idLabel = _leadIdLabel(lead);
    final followUp = _followUpLabel(lead);
    final location = '${lead['preferred_location'] ?? ''}'.trim();
    final config = _leadConfigLabel(lead);
    final budget = _leadBudgetLabel(lead);
    final interestBits = [
      if (config != null && config.isNotEmpty) config,
      if (budget != null && budget.isNotEmpty) budget,
    ];

    return Material(
      color: Colors.white,
      elevation: dragging ? 6 : 0,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: dragging ? null : onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.fromLTRB(compact ? 10 : 12, compact ? 10 : 10, 6, compact ? 10 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dragging ? accent : AppTheme.line, width: dragging ? 1.5 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: interestBits.isNotEmpty ? (compact ? 64 : 68) : (compact ? 48 : 52),
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          idLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 14 : 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(mobile, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w600, fontSize: 13)),
                    if (interestBits.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (config != null && config.isNotEmpty)
                            _LeadInfoChip(label: config, color: accent),
                          if (budget != null && budget.isNotEmpty)
                            _LeadInfoChip(label: budget, color: AppTheme.brandGoldDeep),
                        ],
                      ),
                    ],
                    if (location.isNotEmpty || followUp != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (location.isNotEmpty) location,
                          if (followUp != null) followUp,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: followUp != null ? accent : AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              if (!dragging) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Call',
                  onPressed: () => openPhoneCall(mobile),
                  icon: const Icon(Icons.call_rounded, size: 20, color: AppTheme.brandGreenDark),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'WhatsApp',
                  onPressed: () => openWhatsApp(mobile),
                  icon: const Icon(Icons.chat_rounded, size: 20, color: Color(0xFF25D366)),
                ),
                PopupMenuButton<int>(
                  tooltip: 'Move status',
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 20, color: AppTheme.brandGoldDeep),
                  onSelected: onStageChanged,
                  itemBuilder: (context) => [
                    for (final s in stages)
                      PopupMenuItem(value: s['id'] as int, child: Text('${s['name']}')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _cardBody(dragging: false);
    final feedback = Material(
      color: Colors.transparent,
      elevation: 8,
      child: SizedBox(width: compact ? MediaQuery.sizeOf(context).width - 48 : 280, child: _cardBody(dragging: true)),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: compact
          ? LongPressDraggable<Map<String, dynamic>>(
              data: lead,
              delay: const Duration(milliseconds: 180),
              onDragStarted: () => onDragChanged(true),
              onDragEnd: (_) => onDragChanged(false),
              onDraggableCanceled: (_, __) => onDragChanged(false),
              feedback: feedback,
              childWhenDragging: Opacity(opacity: 0.35, child: body),
              child: body,
            )
          : Draggable<Map<String, dynamic>>(
              data: lead,
              affinity: Axis.horizontal,
              onDragStarted: () => onDragChanged(true),
              onDragEnd: (_) => onDragChanged(false),
              onDraggableCanceled: (_, __) => onDragChanged(false),
              feedback: feedback,
              childWhenDragging: Opacity(opacity: 0.35, child: body),
              child: body,
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
                  DataColumn(label: Text('ID')),
                  DataColumn(label: Text('Lead')),
                  DataColumn(label: Text('Mobile')),
                  DataColumn(label: Text('Config')),
                  DataColumn(label: Text('Budget')),
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
                        DataCell(Text(_leadIdLabel(lead), style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.brandGreenDark))),
                        DataCell(Text('${lead['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                        DataCell(Text('${lead['mobile']}')),
                        DataCell(Text(_leadConfigLabel(lead) ?? '—')),
                        DataCell(Text(_leadBudgetLabel(lead) ?? '—')),
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
                                onPressed: () => openPhoneCall('${lead['mobile']}'),
                                icon: const Icon(Icons.call_rounded, color: AppTheme.brandGreenDark),
                              ),
                              IconButton(
                                tooltip: 'WhatsApp',
                                onPressed: () => openWhatsApp('${lead['mobile']}'),
                                icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
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
