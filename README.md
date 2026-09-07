# LiteMusic

一个专为 **iOS 14.0** 设计的轻量级网易云音乐播放器，使用 **SwiftUI + UIKit 混合开发**，支持通过 **TrollStore** 以永久签名方式安装（无需 Apple 开发者账号）。

## 功能特性

- **登录**：网易云扫码登录、手机号登录，登录态通过 Keychain 持久化保存
- **歌单**：我的歌单、每日推荐、私人 FM
- **歌曲列表**：显示歌名 / 歌手 / 专辑 / 时长，支持搜索
- **播放控制**：底部迷你播放器 + 全屏播放器，支持播放/暂停、上一首/下一首、进度拖拽、播放模式切换（列表循环/随机/单曲循环）、音量控制
- **歌词**：LRC 滚动歌词，当前行高亮
- **后台播放**：锁屏控制、控制中心控制、后台音频播放

## 技术栈

| 模块 | 方案 |
| --- | --- |
| UI | SwiftUI（主要）+ UIKit（搜索栏 / 音量 / 图片缓存） |
| 网络 | URLSession |
| 音频 | AVFoundation + MediaPlayer |
| 持久化 | UserDefaults + Keychain |
| 状态管理 | ObservableObject / Combine / @EnvironmentObject |
| 数据源 | [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi) |
| 最低部署目标 | iOS 14.0 |
| 开发环境 | Xcode 12.5+（Swift 5） |

> 无任何第三方库依赖，全部使用 Apple 官方框架，天然兼容 iOS 14.0。

## 项目结构

```
LiteMusic/
├── LiteMusic.xcodeproj          # Xcode 工程（含共享 scheme）
├── LiteMusic/
│   ├── App/LiteMusicApp.swift   # 应用入口 + AppDelegate（后台音频会话）
│   ├── Models/                  # Song / Playlist / User / 歌词解析
│   ├── Services/                # APIService / AudioPlayer / AuthManager / KeychainHelper
│   ├── ViewModels/              # PlayerViewModel / PlaylistViewModel
│   ├── Views/                   # MainTab / Login / Playlist / SongList / Player / MiniPlayer / Lyrics / SearchBar / RemoteImage
│   └── Info.plist               # 后台音频权限等配置
├── .github/workflows/build.yml  # GitHub Actions 自动构建 IPA（Windows 也能用）
└── README.md
```

---

## 第一步：部署 API 服务

本项目数据源为开源的 NeteaseCloudMusicApi，需要自行部署一个可访问的接口地址（默认为空，需在 App「我的 → API 设置」中填写）。

```bash
git clone https://github.com/Binaryify/NeteaseCloudMusicApi.git
cd NeteaseCloudMusicApi
npm install
node app.js        # 默认监听 http://0.0.0.0:3000
```

在手机上打开 App 后，进入「我的」页，将 `API 地址` 填为你的服务器地址，例如 `http://192.168.1.5:3000`（手机与服务器需网络互通）。

---

## 第二步：构建 IPA

### 方式 A：GitHub Actions（推荐，无需 Mac / 无需 Xcode，适合 Windows）

本仓库已内置 `.github/workflows/build.yml`，把项目推送到 GitHub 仓库后会自动在 macOS 云主机上编译并产出 `LiteMusic.ipa`。

1. 在 GitHub 新建一个仓库，把本项目所有文件推送上去：

   ```bash
   git init
   git add .
   git commit -m "LiteMusic"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git push -u origin main
   ```

2. 推送后 GitHub Actions 会自动运行；或到仓库 **Actions** 页手动点击 **Run workflow**。
3. 构建完成后，进入该次运行详情，在 **Artifacts** 中下载 `LiteMusic-IPA`，解压得到 `LiteMusic.ipa`。

> 原理：`xcodebuild` 关闭签名编译出 `.app` → `ldid -S` 做 ad-hoc 伪签名 → 打包成 IPA。TrollStore 利用 CoreTrust 漏洞安装，因此**无需 Apple 开发者证书**。

### 方式 B：本地 Mac + Xcode（手动打包）

1. 用 Xcode 12.5+ 打开 `LiteMusic.xcodeproj`。
2. `Product → Archive` 生成 `LiteMusic.xcarchive`（即使没有开发者账号也可 Archive，签名失败可忽略）。
3. 取出 App 并伪签名打包：

   ```bash
   # 安装 ldid
   brew install procursus/tap/ldid

   APP="LiteMusic.xcarchive/Products/Applications/LiteMusic.app"
   ldid -S "$APP/LiteMusic"        # 伪签名

   mkdir -p Payload
   cp -R "$APP" Payload/
   zip -qr LiteMusic.ipa Payload   # 得到 LiteMusic.ipa
   ```

### 方式 C：无 Xcode 的本地命令行（macOS 上，仅装命令行工具）

```bash
xcodebuild archive \
  -project LiteMusic.xcodeproj \
  -scheme LiteMusic \
  -configuration Release \
  -archivePath LiteMusic.xcarchive \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

APP="LiteMusic.xcarchive/Products/Applications/LiteMusic.app"
ldid -S "$APP/LiteMusic"
mkdir -p Payload && cp -R "$APP" Payload/
zip -qr LiteMusic.ipa Payload
```

---

## 第三步：通过 TrollStore 安装

1. 确保你的 iPhone 已安装 **TrollStore**（利用 CoreTrust 漏洞的永久签名安装器，适用于特定 iOS 版本）。
2. 将 `LiteMusic.ipa` 传到手机（隔空投送 / 文件 App / 网盘均可）。
3. 用 TrollStore 打开该 IPA 并安装，即可免签名长期使用。

---

## 常见问题

- **App 打开后提示「尚未配置 API 地址」**：进入「我的」页填写你部署的 NeteaseCloudMusicApi 地址并保存。
- **搜索/推荐无数据**：这些接口需要登录态，请先扫码或手机号登录。
- **部分歌曲无法播放**：网易云对 VIP / 无版权歌曲不返回播放地址，App 会自动跳到下一首。
- **锁屏不显示控制**：请确认 iOS「设置 → 通知/后台」已允许 App，且已使用过 App 播放一次。
- **音量滑块在模拟器上不显示**：`MPVolumeView` 仅真机显示系统音量，属正常现象。

## 二次开发提示

- 所有代码均有中文注释，核心逻辑见 `Services/APIService.swift`（接口封装）、`Services/AudioPlayer.swift`（播放）、`ViewModels/PlayerViewModel.swift`（播放状态机）。
- 若要修改接口地址默认值，改 `APIService.baseURL`；若要新增歌单/歌曲入口，在 `Views/PlaylistView.swift` 与 `Views/SongListView.swift` 中扩展 `SongListSource`。
