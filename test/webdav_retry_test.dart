import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memory_taker/data/webdav.dart';

void main() {
  test('retries an interrupted response body', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      if (requests == 1) {
        final socket = await request.response.detachSocket();
        socket.destroy();
      } else {
        request.response.write('recovered');
        await request.response.close();
      }
    });
    final client = WebDavClient(
      DavCredentials('http://127.0.0.1:${server.port}/dav/', 'user', 'pass'),
    );
    try {
      expect(await client.read('MT/records/item.json'), 'recovered');
      expect(requests, 2);
    } finally {
      client.close();
      await server.close(force: true);
    }
  });

  test('retries a connection closed before its response header', () async {
    var requests = 0;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) async {
      await socket.first;
      requests++;
      if (requests == 1) {
        socket.destroy();
      } else {
        socket.write(
          'HTTP/1.1 200 OK\r\n'
          'Content-Length: 9\r\n'
          'Connection: close\r\n\r\nrecovered',
        );
        await socket.flush();
        await socket.close();
      }
    });
    final client = WebDavClient(
      DavCredentials('http://127.0.0.1:${server.port}/dav/', 'user', 'pass'),
    );
    try {
      expect(await client.read('MT/records/item.json'), 'recovered');
      expect(requests, 2);
    } finally {
      client.close();
      await server.close();
    }
  });

  test('retries a temporary WebDAV server error', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      request.response.statusCode = requests == 1 ? 503 : 200;
      if (requests > 1) request.response.write('ok');
      await request.response.close();
    });
    final client = WebDavClient(
      DavCredentials('http://127.0.0.1:${server.port}/dav/', 'user', 'pass'),
    );
    try {
      expect(await client.read('MT/records/item.json'), 'ok');
      expect(requests, 2);
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
}
