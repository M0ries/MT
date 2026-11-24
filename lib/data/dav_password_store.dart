import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps WebDAV passwords on this device, outside the journal and preferences.
class DavPasswordStore {
  DavPasswordStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          (Platform.isMacOS
              ? const FlutterSecureStorage(
                  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
                )
              : const FlutterSecureStorage());

  final FlutterSecureStorage _storage;

  String _key(String account) => 'webdav.$account.password';

  Future<String> read(String account) async =>
      await _storage.read(key: _key(account)) ?? '';

  Future<void> write(String account, String password) async {
    if (password.isEmpty) {
      await _storage.delete(key: _key(account));
    } else {
      await _storage.write(key: _key(account), value: password);
    }
  }
}
