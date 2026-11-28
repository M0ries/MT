import '../model/watch_entry.dart';
import 'bangumi.dart';
import 'journal_store.dart';

class BangumiMetadataResult {
  const BangumiMetadataResult(this.checked, this.updated, this.failed);
  final int checked;
  final int updated;
  final int failed;
}

class BangumiMetadataSync {
  const BangumiMetadataSync({this.client});
  final BangumiClient? client;

  Future<BangumiMetadataResult> sync(
    JournalStore store, {
    bool force = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final byId = <int, List<String>>{};
    for (final entry in store.entries) {
      final id = entry.bangumiId;
      if (id != null) byId.putIfAbsent(id, () => []).add(entry.id);
    }
    final ids = byId.keys.toList();
    if (ids.isEmpty) return const BangumiMetadataResult(0, 0, 0);
    final api = client ?? BangumiClient();
    var checked = 0;
    var updated = 0;
    var failed = 0;
    for (var offset = 0; offset < ids.length; offset += 16) {
      final batch = ids.skip(offset).take(16).toList();
      final subjects = <BangumiSubject?>[];
      for (var part = 0; part < batch.length; part += 4) {
        subjects.addAll(
          await Future.wait(
            batch.skip(part).take(4).map((id) async {
              try {
                return await api.detail(id, refresh: force);
              } catch (_) {
                return null;
              }
            }),
          ),
        );
      }
      final changes = <WatchEntry>[];
      for (var i = 0; i < batch.length; i++) {
        final subject = subjects[i];
        if (subject == null) {
          failed++;
          continue;
        }
        for (final entryId in byId[batch[i]]!) {
          final current = store.byId(entryId);
          if (current == null || current.deleted) continue;
          final originalTitle = subject.originalTitle.isEmpty
              ? current.originalTitle
              : subject.originalTitle;
          final summary = subject.summary.isEmpty
              ? current.summary
              : subject.summary;
          final coverUrl = subject.coverUrl.isEmpty
              ? current.coverUrl
              : subject.coverUrl;
          final episodeCount =
              current.episodeCountManual || subject.episodeCount <= 0
              ? current.episodeCount
              : subject.episodeCount;
          if (originalTitle == current.originalTitle &&
              summary == current.summary &&
              coverUrl == current.coverUrl &&
              episodeCount == current.episodeCount) {
            continue;
          }
          final now = DateTime.now().toUtc();
          changes.add(
            current.copyWith(
              originalTitle: originalTitle,
              summary: summary,
              coverUrl: coverUrl,
              episodeCount: episodeCount,
              updatedAt: now.isAfter(current.updatedAt)
                  ? now
                  : current.updatedAt.add(const Duration(milliseconds: 1)),
            ),
          );
        }
      }
      if (changes.isNotEmpty) {
        await store.putAll(changes);
        updated += changes.length;
      }
      checked += batch.length;
      onProgress?.call(checked, ids.length);
    }
    return BangumiMetadataResult(checked, updated, failed);
  }
}
