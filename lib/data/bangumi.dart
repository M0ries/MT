import 'dart:convert';
import 'dart:io';

import 'content_cache.dart';

class BangumiSubject {
  const BangumiSubject({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.summary,
    required this.coverUrl,
    required this.type,
    required this.episodeCount,
  });
  final int id, type, episodeCount;
  final String title, originalTitle, summary, coverUrl;

  factory BangumiSubject.fromJson(Map<String, dynamic> json) {
    final images = json['images'] as Map? ?? const {};
    final name = json['name'] as String? ?? '';
    final cn = json['name_cn'] as String? ?? '';
    return BangumiSubject(
      id: (json['id'] as num).toInt(),
      title: cn.isEmpty ? name : cn,
      originalTitle: name,
      summary: json['summary'] as String? ?? '',
      coverUrl: (images['large'] ?? images['common'] ?? images['medium'] ?? '')
          .toString(),
      type: (json['type'] as num?)?.toInt() ?? 2,
      episodeCount:
          (json['total_episodes'] as num?)?.toInt() ??
          (json['eps'] as num?)?.toInt() ??
          0,
    );
  }
}

class BangumiClient {
  Future<dynamic> _request(String method, String path, [String? body]) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await http.openUrl(
        method,
        Uri.parse('https://api.bgm.tv$path'),
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'MT-MemoryTaker/1.0 (https://github.com; personal watch journal)',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('Bangumi 请求失败：HTTP ${response.statusCode}');
      }
      return jsonDecode(await utf8.decodeStream(response));
    } finally {
      http.close(force: true);
    }
  }

  Future<List<BangumiSubject>> search(String keyword) async {
    if (keyword.trim().isEmpty) return const [];
    final term = keyword.trim();
    final result = await ContentCache.instance.jsonResponse(
      'bangumi-search:$term',
      () => _request(
        'POST',
        '/v0/search/subjects?limit=20',
        jsonEncode({
          'keyword': term,
          'sort': 'match',
          'filter': {
            'type': [2, 6],
          },
        }),
      ),
      lifetime: const Duration(days: 1),
    );
    final data = result['data'] as List? ?? const [];
    return data
        .map(
          (e) => BangumiSubject.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<BangumiSubject> detail(int id, {bool refresh = false}) async {
    final result = await ContentCache.instance.jsonResponse(
      'bangumi-detail:$id',
      () => _request('GET', '/v0/subjects/$id'),
      refresh: refresh,
    );
    return BangumiSubject.fromJson(Map<String, dynamic>.from(result as Map));
  }
}
