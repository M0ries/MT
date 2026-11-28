import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../model/watch_entry.dart';
import 'journal_store.dart';
import 'webdav.dart';

class MtSyncResult {
  const MtSyncResult(this.downloaded, this.uploaded);
  final int downloaded;
  final int uploaded;
}

typedef SyncProgress = void Function(String phase, int done, int total);

class MtSyncService {
  const MtSyncService();

  Future<MtSyncResult> sync(
    JournalStore store,
    DavCredentials credentials, {
    SyncProgress? onProgress,
    Directory? cacheDirectory,
  }) async {
    final client = WebDavClient(credentials);
    final directory = cacheDirectory ?? await getApplicationCacheDirectory();
    final key = sha256
        .convert(
          utf8.encode(
            '${credentials.url.trim()}\n${credentials.username.trim()}',
          ),
        )
        .toString();
    final cache = File(
      '${directory.path}${Platform.pathSeparator}mt-sync-$key.json',
    );
    final previous = <String, Map<String, dynamic>>{};
    if (await cache.exists()) {
      try {
        final data = jsonDecode(await cache.readAsString()) as Map;
        for (final item in (data['entries'] as Map).entries) {
          previous[item.key as String] = Map<String, dynamic>.from(
            item.value as Map,
          );
        }
      } catch (_) {
        // A damaged cache never replaces the cloud records.
      }
    }
    try {
      onProgress?.call('检查云端记录', 0, 0);
      List<DavResource> listed;
      try {
        listed = await client.listResources('MT/records/');
      } on HttpException catch (error) {
        if (!error.message.contains('HTTP 404')) rethrow;
        await client.ensureDirectory('MT/records/');
        listed = await client.listResources('MT/records/');
      }
      final resources = listed
          .where((item) => item.name.endsWith('.json'))
          .toList();
      final remote = <String, WatchEntry>{};
      final next = <String, Map<String, dynamic>>{};
      var scanned = 0;
      for (var offset = 0; offset < resources.length; offset += 6) {
        final batch = resources.skip(offset).take(6).toList();
        final loaded = await Future.wait(
          batch.map((resource) async {
            final cached = previous[resource.name];
            if (resource.version != null &&
                cached?['version'] == resource.version) {
              try {
                return WatchEntry.fromJson(
                  Map<String, dynamic>.from(cached!['record'] as Map),
                );
              } catch (_) {
                // Fetch this record again if only its cached copy is damaged.
              }
            }
            final raw = await client.read('MT/records/${resource.name}');
            return raw == null
                ? null
                : WatchEntry.fromJson(
                    Map<String, dynamic>.from(jsonDecode(raw) as Map),
                  );
          }),
        );
        for (var i = 0; i < batch.length; i++) {
          final resource = batch[i];
          final item = loaded[i];
          if (item == null) continue;
          if (resource.name != '${item.id}.json') {
            throw const FormatException('WebDAV 文件名与记录 ID 不一致');
          }
          remote[item.id] = item;
          next[resource.name] = {
            'version': resource.version,
            'record': item.toJson(),
          };
        }
        scanned += batch.length;
        onProgress?.call('检查云端记录', scanned, resources.length);
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
      // Finish every read before writing, so a failed read cannot overwrite cloud data.
      if (incoming.isNotEmpty) await store.putAll(incoming);
      var uploaded = 0;
      for (var offset = 0; offset < outgoing.length; offset += 4) {
        final batch = outgoing.skip(offset).take(4).toList();
        await Future.wait(
          batch.map((item) async {
            if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(item.id)) {
              throw const FormatException('无效的记录 ID');
            }
            await client.write(
              'MT/records/${item.id}.json',
              jsonEncode(item.toJson()),
            );
          }),
        );
        uploaded += batch.length;
        onProgress?.call('上传记录', uploaded, outgoing.length);
      }
      // Newly uploaded files have a new ETag; the next sync fetches just those.
      for (final item in outgoing) {
        next.remove('${item.id}.json');
      }
      await directory.create(recursive: true);
      final temporary = File('${cache.path}.tmp');
      await temporary.writeAsString(jsonEncode({'entries': next}), flush: true);
      if (Platform.isWindows && await cache.exists()) await cache.delete();
      await temporary.rename(cache.path);
      return MtSyncResult(incoming.length, outgoing.length);
    } finally {
      client.close();
    }
  }
}
