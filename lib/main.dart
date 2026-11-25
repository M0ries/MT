import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/bangumi.dart';
import 'data/content_cache.dart';
import 'data/dav_password_store.dart';
import 'data/external_import.dart';
import 'data/journal_store.dart';
import 'data/kazumi_import.dart';
import 'data/mt_sync.dart';
import 'data/update_service.dart';
import 'data/webdav.dart';
import 'model/watch_entry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await JournalStore.open();
  final passwords = DavPasswordStore();
  final mtPassword = await passwords.read('mt');
  final kazumiPassword = await passwords.read('kazumi');
  final updateToken = await passwords.readUpdateToken();
  final currentVersion = (await PackageInfo.fromPlatform()).version;
  runApp(
    MemoryTaker(
      store: store,
      passwords: passwords,
      mtPassword: mtPassword,
      kazumiPassword: kazumiPassword,
      updateToken: updateToken,
      currentVersion: currentVersion,
    ),
  );
}

const _accentColors = <({String id, String name, Color color})>[
  (id: 'blue', name: '蓝色', color: Color(0xFF5065B8)),
  (id: 'teal', name: '青绿', color: Color(0xFF148B83)),
  (id: 'green', name: '绿色', color: Color(0xFF4E8061)),
  (id: 'orange', name: '橙色', color: Color(0xFFC66B39)),
  (id: 'pink', name: '粉色', color: Color(0xFFBA6287)),
  (id: 'purple', name: '紫色', color: Color(0xFF8464B2)),
];
Color _accentFor(String id) {
  for (final choice in _accentColors) {
    if (choice.id == id) return choice.color;
  }
  return _accentColors.first.color;
}

const _importFiles = XTypeGroup(
  label: 'JSON 历史文件',
  extensions: ['json', 'jsonl'],
  uniformTypeIdentifiers: ['public.json', 'public.plain-text'],
);

class MemoryTaker extends StatelessWidget {
  const MemoryTaker({
    super.key,
    required this.store,
    required this.passwords,
    required this.mtPassword,
    required this.kazumiPassword,
    required this.updateToken,
    required this.currentVersion,
  });
  final JournalStore store;
  final DavPasswordStore passwords;
  final String mtPassword;
  final String kazumiPassword;
  final String updateToken;
  final String currentVersion;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final accent = _accentFor(store.getString('appearance.accent'));
      final surface = Color.lerp(const Color(0xFFF7F8FC), accent, 0.045)!;
      return MaterialApp(
        title: 'MT · Memory Taker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: accent),
          scaffoldBackgroundColor: surface,
          appBarTheme: AppBarTheme(
            backgroundColor: surface,
            surfaceTintColor: Colors.transparent,
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        home: HomePage(
          store: store,
          passwords: passwords,
          initialMtPassword: mtPassword,
          initialKazumiPassword: kazumiPassword,
          initialUpdateToken: updateToken,
          currentVersion: currentVersion,
        ),
      );
    },
  );
}

String _statusName(WatchStatus status) => switch (status) {
  WatchStatus.planned => '想看',
  WatchStatus.watching => '在看',
  WatchStatus.completed => '看完',
  WatchStatus.paused => '搁置',
  WatchStatus.dropped => '弃坑',
};
String _kindName(WatchKind kind) => switch (kind) {
  WatchKind.anime => '动漫',
  WatchKind.movie => '电影',
  WatchKind.series => '剧集',
};
String _date(DateTime? value) => value == null
    ? '未设置'
    : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _duration(int? ms) {
  if (ms == null || ms <= 0) return '';
  final d = Duration(milliseconds: ms);
  return '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

enum LibrarySort { updated, firstWatch, finish, lastWatch, title }

String _sortName(LibrarySort sort) => switch (sort) {
  LibrarySort.updated => '最近修改',
  LibrarySort.firstWatch => '开始日期',
  LibrarySort.finish => '结束日期',
  LibrarySort.lastWatch => '最近观看',
  LibrarySort.title => '作品名称',
};

int _compareEntries(
  WatchEntry a,
  WatchEntry b,
  LibrarySort sort,
  bool descending,
) {
  if (sort == LibrarySort.title) {
    final result = a.title.compareTo(b.title);
    return result == 0
        ? a.id.compareTo(b.id)
        : descending
        ? -result
        : result;
  }
  DateTime? value(WatchEntry entry) => switch (sort) {
    LibrarySort.updated => entry.updatedAt,
    LibrarySort.firstWatch => entry.firstWatchDate,
    LibrarySort.finish =>
      entry.status == WatchStatus.dropped ? entry.dropDate : entry.finishDate,
    LibrarySort.lastWatch => entry.lastWatchAt,
    LibrarySort.title => null,
  };
  final first = value(a), second = value(b);
  if (first == null && second == null) return a.title.compareTo(b.title);
  if (first == null) return 1;
  if (second == null) return -1;
  final result = first.compareTo(second);
  return result == 0
      ? a.title.compareTo(b.title)
      : descending
      ? -result
      : result;
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    required this.passwords,
    required this.initialMtPassword,
    required this.initialKazumiPassword,
    required this.initialUpdateToken,
    required this.currentVersion,
  });
  final JournalStore store;
  final DavPasswordStore passwords;
  final String initialMtPassword;
  final String initialKazumiPassword;
  final String initialUpdateToken;
  final String currentVersion;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int page = 0;
  WatchStatus? filter;
  String query = '';
  LibrarySort sort = LibrarySort.updated;
  bool sortDescending = true;
  late String mtPassword;
  late String kazumiPassword;
  late String updateToken;
  UpdateRelease? availableUpdate;
  bool checkingUpdate = false;
  bool downloadingUpdate = false;
  int updateReceived = 0;
  int updateTotal = 0;
  final Map<String, Future<void>> _passwordWrites = {};
  final Map<String, String> _syncStatus = {};
  bool _autoSyncPending = false;
  bool _autoSyncRunning = false;
  bool busy = false;
  bool importing = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    mtPassword = widget.initialMtPassword;
    kazumiPassword = widget.initialKazumiPassword;
    updateToken = widget.initialUpdateToken;
    sort = LibrarySort.values.firstWhere(
      (value) => value.name == widget.store.getString('library.sort'),
      orElse: () => LibrarySort.updated,
    );
    sortDescending = widget.store.getString('library.descending') != 'false';
    widget.store.addListener(_refresh);
    timer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => unawaited(_backgroundSync()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_backgroundSync());
      if (mounted && widget.store.getString('updates.autoCheck') != 'false') {
        unawaited(_checkUpdate(automatic: true));
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _updatePassword(String account, String value) {
    setState(() {
      if (account == 'mt') {
        mtPassword = value;
      } else {
        kazumiPassword = value;
      }
    });
    _saveSecret(account, () => widget.passwords.write(account, value));
  }

  void _updateToken(String value) {
    setState(() => updateToken = value.trim());
    _saveSecret(
      'github',
      () => widget.passwords.writeUpdateToken(value.trim()),
    );
  }

  void _saveSecret(String key, Future<void> Function() write) {
    final previous = _passwordWrites[key] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => write());
    _passwordWrites[key] = next;
    unawaited(
      next.catchError((Object error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('凭据保存失败：$error')));
        }
      }),
    );
  }

  Future<void> _openReleasePage([Uri? page]) async {
    final url = page ?? Uri.parse(mtReleasesUrl);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('无法打开浏览器');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开 GitHub 失败：$error')));
      }
    }
  }

  Future<void> _checkUpdate({bool automatic = false}) async {
    if (checkingUpdate || downloadingUpdate) return;
    setState(() => checkingUpdate = true);
    try {
      final release = await UpdateService().checkLatest(
        currentVersion: widget.currentVersion,
        token: updateToken,
      );
      if (!mounted) return;
      setState(() => availableUpdate = release);
      if (release == null) {
        if (!automatic) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('当前已经是最新版本')));
        }
      } else {
        await _showUpdateDialog(release);
      }
    } catch (error) {
      if (mounted && !automatic) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => checkingUpdate = false);
    }
  }

  Future<void> _showUpdateDialog(UpdateRelease release) async {
    final asset = release.assetForPlatform(Platform.operatingSystem);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('发现新版本 v${release.version}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本 v${widget.currentVersion}'),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 190),
                child: SingleChildScrollView(
                  child: SelectableText(
                    release.notes.isEmpty ? '查看 GitHub 获取更新说明。' : release.notes,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'github'),
            child: const Text('在 GitHub 查看'),
          ),
          if (asset != null)
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'download'),
              icon: const Icon(Icons.download_outlined),
              label: const Text('下载并打开安装包'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'github') await _openReleasePage(release.page);
    if (action == 'download' && asset != null) {
      await _downloadAndOpen(release, asset);
    }
  }

  Future<void> _downloadAndOpen(
    UpdateRelease release,
    ReleaseAsset asset,
  ) async {
    if (downloadingUpdate) return;
    setState(() {
      downloadingUpdate = true;
      updateReceived = 0;
      updateTotal = asset.size;
    });
    try {
      final file = await UpdateService().downloadAsset(
        release,
        asset,
        token: updateToken,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              updateReceived = received;
              updateTotal = total;
            });
          }
        },
      );
      if (!mounted) return;
      if (!await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('无法打开安装包');
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已打开安装包，请按系统提示完成更新')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('更新失败：$error')));
      }
    } finally {
      if (mounted) setState(() => downloadingUpdate = false);
    }
  }

  DavCredentials _credentials(String prefix, String password) => DavCredentials(
    widget.store.getString('$prefix.url'),
    widget.store.getString('$prefix.user'),
    password,
  );

  Future<void> _backgroundSync() async {
    _autoSyncPending = true;
    if (_autoSyncRunning || busy) return;
    _autoSyncRunning = true;
    try {
      while (_autoSyncPending && mounted && !busy) {
        _autoSyncPending = false;
        await _syncOnce();
      }
    } finally {
      _autoSyncRunning = false;
      if (_autoSyncPending && mounted && !busy) {
        unawaited(_backgroundSync());
      }
    }
  }

  Future<void> _syncOnce() async {
    if (widget.store.getString('kazumi.url').isNotEmpty &&
        widget.store.getString('kazumi.autoSync') != 'false') {
      await _run(
        () => const KazumiImportService().import(
          widget.store,
          _credentials('kazumi', kazumiPassword),
          onProgress: (phase, done, total) {
            if (mounted) {
              setState(
                () => _syncStatus['kazumi'] = total > 0
                    ? '$phase $done/$total'
                    : phase,
              );
            }
          },
        ),
        quiet: true,
        syncKey: 'kazumi',
      );
    }
    if (busy) {
      _autoSyncPending = true;
      return;
    }
    if (widget.store.getString('mt.url').isNotEmpty &&
        widget.store.getString('mt.autoSync') != 'false') {
      await _run(
        () => const MtSyncService().sync(
          widget.store,
          _credentials('mt', mtPassword),
          onProgress: (phase, done, total) {
            if (mounted) {
              setState(
                () => _syncStatus['mt'] = total > 0
                    ? '$phase $done/$total'
                    : phase,
              );
            }
          },
        ),
        quiet: true,
        syncKey: 'mt',
      );
    }
  }

  Future<T?> _run<T>(
    Future<T> Function() task, {
    bool quiet = false,
    String? syncKey,
  }) async {
    if (busy) return null;
    setState(() => busy = true);
    try {
      final result = await task();
      if (mounted && syncKey != null) {
        setState(
          () => _syncStatus[syncKey] = result is MtSyncResult
              ? '同步成功：下载 ${result.downloaded} 条，上传 ${result.uploaded} 条'
              : '导入成功：$result 条记录',
        );
      }
      if (mounted && !quiet) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result is MtSyncResult
                  ? '同步完成：下载 ${result.downloaded} 条，上传 ${result.uploaded} 条'
                  : '已导入 $result 条记录',
            ),
          ),
        );
      }
      return result;
    } catch (e) {
      if (mounted && syncKey != null) {
        setState(() => _syncStatus[syncKey] = '失败：$e');
      }
      if (mounted && !quiet) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (_autoSyncPending && !_autoSyncRunning) {
          unawaited(_backgroundSync());
        }
      }
    }
  }

  Future<void> _edit([WatchEntry? entry]) async {
    final result = await Navigator.push<WatchEntry>(
      context,
      MaterialPageRoute(builder: (_) => EntryEditor(entry: entry)),
    );
    if (result != null) {
      await _applyEntry(result, original: entry);
    }
  }

  Future<void> _applyEntry(WatchEntry result, {WatchEntry? original}) async {
    await widget.store.put(result);
    if (result.deleted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除「${result.title}」'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              if (original == null) return;
              await widget.store.put(original.copyWith(deleted: false));
              unawaited(_backgroundSync());
            },
          ),
        ),
      );
    }
    await _backgroundSync();
  }

  Future<void> _deleteEntry(WatchEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text('「${entry.title}」的删除会同步到其他 MT 设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _applyEntry(entry.copyWith(deleted: true), original: entry);
    }
  }

  Future<void> _exportRecords() async {
    final records = widget.store.entries;
    final today = DateTime.now();
    final name =
        'MT-backup-${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}-${records.length}.json';
    try {
      final contents = encodeEntries(records);
      if (Platform.isIOS) {
        final directory = await getApplicationDocumentsDirectory();
        final destination = '${directory.path}${Platform.pathSeparator}$name';
        await File(destination).writeAsString(contents, flush: true);
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [_importFiles],
        );
        if (location == null) return;
        await XFile.fromData(
          Uint8List.fromList(utf8.encode(contents)),
          mimeType: 'application/json',
          name: name,
        ).saveTo(location.path);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Platform.isIOS
                  ? '已导出 ${records.length} 条记录，可在“文件 → 我的 iPhone/iPad → MT”找到'
                  : '已导出 ${records.length} 条记录',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    }
  }

  Future<void> _clearContentCache() async {
    try {
      await ContentCache.instance.clear();
      imageCache.clear();
      imageCache.clearLiveImages();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清除封面与 Bangumi 内容缓存，追番记录仍保留')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('清除缓存失败：$error')));
      }
    }
  }

  Future<void> _importMtFile() async {
    if (importing) return;
    setState(() => importing = true);
    try {
      final file = await openFile(acceptedTypeGroups: const [_importFiles]);
      if (file == null) return;
      await _runLocalImport(
        () async => const ExternalImportService().importMtJson(
          widget.store,
          await file.readAsString(),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开文件：$e')));
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _importKazumiFiles() async {
    if (importing) return;
    setState(() => importing = true);
    try {
      final files = await openFiles(acceptedTypeGroups: const [_importFiles]);
      if (files.isEmpty) return;
      await _runLocalImport(() async {
        String? snapshot;
        final changes = <String>[];
        for (final file in files) {
          final name = file.name.toLowerCase();
          final content = await file.readAsString();
          if (name.endsWith('.jsonl')) {
            changes.add(content);
          } else if (name.endsWith('.json')) {
            if (snapshot != null) {
              throw const FormatException('一次只能选择一个 Kazumi snapshot.json');
            }
            snapshot = content;
          } else {
            throw const FormatException('请选择 JSON 或 JSONL 历史文件');
          }
        }
        return const KazumiImportService().importLocal(
          widget.store,
          snapshot: snapshot,
          changeLogs: changes,
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开文件：$e')));
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _runLocalImport(Future<int> Function() task) async {
    try {
      final count = await task();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导入 $count 条记录')));
        unawaited(_backgroundSync());
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
    }
  }

  Future<void> _add() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('从 Bangumi 搜索'),
                subtitle: const Text('带入封面和简介'),
                onTap: () => Navigator.pop(context, 'search'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('手动添加'),
                onTap: () => Navigator.pop(context, 'manual'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'manual') await _edit();
    if (choice == 'search') {
      if (!mounted) return;
      final subject = await Navigator.push<BangumiSubject>(
        context,
        MaterialPageRoute(builder: (_) => const BangumiSearchPage()),
      );
      if (subject == null || !mounted) return;
      final existing = widget.store.byBangumiId(subject.id);
      if (existing != null) {
        await _edit(existing);
      } else {
        await _edit(
          WatchEntry(
            id: 'b${subject.id}',
            bangumiId: subject.id,
            title: subject.title,
            originalTitle: subject.originalTitle,
            summary: subject.summary,
            coverUrl: subject.coverUrl,
            kind: subject.type == 6 ? WatchKind.series : WatchKind.anime,
            status: WatchStatus.planned,
            episodeCount: subject.episodeCount,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = page == 0 ? _library() : _settings();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MT  ·  Memory Taker',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (busy)
            const Padding(
              padding: EdgeInsets.only(right: 20),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: page,
              onDestinationSelected: (v) => setState(() => page = v),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.collections_bookmark_outlined),
                  selectedIcon: Icon(Icons.collections_bookmark),
                  label: Text('记录'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('设置'),
                ),
              ],
            ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (v) => setState(() => page = v),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.collections_bookmark_outlined),
                  label: '记录',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: '设置',
                ),
              ],
            ),
      floatingActionButton: page == 0
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('添加作品'),
            )
          : null,
    );
  }

  Widget _library() {
    final entries = widget.store.entries
        .where(
          (e) =>
              (filter == null || e.status == filter) &&
              (query.isEmpty ||
                  '${e.title} ${e.originalTitle} ${e.notes}'
                      .toLowerCase()
                      .contains(query.toLowerCase())),
        )
        .toList();
    entries.sort((a, b) => _compareEntries(a, b, sort, sortDescending));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.store.entries.length} 部作品',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  PopupMenuButton<LibrarySort>(
                    tooltip: '按时间排序',
                    icon: const Icon(Icons.sort),
                    initialValue: sort,
                    onSelected: (value) {
                      setState(() => sort = value);
                      unawaited(
                        widget.store.setString('library.sort', value.name),
                      );
                    },
                    itemBuilder: (_) => [
                      for (final value in LibrarySort.values)
                        PopupMenuItem(
                          value: value,
                          child: Text(_sortName(value)),
                        ),
                    ],
                  ),
                  IconButton(
                    tooltip: sortDescending ? '当前：从新到旧，点击反转' : '当前：从旧到新，点击反转',
                    icon: Icon(
                      sortDescending
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                    ),
                    onPressed: () {
                      setState(() => sortDescending = !sortDescending);
                      unawaited(
                        widget.store.setString(
                          'library.descending',
                          sortDescending.toString(),
                        ),
                      );
                    },
                  ),
                  if (widget.store.getString('mt.url').isNotEmpty)
                    IconButton(
                      tooltip: '同步 MT',
                      icon: const Icon(Icons.sync),
                      onPressed: busy
                          ? null
                          : () => unawaited(
                              _run(
                                () => const MtSyncService().sync(
                                  widget.store,
                                  _credentials('mt', mtPassword),
                                  onProgress: (phase, done, total) {
                                    if (mounted) {
                                      setState(
                                        () => _syncStatus['mt'] = total > 0
                                            ? '$phase $done/$total'
                                            : phase,
                                      );
                                    }
                                  },
                                ),
                                syncKey: 'mt',
                              ),
                            ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索我的记录',
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _filterChip('全部', null),
                  for (final status in WatchStatus.values)
                    _filterChip(_statusName(status), status),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? _empty()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 920
                            ? 3
                            : constraints.maxWidth >= 610
                            ? 2
                            : 1;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisExtent: 146,
                                crossAxisSpacing: 4,
                                mainAxisSpacing: 4,
                              ),
                          itemCount: entries.length,
                          itemBuilder: (_, i) => _entryCard(entries[i]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, WatchStatus? value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: filter == value,
      onSelected: (_) => setState(() => filter = value),
    ),
  );

  Widget _empty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.movie_filter_outlined,
          size: 54,
          color: Colors.blueGrey.shade300,
        ),
        const SizedBox(height: 12),
        Text(
          query.isEmpty && filter == null ? '还没有记录' : '没有匹配的记录',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        if (query.isEmpty && filter == null)
          const Text('从 Bangumi 搜索，或手动添加一部作品'),
      ],
    ),
  );

  Widget _entryCard(WatchEntry item) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _edit(item),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Poster(url: item.coverUrl, width: 82, height: 118),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (item.favorite)
                        const Icon(
                          Icons.favorite,
                          color: Color(0xFFE57373),
                          size: 19,
                        ),
                      PopupMenuButton<String>(
                        tooltip: '记录操作',
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_vert, size: 19),
                        onSelected: (value) {
                          if (value == 'delete') unawaited(_deleteEntry(item));
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'delete', child: Text('删除记录')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_kindName(item.kind)}${item.isOva ? ' · OVA' : ''} · ${_statusName(item.status)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  if (item.status == WatchStatus.watching &&
                      item.episode != null)
                    Text(
                      '看到第 ${item.episode} 集${item.episodeCount == null ? '' : ' / ${item.episodeCount} 集'}${_duration(item.progressMs).isEmpty ? '' : ' · ${_duration(item.progressMs)}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  if (item.status == WatchStatus.completed ||
                      item.status == WatchStatus.dropped) ...[
                    Text(
                      '开始：${_date(item.firstWatchDate)}',
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${item.status == WatchStatus.completed ? '结束' : '弃坑'}：${_date(item.status == WatchStatus.completed ? item.finishDate : item.dropDate)}',
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (item.status == WatchStatus.paused)
                    Text(
                      '开始：${_date(item.firstWatchDate)}',
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  if (item.rating != null)
                    Text(
                      '我的评分  ${item.rating!.toStringAsFixed(1)} / 10',
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _settings() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            '外观与个性化',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '主题颜色',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text('选择喜欢的颜色，界面会立即更新并在下次打开时保留。'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final choice in _accentColors)
                        ChoiceChip(
                          avatar: CircleAvatar(
                            radius: 9,
                            backgroundColor: choice.color,
                          ),
                          label: Text(choice.name),
                          selected:
                              _accentFor(
                                widget.store.getString('appearance.accent'),
                              ) ==
                              choice.color,
                          onSelected: (_) => widget.store.setString(
                            'appearance.accent',
                            choice.id,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '应用更新',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _updatePanel(),
          const SizedBox(height: 24),
          Text(
            '数据与同步',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'MT 的 WebDAV 数据保存在 MT/records/；Kazumi 数据只读。WebDAV 密码保存在本机系统安全存储中，退出后仍会保留。建议使用 HTTPS。',
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '外部导入',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text('从本机或“文件”应用选择备份；已有的较新 MT 记录会保留。'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: importing ? null : _importMtFile,
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('导入 MT JSON'),
                      ),
                      OutlinedButton.icon(
                        onPressed: importing ? null : _importKazumiFiles,
                        icon: const Icon(Icons.history_outlined),
                        label: const Text('导入 Kazumi 文件'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportRecords,
                        icon: const Icon(Icons.ios_share_outlined),
                        label: const Text('导出 MT JSON'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Kazumi 可选择一个 snapshot.json，并同时选择多个 changes/*.jsonl。旧版 histories.tmp 暂不支持。',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('清除内容缓存'),
              subtitle: const Text('删除本机封面和 Bangumi 搜索缓存；追番记录不会删除'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _clearContentCache,
            ),
          ),
          const SizedBox(height: 16),
          _davPanel(
            'MT 多端同步',
            'mt',
            mtPassword,
            (v) => _updatePassword('mt', v),
            () => _run(
              () => const MtSyncService().sync(
                widget.store,
                _credentials('mt', mtPassword),
                onProgress: (phase, done, total) {
                  if (mounted) {
                    setState(
                      () => _syncStatus['mt'] = total > 0
                          ? '$phase $done/$total'
                          : phase,
                    );
                  }
                },
              ),
              syncKey: 'mt',
            ),
          ),
          const SizedBox(height: 16),
          _davPanel(
            '从 Kazumi 导入',
            'kazumi',
            kazumiPassword,
            (v) => _updatePassword('kazumi', v),
            () => _run(
              () => const KazumiImportService().import(
                widget.store,
                _credentials('kazumi', kazumiPassword),
                onProgress: (phase, done, total) {
                  if (mounted) {
                    setState(
                      () => _syncStatus['kazumi'] = total > 0
                          ? '$phase $done/$total'
                          : phase,
                    );
                  }
                },
              ),
              syncKey: 'kazumi',
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '启用自动同步后，MT 每 10 分钟检查一次对应的 WebDAV 数据。'
                '首次连接请先执行一次导入或同步。Kazumi 的旧版 Hive 二进制备份暂不支持直接读取。',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _updatePanel() {
    final release = availableUpdate;
    final asset = release?.assetForPlatform(Platform.operatingSystem);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本 v${widget.currentVersion}',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              '发现新版本后，桌面端可在应用内下载并打开安装包；iPhone/iPad 前往 GitHub 下载并自行签名安装。',
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('启动时检查更新'),
              value: widget.store.getString('updates.autoCheck') != 'false',
              onChanged: (value) =>
                  widget.store.setString('updates.autoCheck', value.toString()),
            ),
            const SizedBox(height: 6),
            TextFormField(
              initialValue: updateToken,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: _updateToken,
              decoration: const InputDecoration(
                labelText: 'GitHub 访问令牌（私有仓库需要）',
              ),
            ),
            const SizedBox(height: 6),
            const Text('只需此仓库的 Contents 读取权限；令牌保存在本机系统安全存储中。公开仓库可留空。'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: checkingUpdate || downloadingUpdate
                      ? null
                      : () => _checkUpdate(),
                  icon: const Icon(Icons.system_update_outlined),
                  label: Text(checkingUpdate ? '正在检查…' : '检查更新'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openReleasePage(),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开 GitHub Releases'),
                ),
                if (release != null && asset != null)
                  OutlinedButton.icon(
                    onPressed: downloadingUpdate
                        ? null
                        : () => _downloadAndOpen(release, asset),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('下载并打开安装包'),
                  ),
              ],
            ),
            if (release != null) ...[
              const SizedBox(height: 12),
              Text('可更新至 v${release.version}'),
            ],
            if (downloadingUpdate) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: updateTotal > 0
                    ? (updateReceived / updateTotal).clamp(0.0, 1.0)
                    : null,
              ),
              const SizedBox(height: 4),
              Text('正在下载：${(updateReceived / 1048576).toStringAsFixed(1)} MB'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _davPanel(
    String title,
    String prefix,
    String password,
    ValueChanged<String> onPassword,
    VoidCallback onAction,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(prefix == 'mt' ? '自动同步 MT' : '自动导入 Kazumi'),
              subtitle: const Text('关闭后仍可使用下方按钮手动操作'),
              value: widget.store.getString('$prefix.autoSync') != 'false',
              onChanged: (value) =>
                  widget.store.setString('$prefix.autoSync', value.toString()),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: widget.store.getString('$prefix.url'),
              decoration: const InputDecoration(
                labelText: 'WebDAV 地址',
                hintText: 'https://example.com/dav/',
              ),
              onChanged: (v) => widget.store.setString('$prefix.url', v.trim()),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: widget.store.getString('$prefix.user'),
              decoration: const InputDecoration(labelText: '用户名'),
              onChanged: (v) =>
                  widget.store.setString('$prefix.user', v.trim()),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: password,
              obscureText: true,
              onChanged: onPassword,
              decoration: const InputDecoration(labelText: '密码或应用专用密码（保存在本机）'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: busy ? null : onAction,
                icon: Icon(prefix == 'mt' ? Icons.sync : Icons.download),
                label: Text(prefix == 'mt' ? '立即同步' : '立即导入'),
              ),
            ),
            if (_syncStatus[prefix] case final status?) ...[
              const SizedBox(height: 8),
              Text(
                status,
                style: TextStyle(
                  color: status.startsWith('失败')
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class Poster extends StatelessWidget {
  const Poster({
    super.key,
    required this.url,
    required this.width,
    required this.height,
  });
  final String url;
  final double width, height;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(9),
    child: SizedBox(
      width: width,
      height: height,
      child: url.isEmpty
          ? ColoredBox(
              color: const Color(0xFFE7EBF5),
              child: Icon(
                Icons.movie_outlined,
                size: 32,
                color: Colors.blueGrey.shade300,
              ),
            )
          : FutureBuilder<File?>(
              future: ContentCache.instance.cover(url),
              builder: (context, snapshot) => snapshot.data == null
                  ? const ColoredBox(
                      color: Color(0xFFE7EBF5),
                      child: Icon(Icons.movie_outlined),
                    )
                  : Image.file(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFFE7EBF5),
                        child: Icon(Icons.movie_outlined),
                      ),
                    ),
            ),
    ),
  );
}

class BangumiSearchPage extends StatefulWidget {
  const BangumiSearchPage({super.key});
  @override
  State<BangumiSearchPage> createState() => _BangumiSearchPageState();
}

class _BangumiSearchPageState extends State<BangumiSearchPage> {
  final queryController = TextEditingController();
  List<BangumiSubject> results = [];
  bool loading = false;
  String? error;
  int generation = 0;

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  Future<void> search(String query) async {
    final current = ++generation;
    if (query.trim().isEmpty) {
      setState(() {
        results = [];
        error = null;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final found = await BangumiClient().search(query);
      if (mounted && current == generation) setState(() => results = found);
    } catch (e) {
      if (mounted && current == generation) setState(() => error = '$e');
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Future<void> select(BangumiSubject subject) async {
    setState(() => loading = true);
    try {
      final detail = await BangumiClient().detail(subject.id);
      if (mounted) Navigator.pop(context, detail);
    } catch (_) {
      if (mounted) Navigator.pop(context, subject);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('搜索 Bangumi')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                controller: queryController,
                onSubmitted: search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: '输入动画、电影或剧集名称',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => search(queryController.text),
                  ),
                ),
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final subject = results[i];
                  return ListTile(
                    leading: Poster(
                      url: subject.coverUrl,
                      width: 46,
                      height: 64,
                    ),
                    title: Text(subject.title),
                    subtitle: Text(
                      subject.originalTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => select(subject),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({super.key, this.entry});
  final WatchEntry? entry;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController notes;
  late final TextEditingController episode;
  late final TextEditingController episodeCount;
  late final TextEditingController cover;
  late final TextEditingController summary;
  late WatchKind kind;
  late WatchStatus status;
  late bool favorite;
  late bool episodeCountManual;
  bool? ovaOverride;
  bool refreshingEpisodeCount = false;
  double? rating;
  DateTime? first, finish, drop;
  late List<DateTime> rewatches;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    title = TextEditingController(text: e?.title ?? '');
    notes = TextEditingController(text: e?.notes ?? '');
    episode = TextEditingController(text: e?.episode?.toString() ?? '');
    episodeCount = TextEditingController(
      text: e?.episodeCount?.toString() ?? '',
    );
    cover = TextEditingController(text: e?.coverUrl ?? '');
    summary = TextEditingController(text: e?.summary ?? '');
    kind = e?.kind ?? WatchKind.anime;
    status = e?.status ?? WatchStatus.planned;
    favorite = e?.favorite ?? false;
    episodeCountManual = e?.episodeCountManual ?? false;
    ovaOverride = e?.ovaOverride;
    rating = e?.rating;
    first = e?.firstWatchDate;
    finish = e?.finishDate;
    drop = e?.dropDate;
    rewatches = [...?e?.rewatchDates];
    if (e?.bangumiId != null && !episodeCountManual) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshEpisodeCount());
      });
    }
  }

  Future<void> _refreshEpisodeCount({bool force = false}) async {
    final id = widget.entry?.bangumiId;
    if (id == null || refreshingEpisodeCount) return;
    setState(() => refreshingEpisodeCount = true);
    try {
      final subject = await BangumiClient().detail(id, refresh: force);
      if (mounted && subject.episodeCount > 0 && !episodeCountManual) {
        setState(() => episodeCount.text = subject.episodeCount.toString());
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Bangumi 集数更新失败：$error')));
      }
    } finally {
      if (mounted) setState(() => refreshingEpisodeCount = false);
    }
  }

  @override
  void dispose() {
    for (final c in [title, notes, episode, episodeCount, cover, summary]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> pick(DateTime? existing) => showDatePicker(
    context: context,
    initialDate: existing ?? DateTime.now(),
    firstDate: DateTime(1900),
    lastDate: DateTime(2100),
  );

  Widget dateField(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> change,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(_date(value)),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value != null)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '清除',
            onPressed: () => setState(() => change(null)),
          ),
        const Icon(Icons.calendar_month_outlined),
      ],
    ),
    onTap: () async {
      final next = await pick(value);
      if (next != null) setState(() => change(next));
    },
  );

  void save() {
    if (!formKey.currentState!.validate()) return;
    final old = widget.entry;
    Navigator.pop(
      context,
      WatchEntry(
        id: old?.id ?? newEntryId(),
        bangumiId: old?.bangumiId,
        title: title.text.trim(),
        originalTitle: old?.originalTitle ?? '',
        summary: summary.text.trim(),
        coverUrl: cover.text.trim(),
        kind: kind,
        status: status,
        firstWatchDate: first,
        finishDate: finish,
        dropDate: drop,
        rewatchDates: rewatches,
        rating: rating,
        favorite: favorite,
        notes: notes.text.trim(),
        episode: int.tryParse(episode.text),
        episodeCount: int.tryParse(episodeCount.text),
        episodeCountManual: old?.bangumiId == null || episodeCountManual,
        ovaOverride: ovaOverride,
        progressMs: old?.progressMs,
        lastWatchAt: old?.lastWatchAt,
        kazumiSource: old?.kazumiSource ?? '',
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.entry == null ? '添加记录' : '编辑记录'),
      actions: [
        if (widget.entry != null)
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('删除这条记录？'),
                  content: const Text('删除会同步到其他 MT 设备。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
              if (yes == true && context.mounted) {
                Navigator.pop(context, widget.entry!.copyWith(deleted: true));
              }
            },
          ),
        TextButton(onPressed: save, child: const Text('保存')),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
            children: [
              if (widget.entry?.coverUrl.isNotEmpty == true)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Poster(
                    url: widget.entry!.coverUrl,
                    width: 96,
                    height: 132,
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: title,
                decoration: const InputDecoration(labelText: '作品名称 *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入名称' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<WatchKind>(
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: '类型'),
                      items: WatchKind.values
                          .map(
                            (k) => DropdownMenuItem(
                              value: k,
                              child: Text(_kindName(k)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => kind = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<WatchStatus>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: '状态'),
                      items: WatchStatus.values
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(_statusName(s)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => status = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: ovaOverride == null
                    ? 'auto'
                    : ovaOverride!
                    ? 'yes'
                    : 'no',
                decoration: const InputDecoration(labelText: 'OVA 标签'),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('自动识别标题')),
                  DropdownMenuItem(value: 'yes', child: Text('标记为 OVA')),
                  DropdownMenuItem(value: 'no', child: Text('不显示 OVA')),
                ],
                onChanged: (value) => setState(
                  () => ovaOverride = switch (value) {
                    'yes' => true,
                    'no' => false,
                    _ => null,
                  },
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: favorite,
                title: const Text('收藏'),
                onChanged: (v) => setState(() => favorite = v),
              ),
              const Divider(),
              dateField('首看日期', first, (v) => first = v),
              dateField('看完日期', finish, (v) => finish = v),
              dateField('弃坑日期', drop, (v) => drop = v),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text('二刷 / 重看日期', style: TextStyle(fontSize: 16)),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final date = await pick(null);
                      if (date != null) setState(() => rewatches.add(date));
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('添加'),
                  ),
                ],
              ),
              for (var i = 0; i < rewatches.length; i++)
                ListTile(
                  title: Text(_date(rewatches[i])),
                  contentPadding: EdgeInsets.zero,
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => rewatches.removeAt(i)),
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: episode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: '看到第几集'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: episodeCount,
                      onChanged: (_) =>
                          setState(() => episodeCountManual = true),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: '总集数'),
                    ),
                  ),
                ],
              ),
              if (widget.entry?.bangumiId != null)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('从 Bangumi 同步总集数'),
                  subtitle: Text(
                    episodeCountManual
                        ? '已使用自定义集数'
                        : refreshingEpisodeCount
                        ? '正在更新集数…'
                        : '可随时改为自定义',
                  ),
                  value: !episodeCountManual,
                  onChanged: (value) {
                    setState(() => episodeCountManual = !value);
                    if (value) unawaited(_refreshEpisodeCount(force: true));
                  },
                ),
              if (widget.entry?.bangumiId != null && !episodeCountManual)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: refreshingEpisodeCount
                        ? null
                        : () => _refreshEpisodeCount(force: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新 Bangumi 集数'),
                  ),
                ),
              if (widget.entry?.progressMs != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Kazumi 播放位置：${_duration(widget.entry!.progressMs)}',
                    style: TextStyle(color: Colors.blueGrey.shade600),
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text('我的评分'),
                  const Spacer(),
                  Text(
                    rating == null
                        ? '未评分'
                        : '${rating!.toStringAsFixed(1)} / 10',
                  ),
                ],
              ),
              Slider(
                value: rating ?? 0,
                min: 0,
                max: 10,
                divisions: 20,
                label: rating?.toStringAsFixed(1),
                onChanged: (v) => setState(() => rating = v),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => rating = null),
                  child: const Text('清除评分'),
                ),
              ),
              TextFormField(
                controller: notes,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '评价 / 笔记',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: summary,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '简介',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: cover,
                decoration: const InputDecoration(labelText: '封面图片链接'),
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: save, child: const Text('保存记录')),
            ],
          ),
        ),
      ),
    ),
  );
}
