import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shreeram_crm/core/network/api_client.dart';
import 'package:shreeram_crm/core/network/lookup_providers.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';
import 'package:shreeram_crm/core/utils/phone_links.dart';
import 'package:shreeram_crm/features/leads/stage_change_dialog.dart';

/// Loads every non-duplicate lead visible to the current user.
final leadsBoardProvider =
    FutureProvider.family<Map<String, dynamic>, String?>((ref, _) async {
  final dio = ref.watch(dioProvider);
  final all = <Map<String, dynamic>>[];
  var page = 1;
  var lastPage = 1;
  const perPage = 1000;

  do {
    final res = await dio.get('/leads', queryParameters: {
      'per_page': perPage,
      'page': page,
    });

    final raw = Map<String, dynamic>.from(res.data as Map);
    final list = (raw['data'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    all.addAll(list);

    final meta = Map<String, dynamic>.from((raw['meta'] as Map?) ?? const {});
    lastPage = (meta['last_page'] as num?)?.toInt() ?? page;
    page++;
  } while (page <= lastPage && page <= 100);

  return {
    'data': all,
    'meta': {'total': all.length},
  };
});

class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({
    super.key,
    this.initialStageId,
    this.openCreate = false,
  });

  final String? initialStageId;
  final bool openCreate;

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  final _searchController = TextEditingController();
  String? _stageId;
  String _query = '';
  bool _createOpened = false;

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
      setState(() => _stageId = widget.initialStageId);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> leads) {
    return leads.where((lead) {
      if (_stageId != null &&
          '${lead['stage']?['id']}' != _stageId) {
        return false;
      }

      if (_query.isEmpty) return true;

      final q = _query.toLowerCase();
      final id = '${lead['id']}';
      final name = '${lead['name'] ?? ''}'.toLowerCase();
      final mobile = '${lead['mobile'] ?? ''}'.toLowerCase();
      final location =
          '${lead['preferred_location'] ?? ''}'.toLowerCase();

      return id.contains(q) ||
          '#$id'.contains(q) ||
          name.contains(q) ||
          mobile.contains(q) ||
          location.contains(q);
    }).toList();
  }

  Map<String, int> _stageCounts(List<Map<String, dynamic>> leads) {
    final counts = <String, int>{};
    for (final lead in leads) {
      final id = '${lead['stage']?['id']}';
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _changeStage(
    Map<String, dynamic> lead,
    int stageId,
  ) async {
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
      await ref.read(dioProvider).patch(
        '/leads/${lead['id']}/stage',
        data: {
          'lead_stage_id': result.stageId,
          if (result.followUpAt != null)
            'next_follow_up_at':
                result.followUpAt!.toUtc().toIso8601String(),
          if (result.remarks != null) 'remarks': result.remarks,
        },
      );

      ref.invalidate(leadsBoardProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update lead: $e'),
          backgroundColor: AppTheme.brandRed,
        ),
      );
    }
  }

  Future<void> _openCreateLead() async {
    final sources = await ref.read(sourcesProvider.future);
    if (!mounted) return;

    final name = TextEditingController();
    final mobile = TextEditingController();
    final email = TextEditingController();
    final location = TextEditingController();
    final formKey = GlobalKey<FormState>();

    int? sourceId;
    for (final source in sources) {
      if (source['code'] == 'OTHER') {
        sourceId = source['id'] as int?;
        break;
      }
    }
    sourceId ??= sources.isNotEmpty ? sources.first['id'] as int? : null;

    var saving = false;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Add new lead'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'Customer name *'),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Required'
                                  : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: mobile,
                          keyboardType: TextInputType.phone,
                          decoration:
                              const InputDecoration(labelText: 'Mobile *'),
                          validator: (value) {
                            final digits =
                                value?.replaceAll(RegExp(r'\D'), '') ?? '';
                            return digits.length < 8
                                ? 'Enter a valid mobile'
                                : null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: email,
                          decoration:
                              const InputDecoration(labelText: 'Email'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: location,
                          decoration:
                              const InputDecoration(labelText: 'Location'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: sourceId,
                          decoration:
                              const InputDecoration(labelText: 'Source *'),
                          items: [
                            for (final source in sources)
                              DropdownMenuItem<int>(
                                value: source['id'] as int,
                                child: Text('${source['name']}'),
                              ),
                          ],
                          onChanged: saving
                              ? null
                              : (value) => setModalState(() {
                                    sourceId = value;
                                  }),
                          validator: (value) =>
                              value == null ? 'Select a source' : null,
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            style: const TextStyle(
                              color: AppTheme.brandRed,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }

                          setModalState(() {
                            saving = true;
                            error = null;
                          });

                          try {
                            await ref.read(dioProvider).post('/leads', data: {
                              'name': name.text.trim(),
                              'mobile': mobile.text.trim(),
                              'email': email.text.trim().isEmpty
                                  ? null
                                  : email.text.trim(),
                              'preferred_location':
                                  location.text.trim().isEmpty
                                      ? null
                                      : location.text.trim(),
                              'lead_source_id': sourceId,
                            });

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } catch (_) {
                            setModalState(() {
                              saving = false;
                              error = 'Could not save lead.';
                            });
                          }
                        },
                  child: Text(saving ? 'Saving...' : 'Save lead'),
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

    if (saved == true) {
      ref.invalidate(leadsBoardProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final leadsAsync = ref.watch(leadsBoardProvider(null));
    final stagesAsync = ref.watch(stagesProvider);
    final compact = MediaQuery.sizeOf(context).width < 900;

    return Material(
      color: const Color(0xFFF7F9FB),
      child: Column(
        children: [
          _Header(
            compact: compact,
            leadsAsync: leadsAsync,
            stageId: _stageId,
            query: _query,
            searchController: _searchController,
            stagesAsync: stagesAsync,
            stageCounts: (leads) => _stageCounts(leads),
            onSearch: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            onStage: (value) => setState(() => _stageId = value),
            onCreate: _openCreateLead,
          ),
          const Divider(height: 1),
          Expanded(
            child: leadsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (error, _) => Center(
                child: Text('Failed to load leads: $error'),
              ),
              data: (page) {
                final all = List<Map<String, dynamic>>.from(
                  page['data'] as List? ?? const [],
                );
                final filtered = _filter(all);

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _stageId == null
                          ? 'No leads found'
                          : 'No leads in this status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  );
                }

                return stagesAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) => Center(
                    child: Text('Failed to load statuses: $error'),
                  ),
                  data: (stages) {
                    final grouped = <Map<String, dynamic>, List<Map<String, dynamic>>>{};

                    for (final stage in stages) {
                      final items = filtered
                          .where(
                            (lead) =>
                                '${lead['stage']?['id']}' ==
                                '${stage['id']}',
                          )
                          .toList();
                      if (items.isNotEmpty) {
                        grouped[stage] = items;
                      }
                    }

                    // Keep any unexpected stage-less records visible as well.
                    final knownIds =
                        stages.map((s) => '${s['id']}').toSet();
                    final unmatched = filtered.where((lead) {
                      final id = '${lead['stage']?['id']}';
                      return !knownIds.contains(id);
                    }).toList();

                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 12 : 18,
                        14,
                        compact ? 12 : 18,
                        28,
                      ),
                      children: [
                        for (final entry in grouped.entries)
                          _StageSection(
                            stage: entry.key,
                            leads: entry.value,
                            stages: stages,
                            compact: compact,
                            onOpen: (id) => context.go('/leads/$id'),
                            onStageChanged: _changeStage,
                          ),
                        if (unmatched.isNotEmpty)
                          _StageSection(
                            stage: const {
                              'id': -1,
                              'code': 'OTHER',
                              'name': 'Other',
                            },
                            leads: unmatched,
                            stages: stages,
                            compact: compact,
                            onOpen: (id) => context.go('/leads/$id'),
                            onStageChanged: _changeStage,
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.compact,
    required this.leadsAsync,
    required this.stageId,
    required this.query,
    required this.searchController,
    required this.stagesAsync,
    required this.stageCounts,
    required this.onSearch,
    required this.onStage,
    required this.onCreate,
  });

  final bool compact;
  final AsyncValue<Map<String, dynamic>> leadsAsync;
  final String? stageId;
  final String query;
  final TextEditingController searchController;
  final AsyncValue<List<Map<String, dynamic>>> stagesAsync;
  final Map<String, int> Function(List<Map<String, dynamic>>) stageCounts;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onStage;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final leads = leadsAsync.maybeWhen(
      data: (page) => List<Map<String, dynamic>>.from(
        page['data'] as List? ?? const [],
      ),
      orElse: () => const <Map<String, dynamic>>[],
    );

    final total = leads.length;
    final counts = stageCounts(leads);

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 20,
        compact ? 10 : 16,
        compact ? 12 : 20,
        12,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Leads · $total',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (!compact)
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearch,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search ID, name or mobile',
                      isDense: true,
                    ),
                  ),
                ),
              if (!compact) const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: Text(compact ? 'New' : 'New lead'),
              ),
            ],
          ),
          if (compact) ...[
            const SizedBox(height: 10),
            TextField(
              controller: searchController,
              onChanged: onSearch,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search ID, name or mobile',
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: stagesAsync.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (error, _) => Align(
                alignment: Alignment.centerLeft,
                child: Text('$error'),
              ),
              data: (stages) => ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _StatusChip(
                    label: 'All',
                    count: total,
                    selected: stageId == null,
                    color: AppTheme.brandGreenDark,
                    onTap: () => onStage(null),
                  ),
                  for (final stage in stages) ...[
                    const SizedBox(width: 8),
                    _StatusChip(
                      label: '${stage['name']}',
                      count: counts['${stage['id']}'] ?? 0,
                      selected: stageId == '${stage['id']}',
                      color: AppTheme.stageColor('${stage['code']}'),
                      onTap: () => onStage(
                        stageId == '${stage['id']}'
                            ? null
                            : '${stage['id']}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.45)
                : AppTheme.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: selected ? color : AppTheme.ink,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageSection extends StatelessWidget {
  const _StageSection({
    required this.stage,
    required this.leads,
    required this.stages,
    required this.compact,
    required this.onOpen,
    required this.onStageChanged,
  });

  final Map<String, dynamic> stage;
  final List<Map<String, dynamic>> leads;
  final List<Map<String, dynamic>> stages;
  final bool compact;
  final ValueChanged<String> onOpen;
  final Future<void> Function(Map<String, dynamic>, int) onStageChanged;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.stageColor('${stage['code']}');

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${stage['name']}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${leads.length}',
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (compact)
            for (final lead in leads)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LeadCard(
                  lead: lead,
                  stages: stages,
                  accent: color,
                  onOpen: () => onOpen('${lead['id']}'),
                  onStageChanged: (stageId) =>
                      onStageChanged(lead, stageId),
                ),
              )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1250
                    ? 4
                    : constraints.maxWidth >= 900
                        ? 3
                        : 2;

                final cardWidth =
                    (constraints.maxWidth - ((columns - 1) * 12)) / columns;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final lead in leads)
                      SizedBox(
                        width: cardWidth,
                        child: _LeadCard(
                          lead: lead,
                          stages: stages,
                          accent: color,
                          onOpen: () => onOpen('${lead['id']}'),
                          onStageChanged: (stageId) =>
                              onStageChanged(lead, stageId),
                        ),
                      ),
                  ],
                );
              },
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
    final name = '${lead['name'] ?? ''}';
    final mobile = '${lead['mobile'] ?? ''}';
    final config = _leadConfigLabel(lead);
    final budget = _leadBudgetLabel(lead);
    final location = '${lead['preferred_location'] ?? ''}'.trim();
    final followUp = _followUpLabel(lead);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 58,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#${lead['id']}',
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mobile,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (config != null || budget != null) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (config != null)
                            _LeadInfoChip(label: config, color: accent),
                          if (budget != null)
                            _LeadInfoChip(
                              label: budget,
                              color: AppTheme.brandGoldDeep,
                            ),
                        ],
                      ),
                    ],
                    if (location.isNotEmpty || followUp != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        [
                          if (location.isNotEmpty) location,
                          if (followUp != null) followUp,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Call',
                visualDensity: VisualDensity.compact,
                onPressed: () => openPhoneCall(mobile),
                icon: const Icon(
                  Icons.call_rounded,
                  size: 20,
                  color: AppTheme.brandGreenDark,
                ),
              ),
              IconButton(
                tooltip: 'WhatsApp',
                visualDensity: VisualDensity.compact,
                onPressed: () => openWhatsApp(mobile),
                icon: const Icon(
                  Icons.chat_rounded,
                  size: 20,
                  color: Color(0xFF25D366),
                ),
              ),
              PopupMenuButton<int>(
                tooltip: 'Move status',
                icon: const Icon(
                  Icons.swap_horiz_rounded,
                  size: 20,
                  color: AppTheme.brandGoldDeep,
                ),
                onSelected: onStageChanged,
                itemBuilder: (context) => [
                  for (final stage in stages)
                    PopupMenuItem<int>(
                      value: stage['id'] as int,
                      child: Text('${stage['name']}'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _followUpLabel(Map<String, dynamic> lead) {
  final raw = lead['next_follow_up_at'];
  if (raw == null) return null;

  try {
    return DateFormat('d MMM · h:mm a')
        .format(DateTime.parse('$raw').toLocal());
  } catch (_) {
    return null;
  }
}

String? _formAnswerMatching(
  Map<String, dynamic> lead,
  List<String> needles,
) {
  final answers = lead['form_answers'];
  if (answers is! List) return null;

  for (final raw in answers) {
    if (raw is! Map) continue;
    final question =
        '${raw['question'] ?? ''}'.toLowerCase();
    if (!needles.any(question.contains)) continue;

    final answer = '${raw['answer'] ?? ''}'.trim();
    if (answer.isNotEmpty) return answer;
  }

  return null;
}

String? _leadConfigLabel(Map<String, dynamic> lead) {
  final config =
      '${lead['property_configuration']?['name'] ?? ''}'.trim();
  final type =
      '${lead['property_type']?['name'] ?? ''}'.trim();

  if (config.isNotEmpty && type.isNotEmpty) {
    final lower = type.toLowerCase();
    if (lower == 'shop' || lower == 'office' || lower == 'plot') {
      return type;
    }
    return config;
  }

  if (config.isNotEmpty) return config;
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
  return _formAnswerMatching(
    lead,
    ['budget', 'price range', 'investment', 'afford'],
  );
}

class _LeadInfoChip extends StatelessWidget {
  const _LeadInfoChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
