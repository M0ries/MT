import 'dart:convert';

import '../model/watch_entry.dart';
import 'journal_store.dart';
import 'webdav.dart';

class KazumiImportService {
  const KazumiImportService();

  Future<int> import(JournalStore store, DavCredentials credentials) async {
    final client = WebDavClient(credentials);
    try {
      final raw = await client.read('kazumiSync/history/snapshot.json');
      final histories = <String, _KazumiHistory>{};
      if (raw != null) {
        final snapshot = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        for (final value in snapshot['histories'] as List? ?? const []) {
          final map = Map<String, dynamic>.from(value as Map);
          final history = _KazumiHistory.fromSnapshot(map);
          if (history != null) histories[history.key] = history;
        }
      }

      List<String> files;
      try {
        files = await client.listFiles('kazumiSync/history/changes/');
      } catch (_) {
        files = const [];
      }
      final events = <Map<String, dynamic>>[];
      for (final file in files.where((f) => f.endsWith('.jsonl'))) {
        final text = await client.read('kazumiSync/history/changes/$file');
        if (text == null) continue;
        for (final line in const LineSplitter().convert(text)) {
          if (line.trim().isEmpty) continue;
          events.add(Map<String, dynamic>.from(jsonDecode(line) as Map));
        }
      }
      events.sort((a, b) {
        final time = ((a['updatedAt'] as num?)?.toInt() ?? 0)
            .compareTo((b['updatedAt'] as num?)?.toInt() ?? 0);
        if (time != 0) return time;
        // Kazumi writes progress and watch-state at the same time.
        if (a['op'] == 'upsertWatchState' && b['op'] == 'upsertProgress') return -1;
        if (a['op'] == 'upsertProgress' && b['op'] == 'upsertWatchState') return 1;
        return 0;
      });
      for (final event in events) {
        final op = event['op'];
        final time = (event['updatedAt'] as num?)?.toInt() ?? 0;
        if (op == 'clearAll') {
          histories.removeWhere((_, h) => h.lastWatchMs <= time);
        } else if (op == 'deleteHistory') {
          final key = event['entityKey'] as String? ?? '';
          histories.remove(key);
          histories.remove('$key::online');
        } else if (op == 'upsertWatchState' || op == 'upsertProgress') {
          final item = event['bangumiItem'];
          if (item is! Map) continue;
          final bgm = Map<String, dynamic>.from(item);
          final id = (bgm['id'] as num?)?.toInt();
          if (id == null || id <= 0) continue;
          final adapter = event['adapterName'] as String? ?? '';
          final key = '$adapter$id::${event['entryKind'] ?? 'online'}';
          final current = histories[key];
          histories[key] = _KazumiHistory.fromEvent(event, current);
        }
      }

      if (raw == null && files.isEmpty) {
        throw const FormatException('未找到 Kazumi 新版观看历史（snapshot.json / changes/*.jsonl）');
      }
      final latestById = <int, _KazumiHistory>{};
      for (final history in histories.values) {
        final old = latestById[history.bangumiId];
        if (old == null || history.lastWatchMs > old.lastWatchMs) {
          latestById[history.bangumiId] = history;
        }
      }
      final updates = <WatchEntry>[];
      for (final h in latestById.values) {
        final existing = store.byBangumiId(h.bangumiId, includeDeleted: true);
        if (existing?.deleted == true) continue;
        if (existing != null &&
            (existing.lastWatchAt?.millisecondsSinceEpoch ?? 0) >= h.lastWatchMs) {
          continue;
        }
        final title = h.nameCn.isNotEmpty ? h.nameCn : h.name;
        if (title.isEmpty) continue;
        if (existing == null) {
          updates.add(WatchEntry(
            id: 'b${h.bangumiId}',
            bangumiId: h.bangumiId,
            title: title,
            originalTitle: h.name,
            summary: h.summary,
            coverUrl: h.coverUrl,
            kind: WatchKind.anime,
            status: WatchStatus.watching,
            episode: h.episode,
            progressMs: h.progressMs,
            lastWatchAt: DateTime.fromMillisecondsSinceEpoch(h.lastWatchMs, isUtc: true),
            kazumiSource: h.adapter,
            updatedAt: DateTime.now().toUtc(),
          ));
        } else {
          updates.add(existing.copyWith(
            summary: existing.summary.isEmpty ? h.summary : null,
            coverUrl: existing.coverUrl.isEmpty ? h.coverUrl : null,
            episode: h.episode,
            progressMs: h.progressMs,
            lastWatchAt: DateTime.fromMillisecondsSinceEpoch(h.lastWatchMs, isUtc: true),
            kazumiSource: h.adapter,
          ));
        }
      }
      if (updates.isNotEmpty) await store.putAll(updates);
      return updates.length;
    } finally {
      client.close();
    }
  }
}

class _KazumiHistory {
  const _KazumiHistory({required this.key, required this.adapter,
    required this.bangumiId, required this.name, required this.nameCn,
    required this.summary, required this.coverUrl, required this.lastWatchMs,
    required this.episode, required this.progressMs});

  final String key, adapter, name, nameCn, summary, coverUrl;
  final int bangumiId, lastWatchMs, episode, progressMs;

  static _KazumiHistory? fromSnapshot(Map<String, dynamic> json) {
    final item = json['bangumiItem'];
    if (item is! Map) return null;
    final bgm = Map<String, dynamic>.from(item);
    final id = (bgm['id'] as num?)?.toInt();
    if (id == null || id <= 0) return null;
    final adapter = json['adapterName'] as String? ?? '';
    final episode = (json['lastWatchEpisode'] as num?)?.toInt() ?? 0;
    final progress = (json['progresses'] as Map?)?[episode.toString()];
    return _KazumiHistory(
      key: '$adapter$id::${json['entryKind'] ?? 'online'}', adapter: adapter,
      bangumiId: id, name: bgm['name'] as String? ?? '',
      nameCn: bgm['nameCn'] as String? ?? '', summary: bgm['summary'] as String? ?? '',
      coverUrl: _cover(bgm),
      lastWatchMs: (json['lastWatchTime'] as num?)?.toInt() ?? 0,
      episode: episode,
      progressMs: progress is Map ? (progress['progressMs'] as num?)?.toInt() ?? 0 : 0,
    );
  }

  static _KazumiHistory fromEvent(Map<String, dynamic> event, _KazumiHistory? current) {
    final bgm = Map<String, dynamic>.from(event['bangumiItem'] as Map);
    final id = (bgm['id'] as num).toInt();
    final adapter = event['adapterName'] as String? ?? '';
    final episode = (event['episode'] as num?)?.toInt() ?? current?.episode ?? 0;
    final isWatch = event['op'] == 'upsertWatchState';
    final time = (event['updatedAt'] as num?)?.toInt() ?? 0;
    return _KazumiHistory(
      key: '$adapter$id::${event['entryKind'] ?? 'online'}', adapter: adapter,
      bangumiId: id, name: bgm['name'] as String? ?? current?.name ?? '',
      nameCn: bgm['nameCn'] as String? ?? current?.nameCn ?? '',
      summary: bgm['summary'] as String? ?? current?.summary ?? '',
      coverUrl: _cover(bgm).isEmpty ? current?.coverUrl ?? '' : _cover(bgm),
      lastWatchMs: isWatch || current == null ? time : current.lastWatchMs,
      episode: isWatch || current == null ? episode : current.episode,
      progressMs: event['op'] == 'upsertProgress' && episode == (current?.episode ?? episode)
          ? (event['progressMs'] as num?)?.toInt() ?? 0
          : isWatch && current != null && episode != current.episode
              ? 0 : current?.progressMs ?? 0,
    );
  }

  static String _cover(Map<String, dynamic> bgm) {
    final images = bgm['images'];
    if (images is! Map) return '';
    return (images['large'] ?? images['common'] ?? images['medium'] ?? '').toString();
  }
}
