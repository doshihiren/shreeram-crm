import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';

class StageChangeResult {
  const StageChangeResult({
    required this.stageId,
    this.followUpAt,
    this.remarks,
  });

  final int stageId;
  final DateTime? followUpAt;
  final String? remarks;
}

bool stageRequiresFollowUp(String? code) {
  final c = (code ?? '').toUpperCase();
  return c != 'LOST' && c != 'UNIT_BOOKED';
}

DateTime defaultFollowUpAt({required bool nextDay}) {
  final base = nextDay ? DateTime.now().add(const Duration(days: 1)) : DateTime.now();
  return DateTime(base.year, base.month, base.day, 10, 0);
}

/// Dialog: confirm stage change + optional/required next follow-up (default 10:00) + remarks.
Future<StageChangeResult?> showStageChangeDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> stages,
  required int selectedStageId,
  String? leadName,
}) async {
  Map<String, dynamic> selected = stages.firstWhere(
    (s) => s['id'] == selectedStageId,
    orElse: () => stages.isNotEmpty ? stages.first : <String, dynamic>{},
  );
  if (selected.isEmpty) return null;

  var stageId = selected['id'] as int;
  var code = '${selected['code'] ?? ''}';
  var requireFollowUp = stageRequiresFollowUp(code);
  var followUp = code.toUpperCase() == 'CALL_NOT_RECEIVED'
      ? defaultFollowUpAt(nextDay: true)
      : (requireFollowUp ? defaultFollowUpAt(nextDay: false) : null);
  final remarks = TextEditingController();
  String? error;

  final result = await showDialog<StageChangeResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModal) {
          return AlertDialog(
            title: Text(leadName == null ? 'Update status' : 'Update · $leadName'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int>(
                    value: stageId,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final s in stages)
                        DropdownMenuItem(value: s['id'] as int, child: Text('${s['name']}')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      final s = stages.firstWhere((e) => e['id'] == v);
                      setModal(() {
                        stageId = v;
                        code = '${s['code'] ?? ''}';
                        requireFollowUp = stageRequiresFollowUp(code);
                        if (code.toUpperCase() == 'CALL_NOT_RECEIVED') {
                          followUp = defaultFollowUpAt(nextDay: true);
                        } else if (requireFollowUp && followUp == null) {
                          followUp = defaultFollowUpAt(nextDay: false);
                        } else if (!requireFollowUp) {
                          followUp = null;
                        }
                        error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (requireFollowUp) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_available, color: AppTheme.brandGoldDeep),
                      title: Text(
                        followUp == null
                            ? 'Next follow-up *'
                            : DateFormat('EEE, d MMM · h:mm a').format(followUp!),
                      ),
                      subtitle: Text(
                        code.toUpperCase() == 'CALL_NOT_RECEIVED'
                            ? 'Defaults to tomorrow 10:00 AM'
                            : 'Default time 10:00 AM',
                      ),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: ctx,
                          initialDate: followUp ?? defaultFollowUpAt(nextDay: false),
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date == null || !ctx.mounted) return;
                        final time = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(followUp ?? defaultFollowUpAt(nextDay: false)),
                        );
                        if (time == null) return;
                        setModal(() {
                          followUp = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                          error = null;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: remarks,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Remarks *',
                        hintText: 'Call notes / next step',
                      ),
                    ),
                  ] else
                    Text(
                      'Follow-up not required for ${selected['name'] ?? code}.',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  if (requireFollowUp) {
                    if (followUp == null) {
                      setModal(() => error = 'Next follow-up date is required');
                      return;
                    }
                    if (remarks.text.trim().isEmpty) {
                      setModal(() => error = 'Remarks are required');
                      return;
                    }
                  }
                  Navigator.pop(
                    ctx,
                    StageChangeResult(
                      stageId: stageId,
                      followUpAt: followUp,
                      remarks: remarks.text.trim().isEmpty ? null : remarks.text.trim(),
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  remarks.dispose();
  return result;
}
