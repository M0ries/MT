import 'dart:convert';

import '../model/watch_entry.dart';
import 'journal_store.dart';
import 'webdav.dart';

class MtSyncResult {
  const MtSyncResult(this.downloaded, this.uploaded);
  final int downloaded;
  final int uploaded;
}

class MtSyncService {
  const MtSyncService();

  Future<MtSyncResult> sync(JournalStore store, DavCredentials credentials) async {
    final client = WebDavClient(credentials);
    try {
      await client.ensureDirectory('MT/records/');
      final names = await client.listFiles('MT/records/');
      final remote = <String, WatchEntry>{};
      for (final name in names.where((n) => n.endsWith('.json'))) {
        final raw = await client.read('MT/records/$name');
        if (raw == null) continue;
        final item = WatchEntry.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        if (name != '${item.id}.json') {
          throw const FormatException('WebDAV 文件名与 MT 记录 ID 不一致');
        }
        remote[item.id] = item;
      }
      final local = {for (final item in store.allEntries) item.id: item};
      final incoming = <WatchEntry>[];
      final outgoing = <WatchEntry>[];
      for (final id in {...local.keys, ...remote.keys}) {
        final mine = local[id];
        final theirs = remote[id];
        if (mine == null && theirs != null) {
          incoming.add(theirs);
        } else if (theirs == null && mine != null) {
          outgoing.add(mine);
        } else if (mine != null && theirs != null) {
          if (theirs.updatedAt.isAfter(mine.updatedAt)) {
            incoming.add(theirs);
          } else if (mine.updatedAt.isAfter(theirs.updatedAt)) {
            outgoing.add(mine);
          }
        }
      }
      // Download before uploading, so a failed read cannot overwrite remote data.
      if (incoming.isNotEmpty) await store.putAll(incoming);
      for (final item in outgoing) {
        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(item.id)) {
          throw const FormatException('无效的 MT 记录 ID');
        }
        await client.write('MT/records/${item.id}.json', jsonEncode(item.toJson()));
      }
      return MtSyncResult(incoming.length, outgoing.length);
    } finally {
      client.close();
    }
  }
}
