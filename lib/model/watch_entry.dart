import 'dart:convert';
import 'dart:math';

enum WatchKind { anime, ova, movie, series }

enum WatchStatus { planned, watching, completed, paused, dropped }

enum DatePrecision { year, month, day }

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
    this.firstWatchPrecision = DatePrecision.day,
    this.finishDate,
    this.finishPrecision = DatePrecision.day,
    this.dropDate,
    this.dropPrecision = DatePrecision.day,
    this.rewatchDates = const [],
    this.rewatchDatePrecisions = const [],
    this.historyOrder,
    this.rating,
    this.favorite = false,
    this.notes = '',
    this.episode,
    this.episodeCount,
    this.episodeCountManual = false,
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
  final DatePrecision firstWatchPrecision;
  final DateTime? finishDate;
  final DatePrecision finishPrecision;
  final DateTime? dropDate;
  final DatePrecision dropPrecision;
  final List<DateTime> rewatchDates;
  final List<DatePrecision> rewatchDatePrecisions;
  final int? historyOrder;
  final double? rating;
  final bool favorite;
  final String notes;
  final int? episode;
  final int? episodeCount;
  final bool episodeCountManual;
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
    DatePrecision? firstWatchPrecision,
    DateTime? finishDate,
    DatePrecision? finishPrecision,
    DateTime? dropDate,
    DatePrecision? dropPrecision,
    List<DateTime>? rewatchDates,
    List<DatePrecision>? rewatchDatePrecisions,
    int? historyOrder,
    double? rating,
    bool? favorite,
    String? notes,
    int? episode,
    int? episodeCount,
    bool? episodeCountManual,
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
    firstWatchPrecision: firstWatchPrecision ?? this.firstWatchPrecision,
    finishDate: finishDate ?? this.finishDate,
    finishPrecision: finishPrecision ?? this.finishPrecision,
    dropDate: dropDate ?? this.dropDate,
    dropPrecision: dropPrecision ?? this.dropPrecision,
    rewatchDates: rewatchDates ?? this.rewatchDates,
    rewatchDatePrecisions: rewatchDatePrecisions ?? this.rewatchDatePrecisions,
    historyOrder: historyOrder ?? this.historyOrder,
    rating: rating ?? this.rating,
    favorite: favorite ?? this.favorite,
    notes: notes ?? this.notes,
    episode: episode ?? this.episode,
    episodeCount: episodeCount ?? this.episodeCount,
    episodeCountManual: episodeCountManual ?? this.episodeCountManual,
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
    // Keep the legacy kind readable by older clients while storing OVA as a type.
    'kind': kind == WatchKind.ova ? WatchKind.anime.name : kind.name,
    'mediaSubtype': kind == WatchKind.ova ? 'ova' : '',
    'ovaOverride': kind == WatchKind.ova,
    'status': status.name,
    'firstWatchDate': firstWatchDate?.toIso8601String(),
    'firstWatchPrecision': firstWatchPrecision.name,
    'finishDate': finishDate?.toIso8601String(),
    'finishPrecision': finishPrecision.name,
    'dropDate': dropDate?.toIso8601String(),
    'dropPrecision': dropPrecision.name,
    'rewatchDates': rewatchDates.map((e) => e.toIso8601String()).toList(),
    'rewatchDatePrecisions': rewatchDatePrecisions.map((e) => e.name).toList(),
    'historyOrder': historyOrder,
    'rating': rating,
    'favorite': favorite,
    'notes': notes,
    'episode': episode,
    'episodeCount': episodeCount,
    'episodeCountManual': episodeCountManual,
    'progressMs': progressMs,
    'lastWatchAt': lastWatchAt?.toIso8601String(),
    'kazumiSource': kazumiSource,
    'updatedAt': updatedAt.toIso8601String(),
    'deleted': deleted,
  };

  static DateTime? _date(dynamic value) =>
      value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

  static DatePrecision _precision(dynamic value) =>
      DatePrecision.values.firstWhere(
        (item) => item.name == value,
        orElse: () => DatePrecision.day,
      );

  static WatchKind _kind(Map<String, dynamic> json) {
    final raw = json['kind'] as String? ?? 'anime';
    if (json.containsKey('mediaSubtype')) {
      return json['mediaSubtype'] == 'ova'
          ? WatchKind.ova
          : WatchKind.values.byName(raw);
    }
    // Convert records written by v1.1.0, where OVA was only a display tag.
    final override = json['ovaOverride'] as bool?;
    final title = json['title'] as String? ?? '';
    final oldTag =
        override ??
        RegExp(
          r'(^|[^A-Za-z])OVA([^A-Za-z]|$)',
          caseSensitive: false,
        ).hasMatch(title);
    return oldTag || raw == 'ova'
        ? WatchKind.ova
        : WatchKind.values.byName(raw);
  }

  factory WatchEntry.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported MT record');
    }
    return WatchEntry(
      id: json['id'] as String,
      bangumiId: (json['bangumiId'] as num?)?.toInt(),
      title: json['title'] as String? ?? '',
      originalTitle: json['originalTitle'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      kind: _kind(json),
      status: WatchStatus.values.byName(json['status'] as String? ?? 'planned'),
      firstWatchDate: _date(json['firstWatchDate']),
      firstWatchPrecision: _precision(json['firstWatchPrecision']),
      finishDate: _date(json['finishDate']),
      finishPrecision: _precision(json['finishPrecision']),
      dropDate: _date(json['dropDate']),
      dropPrecision: _precision(json['dropPrecision']),
      rewatchDates: (json['rewatchDates'] as List? ?? const [])
          .map(_date)
          .whereType<DateTime>()
          .toList(),
      rewatchDatePrecisions:
          (json['rewatchDatePrecisions'] as List? ?? const [])
              .map(_precision)
              .toList(),
      historyOrder: (json['historyOrder'] as num?)?.toInt(),
      rating: (json['rating'] as num?)?.toDouble(),
      favorite: json['favorite'] == true,
      notes: json['notes'] as String? ?? '',
      episode: (json['episode'] as num?)?.toInt(),
      episodeCount: (json['episodeCount'] as num?)?.toInt(),
      episodeCountManual:
          json['episodeCountManual'] as bool? ?? json['episodeCount'] != null,
      progressMs: (json['progressMs'] as num?)?.toInt(),
      lastWatchAt: _date(json['lastWatchAt']),
      kazumiSource: json['kazumiSource'] as String? ?? '',
      updatedAt:
          _date(json['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      deleted: json['deleted'] == true,
    );
  }
}

String encodeEntries(Iterable<WatchEntry> entries) => jsonEncode({
  'schemaVersion': 1,
  'entries': entries.map((e) => e.toJson()).toList(),
});
