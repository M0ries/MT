import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class ContentCache {
  ContentCache._();
  static final instance = ContentCache._();
  final Map<String, Future<File?>> _covers = {};

  Future<Directory> _directory() async {
    final base = await getApplicationCacheDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}mt-content',
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _key(String value) => sha256.convert(utf8.encode(value)).toString();

  Future<dynamic> jsonResponse(
    String key,
    Future<dynamic> Function() fetch, {
    Duration lifetime = const Duration(days: 3),
  }) async {
    final directory = await _directory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_key(key)}.json',
    );
    dynamic cached;
    if (await file.exists()) {
      try {
        cached = jsonDecode(await file.readAsString());
        if (DateTime.now().difference(await file.lastModified()) < lifetime) {
          return cached;
        }
      } catch (_) {}
    }
    try {
      final value = await fetch();
      await file.writeAsString(jsonEncode(value));
      return value;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<File?> cover(String url) =>
      _covers.putIfAbsent(url, () => _downloadCover(url));

  Future<File?> _downloadCover(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return null;
    final directory = await _directory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_key(url)}.image',
    );
    if (await file.exists() && await file.length() > 0) return file;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200 || response.contentLength > 10000000) {
        return null;
      }
      final bytes = await response
          .fold<List<int>>(<int>[], (all, chunk) {
            all.addAll(chunk);
            if (all.length > 10000000) throw const FormatException('封面文件过大');
            return all;
          })
          .timeout(const Duration(seconds: 20));
      if (bytes.isEmpty) return null;
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> clear() async {
    _covers.clear();
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
