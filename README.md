# MT · Memory Taker

MT 是一个简洁的 Flutter 追番与影视记录应用，支持 Windows、macOS、iPhone 和 iPad。

## 已实现

- 手动添加动画、电影和剧集：想看、在看、看完、搁置、弃坑；首看、看完、弃坑和多次重看日期；评分、收藏、评价、简介、封面及观看集数。
- 使用 Bangumi v0 API 搜索作品，带入封面、简介和总集数；无需登录即可搜索公开条目。
- 从 Kazumi 的 WebDAV **只读**导入新版观看历史：`kazumiSync/history/snapshot.json` 和 `kazumiSync/history/changes/*.jsonl`。会导入作品信息、最近观看集数、播放位置和最近观看时间。已有的 MT 标题、状态、评分和评价会保留。
- 将 MT 记录同步到同一个或另一台 WebDAV 的 `MT/records/`。每条作品单独保存，包含删除标记；不同设备各自新增的作品可合并，同一条记录由最新修改时间决定。连接后应用运行期间每十分钟同步一次，修改记录后也会同步。
- 本地记录存入应用支持目录的 JSON 文件，保留上一版备份。
- 在“设置 → 外观与个性化”选择主题颜色；颜色偏好在本机保存，下次打开仍生效。
- WebDAV 密码分别存入本机系统安全存储，退出后仍保留；在密码框清空可删除对应密码。密码不会写入 MT 记录或 WebDAV 同步文件。
- 在“设置 → 外部导入”选择本地 MT JSON 备份（也支持单条记录 JSON），或同时选择 Kazumi 新版 `snapshot.json` 与多个 `changes/*.jsonl`。导入 MT 备份时保留较新的本机记录和已有删除标记。
- 在“设置 → 应用更新”手动检查更新，或在启动时自动检查。发现新版本会显示更新说明；Windows/macOS 可在应用内下载、校验 SHA-256 并打开安装包，也可以前往 GitHub Releases。iPhone/iPad 可前往 Releases 下载未签名包，再自行签名安装。

## 使用

1. 安装 Flutter 3.47.5 或兼容的稳定版，运行 `flutter pub get`。
2. 运行 `flutter run -d macos`、`flutter run -d windows` 或 `flutter run -d ios`。
3. 在“设置”里填写 WebDAV 地址和凭据。Kazumi 与 MT 可以填同一地址，也可以分别填写不同地址。首次使用点“立即导入”或“立即同步”。
4. 不使用 WebDAV 时，也可在“设置 → 外部导入”选择本地文件。iPhone/iPad 可从“文件”应用选取。
5. 私有仓库的应用内更新检查需要 GitHub 细粒度访问令牌，只授予此仓库的 Contents 读取权限。令牌保存在本机系统安全存储；仓库公开后可以清空。登录 GitHub 的浏览器也可直接访问 Releases。

建议使用 HTTPS WebDAV。HTTP 连接会以明文传输 Basic 认证凭据；若必须连接局域网 HTTP 服务，请确认网络可信。

## 构建

```bash
flutter build windows --release
flutter build macos --release
flutter build ios --release --no-codesign
```

GitHub Actions 会运行检查并生成可下载的 Windows 安装程序（`.exe`）、macOS 磁盘映像（`.dmg`）和未签名 iOS/iPadOS 包（`.ipa`）。Windows 安装程序包含所需的 Visual C++ 运行库。macOS 包未签名，首次打开时系统可能要求手动确认。未签名 iOS `.ipa` 不能直接安装到普通 iPhone/iPad，需要开发者签名或兼容的侧载方式。macOS/iOS 构建需要 Xcode，Windows 构建需要 Windows 开发环境。

## 当前范围

- Kazumi 旧版 `histories.tmp` Hive 二进制备份尚未解析；新版 JSON 同步格式可直接导入。Kazumi 同步文件不提供视频总时长或实际观看分钟数，MT 显示的是**当前播放位置**，不会把它当作累计观看时间。
- 目前仅使用 Bangumi 公开条目资料，不会修改 Bangumi 帐号上的收藏或观看状态。
- 统计页面尚未开发。桌面端更新会打开安装包，需要按系统提示完成安装；未签名 iOS 包无法在应用内直接替换安装。

设计参考 [Kazumi](https://github.com/Predidit/Kazumi) 的简洁导航和分层思路。MT 没有复制 Kazumi 的代码或素材。Bangumi API 资料参见 [官方开发文档](https://github.com/bangumi/dev-docs)。

## 发布

源码与安装包发布在 [MT Releases](https://github.com/M0ries/MT/releases)。仓库目前为私有，只有有权限的 GitHub 帐号可下载。仓库公开前请检查应用标识 `app.memorytaker.memoryTaker` 是否与你的发布计划一致。
