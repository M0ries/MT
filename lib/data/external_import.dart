import 'dart:convert';

import '../model/watch_entry.dart';
import 'journal_store.dart';

class ExternalImportService {
  const ExternalImportService();

  Future<int> importMtJson(JournalStore store, String raw) async {
    final data = jsonDecode(raw);
    final values = switch (data) {
      Map map when map['entries'] is List => map['entries'] as List,
      Map map when map['id'] is String => [map],
      _ => throw const FormatException('请选择 MT 的 JSON 备份或单条记录文件'),
    };
    final incoming = <WatchEntry>[];
    for (final value in values) {
      if (value is! Map) throw const FormatException('MT 备份包含无效记录');
      final entry = WatchEntry.fromJson(Map<String, dynamic>.from(value));
      if (entry.id.isEmpty || entry.title.trim().isEmpty) {
        throw const FormatException('MT 备份包含缺少标题或 ID 的记录');
      }
      incoming.add(entry);
    }

    final byId = {for (final item in store.allEntries) item.id: item};
    final byBangumi = <int, WatchEntry>{
      for (final item in store.allEntries)
        if (item.bangumiId != null) item.bangumiId!: item,
    };
    final changes = <String, WatchEntry>{};
    for (var item in incoming) {
      if (item.deleted) continue;
      final existing =
          byId[item.id] ??
          (item.bangumiId == null ? null : byBangumi[item.bangumiId]);
      if (existing?.deleted == true ||
          (existing != null && !item.updatedAt.isAfter(existing.updatedAt))) {
        continue;
      }
      if (existing != null && existing.id != item.id) {
        item = WatchEntry.fromJson({...item.toJson(), 'id': existing.id});
      }
      byId[item.id] = item;
      if (item.bangumiId != null) byBangumi[item.bangumiId!] = item;
      changes[item.id] = item;
    }
    if (changes.isNotEmpty) await store.putAll(changes.values);
    return changes.length;
  }
}
