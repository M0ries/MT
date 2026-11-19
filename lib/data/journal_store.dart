import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../model/watch_entry.dart';

class JournalStore extends ChangeNotifier {
  JournalStore(this._prefs, this._file);
  final SharedPreferences _prefs;
  final File _file;
  final Map<String, WatchEntry> _entries = {};

  static Future<JournalStore> open({Directory? directory}) async {
    final base = directory ?? await getApplicationSupportDirectory();
    await base.create(recursive: true);
    final store = JournalStore(await SharedPreferences.getInstance(),
      File('${base.path}${Platform.pathSeparator}mt_records_v1.json'));
    String? raw;
    if (await store._file.exists()) {
      raw = await store._file.readAsString();
    } else {
      raw = store._prefs.getString('mt.entries.v1');
    }
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        for (final value in data['entries'] as List? ?? const []) {
          final entry = WatchEntry.fromJson(Map<String, dynamic>.from(value as Map));
          store._entries[entry.id] = entry;
        }
      } catch (_) {
        final backup = File('${store._file.path}.bak');
        if (await backup.exists()) {
          final recovered = await backup.readAsString();
          final data = jsonDecode(recovered) as Map<String, dynamic>;
          for (final value in data['entries'] as List? ?? const []) {
            final entry = WatchEntry.fromJson(Map<String, dynamic>.from(value as Map));
            store._entries[entry.id] = entry;
          }
          await store._file.writeAsString(recovered, flush: true);
        } else {
          rethrow;
        }
      }
    }
    return store;
  }

  List<WatchEntry> get entries => _entries.values.where((e) => !e.deleted).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<WatchEntry> get allEntries => _entries.values.toList();
  WatchEntry? byId(String id) => _entries[id];
  WatchEntry? byBangumiId(int id, {bool includeDeleted = false}) {
    for (final item in _entries.values) {
      if ((includeDeleted || !item.deleted) && item.bangumiId == id) return item;
    }
    return null;
  }

  Future<void> put(WatchEntry entry) async {
    _entries[entry.id] = entry;
    await _save();
  }

  Future<void> putAll(Iterable<WatchEntry> entries) async {
    for (final entry in entries) {
      _entries[entry.id] = entry;
    }
    await _save();
  }

  Future<void> remove(String id) async {
    final entry = _entries[id];
    if (entry == null) return;
    _entries[id] = entry.copyWith(deleted: true);
    await _save();
  }

  Future<void> _save() async {
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(encodeEntries(_entries.values), flush: true);
    if (await _file.exists()) {
      await _file.copy('${_file.path}.bak');
    }
    if (Platform.isWindows && await _file.exists()) {
      await _file.delete();
    }
    await temporary.rename(_file.path);
    notifyListeners();
  }

  String getString(String key) => _prefs.getString(key) ?? '';
  Future<void> setString(String key, String value) async {
    final ok = await _prefs.setString(key, value);
    if (!ok) throw StateError('Settings save failed');
    notifyListeners();
  }
}
