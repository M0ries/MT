import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memory_taker/data/update_service.dart';

void main() {
  test('release assets use versioned MRecorder installer names', () {
    const digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final release = UpdateRelease(
      version: '1.3.2',
      tag: 'v1.3.2',
      notes: '',
      page: Uri.parse('https://github.com/M0ries/MRecorder/releases/tag/v1.3.2'),
      assets: const [
        ReleaseAsset(
          id: 1,
          name: 'MR_macos_1.3.2.dmg',
          size: 1,
          sha256: digest,
        ),
        ReleaseAsset(
          id: 2,
          name: 'MR_windows_1.3.2.exe',
          size: 1,
          sha256: digest,
        ),
      ],
    );
    expect(release.assetForPlatform('macos')?.id, 1);
    expect(release.assetForPlatform('windows')?.id, 2);
    expect(release.assetForPlatform('ios'), isNull);
  });

  test('version comparison uses numbers, not text order', () {
    expect(UpdateService.isNewer('1.0.9', 'v1.0.10'), true);
    expect(UpdateService.isNewer('1.1.0', 'v1.0.99'), false);
    expect(UpdateService.isNewer('1.0.3+4', 'v1.0.3'), false);
  });

  test('private release check and verified installer download', () async {
    final bytes = utf8.encode('test installer contents');
    final digest = sha256.convert(bytes).toString();
    var assetRequests = 0;
    var leakedToken = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path.endsWith('/releases/latest')) {
        if (request.headers.value(HttpHeaders.authorizationHeader) !=
            'Bearer read-token') {
          request.response.statusCode = 404;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'tag_name': 'v1.0.4',
              'body': '更新说明',
              'assets': [
                {
                  'id': 42,
                  'name': 'MR_windows_1.0.4.exe',
                  'size': bytes.length,
                  'digest': 'sha256:$digest',
                },
              ],
            }),
          );
        }
      } else if (path.endsWith('/releases/assets/42')) {
        assetRequests++;
        if (request.headers.value(HttpHeaders.authorizationHeader) !=
            'Bearer read-token') {
          request.response.statusCode = 401;
        } else {
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader, '/payload');
        }
      } else if (path == '/payload') {
        leakedToken =
            request.headers.value(HttpHeaders.authorizationHeader) != null;
        request.response.add(bytes);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp('mt-update-test-');
    final service = UpdateService(
      apiBase: Uri.parse(
        'http://127.0.0.1:${server.port}/repos/M0ries/MRecorder',
      ),
    );
    try {
      await expectLater(
        service.checkLatest(currentVersion: '1.0.3'),
        throwsA(isA<UpdateAccessException>()),
      );
      final release = await service.checkLatest(
        currentVersion: '1.0.3',
        token: 'read-token',
      );
      expect(release?.version, '1.0.4');
      expect(release?.assetForPlatform('ios'), isNull);
      final asset = release!.assetForPlatform('windows')!;
      final file = await service.downloadAsset(
        release,
        asset,
        token: 'read-token',
        directory: directory,
        platform: 'windows',
      );
      expect(await file.readAsBytes(), bytes);
      expect(leakedToken, false);
      await service.downloadAsset(
        release,
        asset,
        token: 'read-token',
        directory: directory,
        platform: 'windows',
      );
      expect(assetRequests, 1);
      expect(
        await service.checkLatest(currentVersion: '1.0.4', token: 'read-token'),
        isNull,
      );
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });
}
