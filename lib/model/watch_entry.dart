import 'dart:convert';
import 'dart:math';

enum WatchKind { anime, movie, series }
enum WatchStatus { planned, watching, completed, paused, dropped }

String newEntryId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  return 'm${bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';
}

class WatchEntry {
  const WatchEntry({
    required this.id,
    required this.title,
    required this.kind,
    required this.status,
    required this.updatedAt,
    this.bangumiId,
    this.originalTitle = '',
    this.summary = '',
    this.coverUrl = '',
    this.firstWatchDate,
    this.finishDate,
    this.dropDate,
    this.rewatchDates = const [],
    this.rating,
    this.favorite = false,
    this.notes = '',
    this.episode,
    this.episodeCount,
    this.progressMs,
    this.lastWatchAt,
    this.kazumiSource = '',
    this.deleted = false,
  });

  final String id;
  final int? bangumiId;
  final String title;
  final String originalTitle;
  final String summary;
  final String coverUrl;
  final WatchKind kind;
  final WatchStatus status;
  final DateTime? firstWatchDate;
  final DateTime? finishDate;
  final DateTime? dropDate;
  final List<DateTime> rewatchDates;
  final double? rating;
  final bool favorite;
  final String notes;
  final int? episode;
  final int? episodeCount;
  final int? progressMs;
  final DateTime? lastWatchAt;
  final String kazumiSource;
  final DateTime updatedAt;
  final bool deleted;

  WatchEntry copyWith({
    String? title,
    String? originalTitle,
    String? summary,
    String? coverUrl,
    WatchKind? kind,
    WatchStatus? status,
    DateTime? firstWatchDate,
    DateTime? finishDate,
    DateTime? dropDate,
    List<DateTime>? rewatchDates,
    double? rating,
    bool? favorite,
    String? notes,
    int? episode,
    int? episodeCount,
    int? progressMs,
    DateTime? lastWatchAt,
    String? kazumiSource,
    DateTime? updatedAt,
    bool? deleted,
  }) => WatchEntry(
        id: id,
        bangumiId: bangumiId,
        title: title ?? this.title,
        originalTitle: originalTitle ?? this.originalTitle,
        summary: summary ?? this.summary,
        coverUrl: coverUrl ?? this.coverUrl,
        kind: kind ?? this.kind,
        status: status ?? this.status,
        firstWatchDate: firstWatchDate ?? this.firstWatchDate,
        finishDate: finishDate ?? this.finishDate,
        dropDate: dropDate ?? this.dropDate,
        rewatchDates: rewatchDates ?? this.rewatchDates,
        rating: rating ?? this.rating,
        favorite: favorite ?? this.favorite,
        notes: notes ?? this.notes,
        episode: episode ?? this.episode,
        episodeCount: episodeCount ?? this.episodeCount,
        progressMs: progressMs ?? this.progressMs,
        lastWatchAt: lastWatchAt ?? this.lastWatchAt,
        kazumiSource: kazumiSource ?? this.kazumiSource,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'bangumiId': bangumiId,
        'title': title,
        'originalTitle': originalTitle,
        'summary': summary,
        'coverUrl': coverUrl,
        'kind': kind.name,
        'status': status.name,
        'firstWatchDate': firstWatchDate?.toIso8601String(),
        'finishDate': finishDate?.toIso8601String(),
        'dropDate': dropDate?.toIso8601String(),
        'rewatchDates': rewatchDates.map((e) => e.toIso8601String()).toList(),
        'rating': rating,
        'favorite': favorite,
        'notes': notes,
        'episode': episode,
        'episodeCount': episodeCount,
        'progressMs': progressMs,
        'lastWatchAt': lastWatchAt?.toIso8601String(),
        'kazumiSource': kazumiSource,
        'updatedAt': updatedAt.toIso8601String(),
        'deleted': deleted,
      };

  static DateTime? _date(dynamic value) => value is String && value.isNotEmpty
      ? DateTime.tryParse(value)
      : null;

  factory WatchEntry.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) throw const FormatException('Unsupported MT record');
    return WatchEntry(
      id: json['id'] as String,
      bangumiId: (json['bangumiId'] as num?)?.toInt(),
      title: json['title'] as String? ?? '',
      originalTitle: json['originalTitle'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      kind: WatchKind.values.byName(json['kind'] as String? ?? 'anime'),
      status: WatchStatus.values.byName(json['status'] as String? ?? 'planned'),
      firstWatchDate: _date(json['firstWatchDate']),
      finishDate: _date(json['finishDate']),
      dropDate: _date(json['dropDate']),
      rewatchDates: (json['rewatchDates'] as List? ?? const [])
          .map(_date).whereType<DateTime>().toList(),
      rating: (json['rating'] as num?)?.toDouble(),
      favorite: json['favorite'] == true,
      notes: json['notes'] as String? ?? '',
      episode: (json['episode'] as num?)?.toInt(),
      episodeCount: (json['episodeCount'] as num?)?.toInt(),
      progressMs: (json['progressMs'] as num?)?.toInt(),
      lastWatchAt: _date(json['lastWatchAt']),
      kazumiSource: json['kazumiSource'] as String? ?? '',
      updatedAt: _date(json['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      deleted: json['deleted'] == true,
    );
  }
}

String encodeEntries(Iterable<WatchEntry> entries) => jsonEncode({
      'schemaVersion': 1,
      'entries': entries.map((e) => e.toJson()).toList(),
    });
