import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DavCredentials {
  const DavCredentials(this.url, this.username, this.password);
  final String url;
  final String username;
  final String password;
}

class WebDavClient {
  WebDavClient(DavCredentials credentials)
    : _credentials = credentials,
      _base = _validateBase(credentials.url);

  final DavCredentials _credentials;
  final Uri _base;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  static Uri _validateBase(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('请输入完整的 WebDAV http(s) 地址');
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  Uri url(String path) {
    final safe = path
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return _base.resolve(path.endsWith('/') ? '$safe/' : safe);
  }

  Future<HttpClientResponse> _request(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _requestOnce(
          method,
          path,
          body: body,
          headers: headers,
        );
        if (attempt == 2 ||
            !{429, 500, 502, 503, 504}.contains(response.statusCode)) {
          return response;
        }
        await response.drain<void>().timeout(const Duration(seconds: 30));
      } on SocketException {
        if (attempt == 2) rethrow;
      } on HttpException {
        if (attempt == 2) rethrow;
      } on TimeoutException {
        if (attempt == 2) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    throw StateError('WebDAV 重试次数已用尽');
  }

  Future<HttpClientResponse> _requestOnce(
    String method,
    String path, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final request = await _http
        .openUrl(method, url(path))
        .timeout(const Duration(seconds: 20));
    request.persistentConnection = false;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Basic ${base64Encode(utf8.encode('${_credentials.username}:${_credentials.password}'))}',
    );
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'MT-MemoryTaker/1.0 (Flutter; contact via GitHub)',
    );
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    return response;
  }

  Future<String?> read(String path) async {
    return _readText('GET', path, action: '读取 $path', missingIsNull: true);
  }

  Future<String?> _readText(
    String method,
    String path, {
    required String action,
    String? body,
    Map<String, String> headers = const {},
    bool missingIsNull = false,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final response = await _request(
        method,
        path,
        body: body,
        headers: headers,
      );
      if (response.statusCode == 404 && missingIsNull) {
        await response.drain<void>();
        return null;
      }
      _check(response, action);
      try {
        return await utf8.decodeStream(
          response.timeout(const Duration(seconds: 30)),
        );
      } on HttpException {
        if (attempt == 2) rethrow;
      } on SocketException {
        if (attempt == 2) rethrow;
      } on TimeoutException {
        if (attempt == 2) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    throw StateError('WebDAV 读取重试次数已用尽');
  }

  Future<void> write(String path, String body) async {
    final response = await _request(
      'PUT',
      path,
      body: body,
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      },
    );
    _check(response, '写入 $path');
    await response.timeout(const Duration(seconds: 30)).drain<void>();
  }

  Future<void> ensureDirectory(String path) async {
    var current = '';
    for (final segment in path.split('/').where((s) => s.isNotEmpty)) {
      current = '$current$segment/';
      final response = await _request('MKCOL', current);
      if (![200, 201, 204, 301, 405].contains(response.statusCode)) {
        _check(response, '创建 $current');
      }
      await response.timeout(const Duration(seconds: 30)).drain<void>();
    }
  }

  Future<List<String>> listFiles(String path) async {
    final xml = (await _readText(
      'PROPFIND',
      path,
      action: '列出 $path',
      body: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>',
      headers: {
        'Depth': '1',
        HttpHeaders.contentTypeHeader: 'application/xml; charset=utf-8',
      },
    ))!;
    final hrefs = RegExp(
      r'<(?:[\w.-]+:)?href[^>]*>([^<]+)</(?:[\w.-]+:)?href>',
      caseSensitive: false,
    ).allMatches(xml).map((m) => m.group(1)!).toList();
    final basePath = Uri.decodeComponent(url(path).path)
        .replaceAll(RegExp(r'/$'), '');
    return hrefs
        .map((s) => s.replaceAll('&amp;', '&'))
        .map((s) => Uri.tryParse(s))
        .whereType<Uri>()
        .map((u) => Uri.decodeComponent(u.path))
        .where((p) => p.startsWith('$basePath/') && !p.endsWith('/'))
        .map((p) => p.substring(basePath.length + 1))
        .where((p) => !p.contains('/'))
        .toList();
  }

  void close() => _http.close(force: true);

  static void _check(HttpClientResponse response, String action) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        '$action 失败：HTTP ${response.statusCode}',
        uri: response.redirects.isEmpty
            ? null
            : response.redirects.last.location,
      );
    }
  }
}
