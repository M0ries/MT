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
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  static Uri _validateBase(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('请输入完整的 WebDAV http(s) 地址');
    }
    return uri.replace(path: uri.path.endsWith('/') ? uri.path : '${uri.path}/');
  }

  Uri url(String path) {
    final safe = path.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    return _base.resolve(path.endsWith('/') ? '$safe/' : safe);
  }

  Future<HttpClientResponse> _request(String method, String path, {String? body, Map<String, String> headers = const {}}) async {
    final request = await _http.openUrl(method, url(path)).timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('${_credentials.username}:${_credentials.password}'))}');
    request.headers.set(HttpHeaders.userAgentHeader, 'MT-MemoryTaker/1.0 (Flutter; contact via GitHub)');
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
    final response = await _request('GET', path);
    if (response.statusCode == 404) {
      await response.drain<void>();
      return null;
    }
    _check(response, '读取 $path');
    return utf8.decode(await response.fold<List<int>>([], (a, b) => a..addAll(b)));
  }

  Future<void> write(String path, String body) async {
    final response = await _request('PUT', path,
        body: body, headers: {HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8'});
    _check(response, '写入 $path');
    await response.drain<void>();
  }

  Future<void> ensureDirectory(String path) async {
    var current = '';
    for (final segment in path.split('/').where((s) => s.isNotEmpty)) {
      current = '$current$segment/';
      final response = await _request('MKCOL', current);
      if (![200, 201, 204, 301, 405].contains(response.statusCode)) {
        _check(response, '创建 $current');
      }
      await response.drain<void>();
    }
  }

  Future<List<String>> listFiles(String path) async {
    final response = await _request('PROPFIND', path,
        body: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>',
        headers: {'Depth': '1', HttpHeaders.contentTypeHeader: 'application/xml; charset=utf-8'});
    _check(response, '列出 $path');
    final xml = await utf8.decodeStream(response);
    final hrefs = RegExp(r'<(?:[\w.-]+:)?href[^>]*>([^<]+)</(?:[\w.-]+:)?href>', caseSensitive: false)
        .allMatches(xml).map((m) => m.group(1)!).toList();
    final basePath = url(path).path.replaceAll(RegExp(r'/$'), '');
    return hrefs.map((s) => s.replaceAll('&amp;', '&'))
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
      throw HttpException('$action 失败：HTTP ${response.statusCode}', uri: response.redirects.isEmpty ? null : response.redirects.last.location);
    }
  }
}
