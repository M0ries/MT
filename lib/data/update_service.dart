import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

const mtReleasesUrl = 'https://github.com/M0ries/MT/releases';

class UpdateAccessException implements Exception {
  const UpdateAccessException();

  @override
  String toString() => '无法读取 Release。私有仓库请填写具有 Contents 读取权限的 GitHub 令牌。';
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.id,
    required this.name,
    required this.size,
    required this.sha256,
  });

  final int id;
  final String name;
  final int size;
  final String sha256;

  bool get canVerify =>
      size > 0 && RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256);
}

class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.tag,
    required this.notes,
    required this.page,
    required this.assets,
  });

  final String version;
  final String tag;
  final String notes;
  final Uri page;
  final List<ReleaseAsset> assets;

  ReleaseAsset? assetForPlatform(String platform) {
    final name = switch (platform) {
      'windows' => 'MT-Windows-Setup.exe',
      'macos' => 'MT-macOS.dmg',
      _ => null,
    };
    if (name == null) return null;
    for (final asset in assets) {
      if (asset.name == name && asset.canVerify) return asset;
    }
    return null;
  }
}

class UpdateService {
  UpdateService({Uri? apiBase})
    : apiBase = apiBase ?? Uri.https('api.github.com', '/repos/M0ries/MT');

  final Uri apiBase;

  static List<int> _versionParts(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$')
        .firstMatch(value.trim());
    if (match == null) throw FormatException('无法识别版本号：$value');
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  static bool isNewer(String current, String remote) {
    final a = _versionParts(current);
    final b = _versionParts(remote);
    for (var i = 0; i < 3; i++) {
      if (b[i] != a[i]) return b[i] > a[i];
    }
    return false;
  }

  Future<UpdateRelease?> checkLatest({
    required String currentVersion,
    String token = '',
  }) async {
    final uri = apiBase.replace(path: '${apiBase.path}/releases/latest');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.userAgentHeader, 'MT-MemoryTaker');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      if (token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode == 404 || response.statusCode == 401) {
        await response.drain<void>();
        throw const UpdateAccessException();
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('检查更新失败（HTTP ${response.statusCode}）');
      }
      final raw = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(raw);
      if (data is! Map) throw const FormatException('GitHub Release 响应无效');
      final tag = data['tag_name'];
      if (tag is! String ||
          !RegExp(r'^v?[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(tag)) {
        throw const FormatException('GitHub Release 版本号无效');
      }
      if (!isNewer(currentVersion, tag)) return null;
      final assets = <ReleaseAsset>[];
      for (final value in data['assets'] as List? ?? const []) {
        if (value is! Map) continue;
        final digest = value['digest'];
        final id = value['id'];
        final name = value['name'];
        final size = value['size'];
        if (id is int && name is String && size is int) {
          assets.add(
            ReleaseAsset(
              id: id,
              name: name,
              size: size,
              sha256: digest is String && digest.startsWith('sha256:')
                  ? digest.substring(7)
                  : '',
            ),
          );
        }
      }
      return UpdateRelease(
        version: tag.startsWith('v') ? tag.substring(1) : tag,
        tag: tag,
        notes: data['body'] is String ? data['body'] as String : '',
        page: Uri.https('github.com', '/M0ries/MT/releases/tag/$tag'),
        assets: assets,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<File> downloadAsset(
    UpdateRelease release,
    ReleaseAsset asset, {
    String token = '',
    Directory? directory,
    String? platform,
    void Function(int received, int total)? onProgress,
  }) async {
    if (!asset.canVerify || !release.assets.contains(asset)) {
      throw const FormatException('安装包缺少有效的 SHA-256 校验值');
    }
    final expectedName = release
        .assetForPlatform(platform ?? Platform.operatingSystem)
        ?.name;
    if (asset.name != expectedName) {
      throw const FormatException('此设备没有对应的安装包');
    }
    final base = directory ?? await getApplicationSupportDirectory();
    final destination = Directory(
      '${base.path}${Platform.pathSeparator}updates'
      '${Platform.pathSeparator}${release.version}',
    );
    await destination.create(recursive: true);
    final file = File(
      '${destination.path}${Platform.pathSeparator}${asset.name}',
    );
    if (await file.exists() && await _matches(file, asset)) {
      onProgress?.call(asset.size, asset.size);
      return file;
    }
    final partial = File('${file.path}.part');
    if (await partial.exists()) await partial.delete();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final assetUri = apiBase.replace(
        path: '${apiBase.path}/releases/assets/${asset.id}',
      );
      var uri = assetUri;
      HttpClientResponse? response;
      for (var hop = 0; hop < 5; hop++) {
        if (!_trustedDownloadUri(uri)) {
          throw const FormatException('安装包跳转地址不安全');
        }
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 20));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'MT-MemoryTaker');
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/octet-stream',
        );
        if (uri == assetUri && token.isNotEmpty) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        response = await request.close().timeout(const Duration(seconds: 20));
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null) throw const FormatException('安装包跳转缺少地址');
          uri = uri.resolve(location);
          continue;
        }
        break;
      }
      if (response == null || response.statusCode != 200) {
        throw HttpException('下载安装包失败（HTTP ${response?.statusCode ?? 0}）');
      }
      var received = 0;
      final sink = partial.openWrite();
      try {
        await for (final bytes in response) {
          sink.add(bytes);
          received += bytes.length;
          onProgress?.call(received, asset.size);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (!await _matches(partial, asset)) {
        throw const FormatException('安装包完整性校验失败，请重试');
      }
      if (await file.exists()) {
        await file.delete();
      }
      await partial.rename(file.path);
      return file;
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  bool _trustedDownloadUri(Uri uri) {
    if (uri.host == apiBase.host && uri.scheme == apiBase.scheme) return true;
    return uri.scheme == 'https' &&
        (uri.host == 'github.com' ||
            uri.host.endsWith('.githubusercontent.com'));
  }

  Future<bool> _matches(File file, ReleaseAsset asset) async {
    if (await file.length() != asset.size) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == asset.sha256.toLowerCase();
  }
}
