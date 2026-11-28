# MRecorder

把看过、正在看和想看的动漫或影视作品放在一个地方。MRecorder 可以记录观看日期、集数、评分与评价，搜索 Bangumi 作品资料，并通过 WebDAV 在自己的设备间同步。

## 下载

到 [Releases](https://github.com/M0ries/MRecorder/releases) 下载对应安装包：

| 设备 | 文件 | 安装方式 |
| --- | --- | --- |
| macOS | `MR_macos_1.3.2.dmg` | 打开后将 MRecorder 拖入“应用程序” |
| Windows | `MR_windows_1.3.2.exe` | 运行安装程序 |
| iPhone / iPad | `MR_ios_unsigned_1.3.2.ipa` | 未签名包，需自行签名后安装 |

macOS 安装包未公证，首次打开可能需要在系统设置中确认。iOS/iPadOS 包不能直接安装到普通设备。

## 开始使用

1. 打开“记录”，点“添加作品”。可以搜索 Bangumi 并带入封面、简介和总集数，也可以手动输入。
2. 选择“在看”“看完”“想看”“搁置”或“弃坑”，填写观看日期、看到的集数和评价。日期可以只填年份、年月，或完整日期。
3. 要在多台设备使用，在“设置 → MRecorder 多端同步”填写同一个 WebDAV 地址、用户名和密码，再点“立即同步”。不需要同步时，记录只保存在本机。
4. 在“设置 → 外部导入”可以导入或导出 JSON 记录。普通导入会保留较新的现有记录；“用文件替换全部”会以所选文件为唯一清单，操作前请先导出备份。

如果你正在使用 Kazumi，可以在设置中填写 Kazumi 的 WebDAV 位置或导入其新版历史文件。这个功能只读取 Kazumi 的记录；不使用 Kazumi 也能完整使用 MRecorder。

## 常见问题

**导入显示 0 条？** 普通导入会跳过已经存在或更新的作品。要恢复已删除的记录，选“从备份恢复”；要用文件里的清单替换现有记录，选“用文件替换全部”。

**换成 MRecorder 后，旧 MT 记录还在吗？** 在。应用标识和 WebDAV 数据位置继续沿用 MT，因此原有记录、设置和同步数据可以继续使用。macOS 会把 `MRecorder.app` 作为新应用放进“应用程序”；确认记录正常后，可以手动移除旧的 `MT.app`。

**需要 GitHub 账号或令牌吗？** 不需要。安装包和更新信息来自公开仓库。WebDAV 同步只需要你自己的 WebDAV 账号。

## 数据与兼容性

- 记录在本机保存为 JSON；开启同步后，MRecorder 会把记录存入 WebDAV 的 `MT/records/`，以兼容旧版 MT。删除和修改也会同步到其他设备。
- WebDAV 密码保存在本机系统安全存储中，不会写入记录文件；建议使用 HTTPS。
- Bangumi 资料用于封面、简介和总集数。你手动写的观看日期、评价与自定义总集数不会被资料刷新覆盖。
- Kazumi 的新版 `snapshot.json` 和 `changes/*.jsonl` 历史文件可导入；旧版 `histories.tmp` 不支持。播放位置表示最近一次播放停在何处，不是累计观看时长。
- MRecorder 目前不提供视频播放或 Bangumi 账号写入功能。

## 开发

项目使用 Flutter。安装兼容的 Flutter 3.47.5 后运行：

```bash
flutter pub get
flutter test
flutter run -d macos
```

Windows、macOS 与未签名 iOS/iPadOS 安装包由 [GitHub Actions](.github/workflows/build.yml) 构建。界面组织参考 [Kazumi](https://github.com/Predidit/Kazumi) 的简洁导航；作品资料使用 [Bangumi API](https://github.com/bangumi/dev-docs)。
