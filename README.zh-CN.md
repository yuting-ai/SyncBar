# SyncBar

**中文** | [English](README.md)

一个 macOS 菜单栏小工具，用简单的界面管理文件夹同步：选好源文件夹和目标文件夹，设好什么时候同步，剩下的交给它在后台完成。

同步本身由免费开源的 [FreeFileSync](https://freefilesync.org) 执行，SyncBar 负责它不擅长的部分：好用的界面、定时运行和状态一目了然。

> SyncBar 是独立开发的工具，不是 FreeFileSync 的官方产品。

## 下载

**[⬇ 下载 SyncBar（macOS）](https://github.com/yuting-ai/SyncBar/releases/latest/download/SyncBar.dmg)**

macOS 15 或更高版本 · Apple 芯片和 Intel 均可 · 已通过 Apple 公证 · 免费开源

所有版本和更新说明：[Releases](https://github.com/yuting-ai/SyncBar/releases)

## 功能

- **菜单栏状态**：每个任务上次同步的结果（复制了多少项、多大）、下次什么时候运行；出错、有警告或超过 2 天没同步时，图标会变色提醒。
- **新建和编辑任务**：选择源文件夹、目标文件夹，默认在目标里新建同名文件夹，并预览实际同步到哪里。
- **两种同步方式**
  - **更新**：只把新增和修改过的文件复制到目标，从不删除目标里的文件（默认）。
  - **镜像**：让目标和源完全一致，源里删掉的文件，目标里也会删掉（移到废纸篓）。
- **过滤**：排除隐藏文件，并可以单独保留 `.git` 文件夹（适合备份代码项目）。
- **定时**：仅手动 / 每天 / 每周几，在后台运行，**不需要开着任何软件**。
- **立即同步**：随时手动同步一次。
- **移动硬盘感知**：硬盘没插时跳过本次同步并发通知，不会把文件写到电脑内置硬盘上。
- **首次启动引导**：检查 FreeFileSync 是否已安装、是否有「完全磁盘访问权限」，一步步带你完成设置。
- **中文和英文界面**：自动跟随系统语言。

## 系统要求

- macOS 15 或更高版本（Apple 芯片和 Intel 均可）
- [FreeFileSync](https://freefilesync.org/download.php)（免费）

## 安装

1. [下载 SyncBar.dmg](https://github.com/yuting-ai/SyncBar/releases/latest/download/SyncBar.dmg)，双击打开，把 SyncBar 拖进「应用程序」文件夹。
2. 打开 SyncBar。它没有窗口，也不在程序坞里，只会出现在屏幕右上角的**菜单栏**。
3. 第一次打开时会弹出「欢迎使用 SyncBar」，按提示完成两步：
   1. **安装 FreeFileSync**：点「下载 FreeFileSync」，装好后回到 SyncBar，会自动识别。
   2. **允许 FreeFileSync 访问所有文件**：点「打开系统设置」，在「完全磁盘访问权限」列表里点 ＋，选择 FreeFileSync 并打开开关。回到 SyncBar 后会自动检查。

> **为什么需要「完全磁盘访问权限」？** 定时同步在后台运行，没有人能点「允许」。提前授权后，FreeFileSync 才能读取桌面、文稿和移动硬盘里的文件。这个权限是授予 FreeFileSync 的，SyncBar 自己不需要任何特殊权限。

## 使用

点菜单栏里的 SyncBar 图标打开面板：

| 操作 | 位置 |
|---|---|
| 新建任务 | 面板右上角的 ＋ |
| 编辑或删除任务 | 任务右边的 ⚙ |
| 立即同步一次 | 任务右边的 ▶ |
| 查看某次同步的详细日志 | 点任务下面的「上次 …」那一行 |
| 开机自动启动 SyncBar | 面板底部「登录时启动」 |

菜单栏图标的含义：

| 图标 | 含义 |
|---|---|
| 硬盘带 ✓ | 所有任务正常 |
| 循环箭头 | 正在同步 |
| 硬盘带 ! | 有任务出错、有警告，或者定时任务超过 2 天没有同步 |

### 删除任务会怎样？

只删除同步任务和它的定时设置（移到废纸篓），**已经同步过去的文件不受影响**。

### 需要更多设置？

编辑任务时点「高级设置」，会在 FreeFileSync 里打开这个任务的全部选项（比如双向同步、按文件大小过滤）。在 FreeFileSync 里做的设置，SyncBar 之后保存时会原样保留。唯一的例外：如果在 SyncBar 里切换了「过滤」的两个开关，过滤规则会按 SyncBar 的设置重新生成。

## 常见问题

**Mac 睡眠或关机时，定时同步会怎样？**
睡眠时错过的同步会在唤醒后补跑一次；关机时错过的不会补，等下一次定时再跑。另外需要处于登录状态（锁屏没关系）。

**同步时屏幕上出现了一个窗口？**
同步出错时，FreeFileSync 会显示结果窗口，方便你看到哪里出了问题，看完关掉即可。没有错误时它会在后台自动完成。

**移动硬盘没插会怎样？**
这次同步会跳过，并弹出一条通知。下次插着的时候会正常同步。

**提示「目标文件夹不存在」？**
备份文件夹被删除或移动时，定时同步会重新创建它，并给出一条警告提醒你。如果是你自己删的，忽略即可；在 SyncBar 里点 ▶ 手动同步不会出现这条警告。

**FreeFileSync 的界面需要打开吗？**
不需要。SyncBar 在后台调用它，平时完全不用打开。

## 卸载

1. 在 SyncBar 里逐个删除同步任务（这样会同时移除后台定时设置）。
2. 退出 SyncBar（面板底部「退出」），把它从「应用程序」拖到废纸篓。

如果已经先删除了 SyncBar，后台定时任务仍会继续运行。可以在终端里移除它们：

```bash
for f in ~/Library/LaunchAgents/local.freefilesync.*.plist; do launchctl bootout gui/$(id -u) "$f"; mv "$f" ~/.Trash/; done
```

## 工作原理

```
SyncBar（界面）
 ├─ 任务文件   ~/FreeFileSync/<任务名>.ffs_batch          FreeFileSync 批处理任务
 ├─ 定时设置   ~/Library/LaunchAgents/local.freefilesync.*.plist   macOS launchd
 └─ 读取日志   ~/Library/Application Support/FreeFileSync/Logs

到时间后：launchd → 检查移动硬盘是否已连接 → 在后台启动 FreeFileSync 执行任务 → 写入日志 → SyncBar 显示结果
```

- 每个任务对应一个 FreeFileSync 批处理文件和一个 launchd 定时配置。SyncBar 只读写这两种文件，不自己复制任何文件。
- 编辑任务时，SyncBar 只修改界面上能改的几项，任务文件里的其他设置原样保留（切换过滤开关时会重新生成过滤规则）。
- 「完全磁盘访问权限」的检查方式：macOS 不允许查询其他 App 的权限，所以 SyncBar 让 FreeFileSync 试读一个受保护的系统文件夹（过滤规则保证不复制任何文件），以能否读取来判断。

## 开发

需要 Xcode 26 或更高版本。

```bash
open SyncBar.xcodeproj   # 然后按 ⌘R 运行
```

运行前先退出已安装的 SyncBar，否则菜单栏会出现两个图标。

| 文件 | 内容 |
|---|---|
| `SyncBar/SyncBarApp.swift` | 入口、菜单栏图标、窗口 |
| `SyncBar/MenuView.swift` | 菜单栏面板 |
| `SyncBar/EditorView.swift` | 新建 / 编辑任务窗口 |
| `SyncBar/SetupView.swift` | 首次启动引导 |
| `SyncBar/SyncStore.swift` | 状态、立即同步、保存 / 删除任务 |
| `SyncBar/SyncTask.swift` | 读取任务、日志 |
| `SyncBar/TaskFiles.swift` | 读写 FreeFileSync 批处理文件和 launchd 配置 |
| `SyncBar/Setup.swift` | 检测 FreeFileSync 和权限 |

### 调试

不用点开菜单栏也能检查界面，把界面渲染成图片：

```bash
SyncBar.app/Contents/MacOS/SyncBar --snapshot out.png                 # 菜单栏面板
SyncBar.app/Contents/MacOS/SyncBar --snapshot out.png new             # 新建任务窗口
SyncBar.app/Contents/MacOS/SyncBar --snapshot out.png <任务 label>    # 编辑某个任务
SyncBar.app/Contents/MacOS/SyncBar --snapshot out.png setup-missing   # 引导页（Debug 版：setup / setup-missing / setup-denied）
```

设置环境变量 `SYNCBAR_LOGS=<文件夹>` 可以让 SyncBar 读取另一个日志文件夹，用假日志预览出错、警告等状态。

### 本地化

界面文字的基准语言是简体中文，英文翻译在 `SyncBar/Localizable.xcstrings`（String Catalog）里，Xcode 编译时会自动提取代码里新增的文字。检查是否还有没翻译的：

```bash
xcodebuild -exportLocalizations -project SyncBar.xcodeproj -localizationPath /tmp/loc -exportLanguage en
```

用指定语言渲染界面：`SyncBar.app/Contents/MacOS/SyncBar --snapshot out.png -AppleLanguages "(en)"`。

SyncBar 读取 FreeFileSync 日志时不依赖日志的文字（FreeFileSync 会用它自己的界面语言写日志），而是看日志里结果图标的文件名、数字和错误码，所以无论 FreeFileSync 设置成什么语言都能正确判断。

### 图标

App 图标由 `scripts/make-icon.swift` 用代码绘制（没有使用 SF Symbols，它的许可不允许用于 App 图标）。修改后重新生成：

```bash
for pt in 16 32 128 256 512; do
  swift scripts/make-icon.swift SyncBar/Assets.xcassets/AppIcon.appiconset/icon_${pt}x${pt}.png $pt
  swift scripts/make-icon.swift SyncBar/Assets.xcassets/AppIcon.appiconset/icon_${pt}x${pt}@2x.png $((pt * 2))
done
```

### 发布

`scripts/release.sh` 一条命令完成：归档 → Developer ID 签名 → 公证并附上公证结果 → 制作 DMG → DMG 签名、公证 → Gatekeeper 验证。产物在 `build/release/SyncBar-<版本>.dmg`。

第一次使用前，需要把公证凭证存进钥匙串（需要 Apple ID 的 App 专用密码）：

```bash
xcrun notarytool store-credentials SyncBar-notary --apple-id <Apple ID> --team-id 3TJQ367JDZ
```

发布新版本：在 Xcode 里修改 `MARKETING_VERSION`，然后运行：

```bash
scripts/release.sh
```

只想检查签名和打包、不提交公证时，加 `--skip-notarize`。

发布到 GitHub。DMG 统一以 `SyncBar.dmg` 的文件名上传，这样 README 里的下载链接（`releases/latest/download/SyncBar.dmg`）始终指向最新版本：

```bash
cp build/release/SyncBar-1.1.dmg build/release/SyncBar.dmg
gh release create v1.1 build/release/SyncBar.dmg --title "SyncBar 1.1" --notes "…"
```

## 许可

SyncBar 以 [GNU 通用公共许可证 v3.0（GPL-3.0）](LICENSE) 发布，与 FreeFileSync 相同。你可以自由使用、修改和再分发 SyncBar；分发修改后的版本时，需要同样以 GPL-3.0 公开源代码。

Copyright © 2026 Yuting Bai

SyncBar 不包含 FreeFileSync 的任何代码，只调用用户自行安装的 FreeFileSync，也不随安装包分发它。
