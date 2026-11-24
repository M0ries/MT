import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memory_taker/data/dav_password_store.dart';
import 'package:memory_taker/data/journal_store.dart';
import 'package:memory_taker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'WebDAV passwords persist across store instances and stay separate',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final first = DavPasswordStore();
      await first.write('mt', 'mt-secret');
      await first.write('kazumi', 'kazumi-secret');
      await first.writeUpdateToken('read-only-token');

      final reopened = DavPasswordStore();
      expect(await reopened.read('mt'), 'mt-secret');
      expect(await reopened.read('kazumi'), 'kazumi-secret');
      expect(await reopened.readUpdateToken(), 'read-only-token');

      await reopened.write('mt', '');
      expect(await first.read('mt'), isEmpty);
      expect(await first.read('kazumi'), 'kazumi-secret');
      await reopened.writeUpdateToken('');
      expect(await first.readUpdateToken(), isEmpty);
    },
  );

  testWidgets('theme color changes immediately and survives reopening', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'updates.autoCheck': 'false'});
    FlutterSecureStorage.setMockInitialValues({});
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('mt-theme-test-'),
    );
    if (directory == null) throw StateError('Unable to create test directory');
    addTearDown(() => directory.delete(recursive: true));
    final store = await tester.runAsync(
      () => JournalStore.open(directory: directory),
    );
    if (store == null) throw StateError('Unable to open journal store');

    await tester.pumpWidget(
      MemoryTaker(
        store: store,
        passwords: DavPasswordStore(),
        mtPassword: '',
        kazumiPassword: '',
        updateToken: '',
        currentVersion: '1.0.3',
      ),
    );
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('应用更新'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    final before = Theme.of(tester.element(find.text('主题颜色')))
        .colorScheme
        .primary;
    await tester.tap(find.widgetWithText(ChoiceChip, '青绿'));
    await tester.pumpAndSettle();

    expect(store.getString('appearance.accent'), 'teal');
    final color = Theme.of(tester.element(find.text('主题颜色')))
        .colorScheme
        .primary;
    expect(color, isNot(equals(before)));

    final reopened = await tester.runAsync(
      () => JournalStore.open(directory: directory),
    );
    if (reopened == null) throw StateError('Unable to reopen journal store');
    expect(reopened.getString('appearance.accent'), 'teal');
  });
}
