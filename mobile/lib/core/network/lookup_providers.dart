import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shreeram_crm/core/network/api_client.dart';

final stagesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.watch(dioProvider).get('/lead-stages');
  return (res.data['data'] as List<dynamic>? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
});

final sourcesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.watch(dioProvider).get('/lead-sources');
  return (res.data['data'] as List<dynamic>? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
});

List<Map<String, dynamic>> mapPaginator(dynamic raw) {
  if (raw is Map && raw['data'] is List) {
    return (raw['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  return const [];
}
