import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memory_taker/data/journal_store.dart';
import 'package:memory_taker/data/bangumi.dart';
import 'package:memory_taker/data/bangumi_metadata_sync.dart';
import 'package:memory_taker/data/external_import.dart';
import 'package:memory_taker/data/kazumi_import.dart';
import 'package:memory_taker/data/mt_sync.dart';
import 'package:memory_taker/data/webdav.dart';
import 'package:memory_taker/model/watch_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('simultaneous imports keep every record on disk', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('mt-overlap-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = await JournalStore.open(directory: directory);
    WatchEntry entry(String id) => WatchEntry(
      id: id,
      title: id,
      kind: WatchKind.anime,
      status: WatchStatus.completed,
      updatedAt: DateTime.utc(2026, 11, 25),
    );
    await Future.wait([
      store.putAll([entry('first')]),
      store.putAll([entry('second')]),
    ]);
    final reopened = await JournalStore.open(directory: directory);
    expect(reopened.byId('first')?.title, 'first');
    expect(reopened.byId('second')?.title, 'second');
  });

  test('record dates, rating and tombstone survive JSON round trip', () {
    final entry = WatchEntry(
      id: 'b123',
      bangumiId: 123,
      title: '作品',
      kind: WatchKind.anime,
      status: WatchStatus.completed,
      updatedAt: DateTime.utc(2026, 1, 1),
      firstWatchDate: DateTime(2024, 1, 1),
      finishDate: DateTime(2024, 2, 1),
      rewatchDates: [DateTime(2025, 8, 8)],
      rating: 8.5,
      favorite: true,
      notes: '喜欢',
      deleted: true,
    );
    final decoded = WatchEntry.fromJson(jsonDecode(jsonEncode(entry.toJson())));
    expect(decoded.firstWatchDate, DateTime(2024, 1, 1));
    expect(decoded.rewatchDates.single, DateTime(2025, 8, 8));
    expect(decoded.rating, 8.5);
    expect(decoded.favorite, true);
    expect(decoded.deleted, true);
  });

  test('partial dates retain their precision and history order', () {
    final entry = WatchEntry(
      id: 'partial1',
      title: '只记得月份的作品',
      kind: WatchKind.anime,
      status: WatchStatus.completed,
      firstWatchDate: DateTime(2024, 8),
      firstWatchPrecision: DatePrecision.month,
      finishDate: DateTime(2025),
      finishPrecision: DatePrecision.year,
      rewatchDates: [DateTime(2026, 7)],
      rewatchDatePrecisions: const [DatePrecision.month],
      historyOrder: 42,
      updatedAt: DateTime.utc(2026, 11, 27),
    );
    final decoded = WatchEntry.fromJson(entry.toJson());
    expect(decoded.firstWatchDate, DateTime(2024, 8));
    expect(decoded.firstWatchPrecision, DatePrecision.month);
    expect(decoded.finishPrecision, DatePrecision.year);
    expect(decoded.rewatchDatePrecisions.single, DatePrecision.month);
    expect(decoded.historyOrder, 42);
    final legacy = WatchEntry.fromJson(
      {...entry.toJson()}
        ..remove('firstWatchPrecision')
        ..remove('rewatchDatePrecisions'),
    );
    expect(legacy.firstWatchPrecision, DatePrecision.day);
    expect(legacy.rewatchDatePrecisions, isEmpty);
  });

  test(
    'Bangumi refresh preserves journal fields and custom episode count',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('mt-bgm-test-');
      addTearDown(() => directory.delete(recursive: true));
      final store = await JournalStore.open(directory: directory);
      await store.putAll([
        WatchEntry(
          id: 'b1',
          bangumiId: 1,
          title: '我的标题',
          kind: WatchKind.ova,
          status: WatchStatus.completed,
          firstWatchDate: DateTime(2025),
          firstWatchPrecision: DatePrecision.year,
          notes: '我的评价',
          episodeCount: 8,
          episodeCountManual: true,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        WatchEntry(
          id: 'b2',
          bangumiId: 2,
          title: '自动集数',
          kind: WatchKind.anime,
          status: WatchStatus.watching,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);
      final result = await BangumiMetadataSync(client: _FakeBangumiClient())
          .sync(store);
      expect(result.checked, 2);
      expect(result.updated, 2);
      expect(result.failed, 0);
      expect(store.byId('b1')?.title, '我的标题');
      expect(store.byId('b1')?.notes, '我的评价');
      expect(store.byId('b1')?.firstWatchPrecision, DatePrecision.year);
      expect(store.byId('b1')?.kind, WatchKind.ova);
      expect(store.byId('b1')?.episodeCount, 8);
      expect(store.byId('b1')?.coverUrl, 'https://example.com/cover.jpg');
      expect(store.byId('b2')?.episodeCount, 12);
    },
  );

  test('OVA and custom episode count survive export and import', () {
    final entry = WatchEntry(
      id: 'ova1',
      title: '特别篇',
      kind: WatchKind.ova,
      status: WatchStatus.watching,
      updatedAt: DateTime.utc(2026),
      episodeCount: 4,
      episodeCountManual: true,
    );
    final serialized = entry.toJson();
    expect(serialized['kind'], 'anime');
    expect(serialized['mediaSubtype'], 'ova');
    expect(serialized['ovaOverride'], true);
    final restored = WatchEntry.fromJson(serialized);
    expect(restored.kind, WatchKind.ova);
    expect(restored.episodeCountManual, true);
    expect(restored.episodeCount, 4);
    final legacy = WatchEntry.fromJson(
      {...entry.toJson()}..remove('episodeCountManual'),
    );
    expect(legacy.episodeCountManual, true);
    final oldTag = WatchEntry.fromJson(
      {...entry.toJson(), 'kind': 'anime', 'ovaOverride': true}
        ..remove('mediaSubtype'),
    );
    expect(oldTag.kind, WatchKind.ova);
    final explicitNonOva = WatchEntry.fromJson(
      {
        ...entry.toJson(),
        'title': '第1卷OVA',
        'kind': 'anime',
        'ovaOverride': false,
      }..remove('mediaSubtype'),
    );
    expect(explicitNonOva.kind, WatchKind.anime);
  });

  test('Bangumi OVA platform is recognized as a type', () {
    final subject = BangumiSubject.fromJson({
      'id': 123,
      'name': 'OVA sample',
      'type': 2,
      'platform': 'OVA',
    });
    expect(subject.isOva, true);
    expect(
      BangumiSubject.fromJson({
        'id': 125,
        'name': 'OAD sample',
        'type': 2,
        'platform': 'OAD',
      }).isOva,
      true,
    );
    expect(
      BangumiSubject.fromJson({
        'id': 124,
        'name': 'TV sample',
        'type': 2,
        'platform': 'TV',
      }).isOva,
      false,
    );
  });

  test('Bangumi movie episode count uses aired episodes', () {
    final subject = BangumiSubject.fromJson({
      'id': 215425,
      'name': 'Movie',
      'type': 2,
      'platform': '剧场版',
      'total_episodes': 4,
      'eps': 1,
    });
    expect(subject.episodeCount, 1);
  });

  test(
    'deliberate backup restore revives tombstones with a newer timestamp',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'mt-restore-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = await JournalStore.open(directory: directory);
      final entry = WatchEntry(
        id: 'restore1',
        title: '保留的评价',
        kind: WatchKind.ova,
        status: WatchStatus.completed,
        notes: '备份内容',
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      await store.put(entry);
      final backup = encodeEntries(store.entries);
      await store.put(
        entry.copyWith(deleted: true, updatedAt: DateTime.utc(2026, 1, 2)),
      );
      expect(
        await const ExternalImportService().importMtJson(store, backup),
        0,
      );
      expect(store.entries, isEmpty);
      expect(
        await const ExternalImportService().importMtJson(
          store,
          backup,
          restoreDeleted: true,
        ),
        1,
      );
      expect(store.byId('restore1')?.deleted, false);
      expect(store.byId('restore1')?.kind, WatchKind.ova);
      expect(store.byId('restore1')?.notes, '备份内容');
      expect(
        store.byId('restore1')!.updatedAt.isAfter(DateTime.utc(2026, 1, 2)),
        true,
      );
    },
  );

  test(
    'replace all uses file contents even when local records are newer',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'mt-replace-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = await JournalStore.open(directory: directory);
      await store.putAll([
        WatchEntry(
          id: 'old-linked',
          bangumiId: 42,
          title: '旧标题',
          kind: WatchKind.anime,
          status: WatchStatus.watching,
          updatedAt: DateTime.utc(2026, 12, 1),
        ),
        WatchEntry(
          id: 'old-unlinked',
          title: '不在新清单中',
          kind: WatchKind.anime,
          status: WatchStatus.completed,
          updatedAt: DateTime.utc(2026, 12, 1),
        ),
      ]);
      final file = encodeEntries([
        WatchEntry(
          id: 'file-linked',
          bangumiId: 42,
          title: '新标题',
          kind: WatchKind.ova,
          status: WatchStatus.completed,
          updatedAt: DateTime.utc(2026, 11, 1),
        ),
        WatchEntry(
          id: 'file-new',
          title: '新作品',
          kind: WatchKind.movie,
          status: WatchStatus.completed,
          updatedAt: DateTime.utc(2026, 11, 1),
        ),
      ]);
      expect(await const ExternalImportService().importMtJson(store, file), 1);
      expect(
        await const ExternalImportService().importMtJson(
          store,
          file,
          replaceAll: true,
        ),
        2,
      );
      expect(store.entries.map((entry) => entry.title).toSet(), {'新标题', '新作品'});
      expect(store.byId('old-linked')?.kind, WatchKind.ova);
      expect(store.byId('old-linked')?.title, '新标题');
      expect(store.byId('file-linked'), isNull);
      expect(store.byId('old-unlinked')?.deleted, true);
      final reopened = await JournalStore.open(directory: directory);
      expect(reopened.entries.length, 2);
      expect(reopened.byId('old-linked')?.title, '新标题');
    },
  );

  test('unchanged WebDAV ETag avoids downloading records again', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('mt-etag-test-');
    final cacheDirectory = await Directory.systemTemp.createTemp(
      'mt-etag-cache-',
    );
    addTearDown(() async {
      await directory.delete(recursive: true);
      await cacheDirectory.delete(recursive: true);
    });
    final store = await JournalStore.open(directory: directory);
    var version = 'v1';
    var gets = 0;
    WatchEntry remote(String title, int day) => WatchEntry(
      id: 'remote1',
      title: title,
      kind: WatchKind.anime,
      status: WatchStatus.completed,
      updatedAt: DateTime.utc(2026, 1, day),
    );
    var body = jsonEncode(remote('旧标题', 1).toJson());
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(
          '<d:multistatus xmlns:d="DAV:"><d:response>'
          '<d:href>/MT/records/remote1.json</d:href>'
          '<d:propstat><d:prop><d:getetag>$version</d:getetag></d:prop>'
          '<d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
          '</d:response></d:multistatus>',
        );
      } else if (request.method == 'GET') {
        gets++;
        request.response.write(body);
      } else {
        request.response.statusCode = 405;
      }
      await request.response.close();
    });
    try {
      final credentials = DavCredentials(
        'http://127.0.0.1:${server.port}/',
        'user',
        'pass',
      );
      await const MtSyncService().sync(
        store,
        credentials,
        cacheDirectory: cacheDirectory,
      );
      expect(gets, 1);
      await const MtSyncService().sync(
        store,
        credentials,
        cacheDirectory: cacheDirectory,
      );
      expect(gets, 1);
      version = 'v2';
      body = jsonEncode(remote('新标题', 2).toJson());
      await const MtSyncService().sync(
        store,
        credentials,
        cacheDirectory: cacheDirectory,
      );
      expect(gets, 2);
      expect(store.byId('remote1')?.title, '新标题');
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'MT WebDAV sync merges separate records and retains deletions',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await JournalStore.open(
        directory: await Directory.systemTemp.createTemp('mt-sync-test-'),
      );
      final local = WatchEntry(
        id: 'm1',
        title: '本地',
        kind: WatchKind.movie,
        status: WatchStatus.completed,
        updatedAt: DateTime.utc(2026, 1, 2),
      );
      await store.put(local);
      final remote = WatchEntry(
        id: 'm2',
        title: '远端',
        kind: WatchKind.series,
        status: WatchStatus.dropped,
        updatedAt: DateTime.utc(2026, 1, 3),
        deleted: true,
      );
      final files = <String, String>{
        'MT/records/m2.json': jsonEncode(remote.toJson()),
      };
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final path = request.uri.path.substring(1);
        request.response.statusCode = switch (request.method) {
          'MKCOL' => 201,
          'PROPFIND' => 207,
          'GET' => files.containsKey(path) ? 200 : 404,
          'PUT' => 201,
          _ => 405,
        };
        if (request.method == 'PROPFIND') {
          request.response.write(
            '<d:multistatus xmlns:d="DAV:">'
            '<d:response><d:href>/MT/records/</d:href></d:response>'
            '<d:response><d:href>/MT/records/m2.json</d:href></d:response>'
            '</d:multistatus>',
          );
        } else if (request.method == 'GET') {
          request.response.write(files[path] ?? '');
        } else if (request.method == 'PUT') {
          files[path] = await utf8.decodeStream(request);
        }
        await request.response.close();
      });
      try {
        final result = await const MtSyncService().sync(
          store,
          DavCredentials('http://127.0.0.1:${server.port}/', 'user', 'pass'),
          cacheDirectory: await Directory.systemTemp.createTemp(
            'mt-sync-cache-',
          ),
        );
        expect(result.downloaded, 1);
        expect(result.uploaded, 1);
        expect(store.byId('m2')?.deleted, true);
        expect(files.containsKey('MT/records/m1.json'), true);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('Kazumi snapshot and change log import play position without replacing notes', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await JournalStore.open(
      directory: await Directory.systemTemp.createTemp('mt-import-test-'),
    );
    final existing = WatchEntry(
      id: 'b123',
      bangumiId: 123,
      title: '我的标题',
      kind: WatchKind.anime,
      status: WatchStatus.completed,
      notes: '我的评价',
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    await store.put(existing);
    final bgm = {
      'id': 123,
      'name': 'Original',
      'nameCn': '中文名',
      'summary': '简介',
      'images': {'large': 'https://example.com/cover.jpg'},
    };
    final snapshot = jsonEncode({
      'histories': [
        {
          'bangumiItem': bgm,
          'adapterName': 'source',
          'lastWatchEpisode': 2,
          'lastWatchTime': 1000,
          'progresses': {
            '2': {'progressMs': 10000},
          },
        },
      ],
    });
    final event = jsonEncode({
      'op': 'upsertWatchState',
      'updatedAt': 2000,
      'bangumiItem': bgm,
      'adapterName': 'source',
      'episode': 3,
    });
    final progress = jsonEncode({
      'op': 'upsertProgress',
      'updatedAt': 2001,
      'bangumiItem': bgm,
      'adapterName': 'source',
      'episode': 3,
      'progressMs': 33000,
    });
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path.endsWith('snapshot.json')) {
        request.response.write(snapshot);
      } else if (path.endsWith('changes/')) {
        request.response.statusCode = 207;
        request.response.write(
          '<d:multistatus xmlns:d="DAV:">'
          '<d:response><d:href>/kazumiSync/history/changes/</d:href></d:response>'
          '<d:response><d:href>/kazumiSync/history/changes/device.jsonl</d:href></d:response>'
          '</d:multistatus>',
        );
      } else if (path.endsWith('device.jsonl')) {
        request.response.write('$event\n$progress\n');
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    try {
      final cacheDirectory = await Directory.systemTemp.createTemp(
        'kazumi-cache-',
      );
      final count = await const KazumiImportService().import(
        store,
        DavCredentials('http://127.0.0.1:${server.port}/', 'user', 'pass'),
        cacheDirectory: cacheDirectory,
      );
      expect(count, 1);
      expect(store.byId('b123')?.title, '我的标题');
      expect(store.byId('b123')?.notes, '我的评价');
      expect(store.byId('b123')?.status, WatchStatus.completed);
      expect(store.byId('b123')?.episode, 3);
      expect(store.byId('b123')?.progressMs, 33000);
      await store.put(store.byId('b123')!.copyWith(deleted: true));
      expect(
        await const KazumiImportService().import(
          store,
          DavCredentials('http://127.0.0.1:${server.port}/', 'user', 'pass'),
          cacheDirectory: cacheDirectory,
        ),
        0,
      );
      expect(store.byId('b123')?.deleted, true);
    } finally {
      await server.close(force: true);
    }
  });

  test('external MT import keeps newer local data and avoids duplicate Bangumi records', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await JournalStore.open(
      directory: await Directory.systemTemp.createTemp('mt-file-test-'),
    );
    final local = WatchEntry(
      id: 'b123',
      bangumiId: 123,
      title: '本机较新',
      kind: WatchKind.anime,
      status: WatchStatus.completed,
      updatedAt: DateTime.utc(2026, 2, 1),
    );
    await store.put(local);
    final stale = local.copyWith(
      title: '旧备份',
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final fresh = WatchEntry(
      id: 'other-id',
      bangumiId: 123,
      title: '新备份',
      kind: WatchKind.anime,
      status: WatchStatus.watching,
      updatedAt: DateTime.utc(2026, 3, 1),
    );
    final newMovie = WatchEntry(
      id: 'movie',
      title: '新电影',
      kind: WatchKind.movie,
      status: WatchStatus.planned,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final count = await const ExternalImportService().importMtJson(
      store,
      encodeEntries([stale, fresh, newMovie]),
    );
    expect(count, 2);
    expect(store.byId('b123')?.title, '新备份');
    expect(store.byId('other-id'), isNull);
    expect(store.byId('movie')?.title, '新电影');
  });

  test('local Kazumi snapshot and changes import play progress', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await JournalStore.open(
      directory: await Directory.systemTemp.createTemp('kazumi-file-test-'),
    );
    final item = {'id': 321, 'name': '作品', 'nameCn': '中文名'};
    final snapshot = jsonEncode({
      'histories': [
        {
          'bangumiItem': item,
          'adapterName': 'source',
          'lastWatchEpisode': 1,
          'lastWatchTime': 1000,
          'progresses': {
            '1': {'progressMs': 5000},
          },
        },
      ],
    });
    final change = jsonEncode({
      'op': 'upsertProgress',
      'updatedAt': 2000,
      'bangumiItem': item,
      'adapterName': 'source',
      'episode': 1,
      'progressMs': 15000,
    });
    final count = await const KazumiImportService().importLocal(
      store,
      snapshot: snapshot,
      changeLogs: ['$change\n'],
    );
    expect(count, 1);
    expect(store.byBangumiId(321)?.progressMs, 15000);
    expect(store.byBangumiId(321)?.status, WatchStatus.watching);
  });
}

class _FakeBangumiClient extends BangumiClient {
  @override
  Future<BangumiSubject> detail(int id, {bool refresh = false}) async =>
      BangumiSubject(
        id: id,
        title: '官方名称',
        originalTitle: 'Official Name',
        summary: '官方简介',
        coverUrl: 'https://example.com/cover.jpg',
        type: 2,
        episodeCount: 12,
      );
}
