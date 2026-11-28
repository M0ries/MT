import 'dart:convert';

import '../model/watch_entry.dart';
import 'journal_store.dart';

class ExternalImportService {
  const ExternalImportService();

  Future<int> importMtJson(
    JournalStore store,
    String raw, {
    bool restoreDeleted = false,
    bool replaceAll = false,
  }) async {
    final data = jsonDecode(raw);
    final values = switch (data) {
      Map map when map['entries'] is List => map['entries'] as List,
      Map map when map['id'] is String => [map],
      _ => throw const FormatException('请选择 MRecorder 的 JSON 备份或单条记录文件'),
    };
    final incoming = <WatchEntry>[];
    for (final value in values) {
      if (value is! Map) throw const FormatException('记录文件包含无效记录');
      final entry = WatchEntry.fromJson(Map<String, dynamic>.from(value));
      if (entry.id.isEmpty || entry.title.trim().isEmpty) {
        throw const FormatException('记录文件包含缺少标题或 ID 的记录');
      }
      incoming.add(entry);
    }

    if (replaceAll) {
      final wanted = incoming.where((entry) => !entry.deleted).toList();
      if (wanted.isEmpty) {
        throw const FormatException('替换文件没有可导入的记录');
      }
      final ids = <String>{};
      final bangumiIds = <int>{};
      for (final entry in wanted) {
        if (!ids.add(entry.id) ||
            (entry.bangumiId != null && !bangumiIds.add(entry.bangumiId!))) {
          throw const FormatException('替换文件包含重复记录');
        }
      }

      final existing = store.allEntries;
      final byId = {for (final entry in existing) entry.id: entry};
      final byBangumi = {
        for (final entry in existing)
          if (entry.bangumiId != null) entry.bangumiId!: entry,
      };
      var stamp = DateTime.now().toUtc();
      for (final entry in existing) {
        if (!stamp.isAfter(entry.updatedAt)) {
          stamp = entry.updatedAt.add(const Duration(milliseconds: 1));
        }
      }
      final changes = <String, WatchEntry>{};
      for (final entry in wanted) {
        final match =
            byId[entry.id] ??
            (entry.bangumiId == null ? null : byBangumi[entry.bangumiId]);
        final id = match?.id ?? entry.id;
        if (changes.containsKey(id)) {
          throw const FormatException('替换文件有多条记录对应同一作品');
        }
        final replacement = id == entry.id
            ? entry
            : WatchEntry.fromJson({...entry.toJson(), 'id': id});
        changes[id] = replacement.copyWith(deleted: false, updatedAt: stamp);
        stamp = stamp.add(const Duration(microseconds: 1));
      }
      for (final entry in existing) {
        if (changes.containsKey(entry.id) || entry.deleted) continue;
        changes[entry.id] = entry.copyWith(deleted: true, updatedAt: stamp);
        stamp = stamp.add(const Duration(microseconds: 1));
      }
      await store.putAll(changes.values);
      return wanted.length;
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
      if (existing?.deleted == true && !restoreDeleted) {
        continue;
      }
      if (existing != null &&
          !existing.deleted &&
          !item.updatedAt.isAfter(existing.updatedAt)) {
        continue;
      }
      if (existing != null && existing.id != item.id) {
        item = WatchEntry.fromJson({...item.toJson(), 'id': existing.id});
      }
      if (existing?.deleted == true) {
        final now = DateTime.now().toUtc();
        final afterDeletion = existing!.updatedAt.add(
          const Duration(milliseconds: 1),
        );
        item = item.copyWith(
          deleted: false,
          updatedAt: now.isAfter(afterDeletion) ? now : afterDeletion,
        );
      }
      byId[item.id] = item;
      if (item.bangumiId != null) byBangumi[item.bangumiId!] = item;
      changes[item.id] = item;
    }
    if (changes.isNotEmpty) await store.putAll(changes.values);
    return changes.length;
  }
}
