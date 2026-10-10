# SyncBar

[中文](README.zh-CN.md) | **English**

A macOS menu bar app for keeping folders in sync with a simple interface: pick a source and a destination folder, choose when to sync, and SyncBar takes care of the rest in the background.

The syncing itself is done by the free, open-source [FreeFileSync](https://freefilesync.org). SyncBar adds what FreeFileSync doesn't focus on: an easy interface, scheduled runs, and status at a glance.

<p align="center"><img src="docs/images/panel-en.png" width="428" alt="SyncBar's menu bar panel listing three sync tasks"></p>

> SyncBar is an independent project and is not affiliated with FreeFileSync.

## Download

**[⬇ Download SyncBar for macOS](https://github.com/yuting-ai/SyncBar/releases/latest/download/SyncBar.dmg)**

macOS 15 or later · Apple silicon and Intel · Notarized by Apple · Free and open source (MIT)

All versions and release notes: [Releases](https://github.com/yuting-ai/SyncBar/releases)

## Screenshots

<table>
  <tr>
    <th>Editing a task</th>
    <th>First-run setup</th>
  </tr>
  <tr>
    <td valign="top"><img src="docs/images/editor-en.png" width="380" alt="Task editor with source and destination folders, sync method, filters and a weekly schedule"></td>
    <td valign="top"><img src="docs/images/setup-en.png" width="420" alt="First-run setup checking FreeFileSync and Full Disk Access"></td>
  </tr>
</table>

## Features

- **Status in the menu bar**: each task's last result (how many items, how much data) and its next scheduled run.
- **Create and edit tasks**: choose a source and a destination folder. By default SyncBar creates a folder named after the source inside the destination, and shows exactly where files will go.
- **Two sync methods**
  - **Update**: copies new and changed files to the destination and never deletes anything there (default).
  - **Mirror**: makes the destination identical to the source; files deleted from the source are also deleted from the destination (moved to the Trash).
- **Filters**: exclude hidden files, optionally keeping `.git` folders (handy for backing up code).
- **Schedules**: manual, daily, or on chosen weekdays. Runs in the background with **no app needing to stay open**.
- **Sync Now**: run any task once, whenever you like.
- **External drive aware**: if the drive isn't connected, the sync is skipped with a notification, so nothing is written to your internal disk by mistake.
- **First-run setup**: checks that FreeFileSync is installed and has Full Disk Access, and walks you through each step.
- **Chinese and English interface**: follows your system language.

## Requirements

- macOS 15 or later (Apple silicon or Intel)
- [FreeFileSync](https://freefilesync.org/download.php) (free)

## Installation

1. [Download SyncBar.dmg](https://github.com/yuting-ai/SyncBar/releases/latest/download/SyncBar.dmg), open it, and drag SyncBar into the Applications folder.
2. Open SyncBar. It has no window and no Dock icon; it appears in the **menu bar** at the top right of the screen.
3. The first time, a “Welcome to SyncBar” window guides you through two steps:
   1. **Install FreeFileSync**: click “Download FreeFileSync”. Once it's installed, SyncBar detects it automatically.
   2. **Allow FreeFileSync to access all files**: click “Open System Settings”, click ＋ below the Full Disk Access list, choose FreeFileSync and turn on its switch. SyncBar checks again when you come back.

> **Why Full Disk Access?** Scheduled syncs run in the background, where nobody can click “Allow”. Granting access in advance lets FreeFileSync read your Desktop, Documents and external drives. The permission is for FreeFileSync; SyncBar itself needs no special permissions.

## Usage

Click SyncBar in the menu bar to open the panel:

| To | Use |
|---|---|
| Create a task | ＋ at the top right of the panel |
| Edit or delete a task | ⚙ next to the task |
| Sync a task now | ▶ next to the task |
| See the detailed log of a sync | Click the “Last: …” line under the task |
| Start SyncBar when you log in | “Open at Login” at the bottom of the panel |

### What happens when I delete a task?

Only the task and its schedule are deleted (moved to the Trash). **Files that were already synced stay where they are.**

### Need more options?

When editing a task, click “Advanced” to open all of its settings in FreeFileSync (for example two-way sync or size filters). Settings you make in FreeFileSync are kept when you later save the task in SyncBar. The one exception: toggling either of the two filter switches in SyncBar regenerates the filter rules from SyncBar's settings.

## FAQ

**What happens to scheduled syncs while my Mac sleeps or is shut down?**
A sync missed during sleep runs once when the Mac wakes. A sync missed while the Mac is shut down is not made up; it runs at the next scheduled time. You also need to be logged in (a locked screen is fine).

**A window popped up during a sync?**
When a sync fails, FreeFileSync shows its results window so you can see what went wrong; close it when you're done. Syncs without errors finish silently in the background.

**What if the external drive isn't connected?**
That sync is skipped and you get a notification. It syncs normally the next time the drive is connected.

**A warning says the destination folder doesn't exist?**
If the backup folder was deleted or moved, a scheduled sync recreates it and warns you. If you deleted it yourself, you can ignore the warning. Syncing manually with ▶ in SyncBar doesn't produce this warning.

**Do I need to open FreeFileSync?**
No. SyncBar runs it in the background; you never need to open it.

## Uninstalling

1. Delete your sync tasks in SyncBar one by one (this also removes their background schedules).
2. Quit SyncBar (“Quit” at the bottom of the panel) and drag it from Applications to the Trash.

If you already deleted SyncBar, its scheduled tasks keep running. Remove them in Terminal:

```bash
for f in ~/Library/LaunchAgents/local.freefilesync.*.plist; do launchctl bootout gui/$(id -u) "$f"; mv "$f" ~/.Trash/; done
```

## How it works

```
SyncBar (interface)
 ├─ Task files  ~/FreeFileSync/<task name>.ffs_batch                 FreeFileSync batch jobs
 ├─ Schedules   ~/Library/LaunchAgents/local.freefilesync.*.plist    macOS launchd
 └─ Reads logs  ~/Library/Application Support/FreeFileSync/Logs

When a task is due: launchd → checks the external drive is connected → starts FreeFileSync in the background → log written → SyncBar shows the result
```

- Each task is one FreeFileSync batch file plus one launchd schedule. SyncBar only reads and writes these files; it never copies your files itself.
- When you edit a task, SyncBar changes only the settings shown in its interface and keeps everything else in the batch file (toggling the filter switches regenerates the filter rules).
- Checking Full Disk Access: macOS doesn't let one app query another's permissions, so SyncBar has FreeFileSync try to read a protected system folder (with a filter that guarantees nothing is copied) and judges by whether that works.

## Development

Requires Xcode 26 or later.

```bash
open SyncBar.xcodeproj   # then press ⌘R
```

Quit the installed SyncBar first, or you'll get two icons in the menu bar.

| File | Contents |
|---|---|
| `SyncBar/SyncBarApp.swift` | Entry point, menu bar icon, windows |
| `SyncBar/MenuView.swift` | Menu bar panel |
| `SyncBar/EditorView.swift` | New / edit task window |
| `SyncBar/SetupView.swift` | First-run setup |
| `SyncBar/SyncStore.swift` | State, Sync Now, saving and deleting tasks |
| `SyncBar/SyncTask.swift` | Reading tasks and logs |
| `SyncBar/TaskFiles.swift` | Reading and writing FreeFileSync batch files and launchd schedules |
| `SyncBar/Setup.swift` | Detecting FreeFileSync and its permission |

### Debugging

You can check the interface without opening the menu bar by rendering it to an image:

```bash
SyncBar.app/Contents/MacOS/SyncBar --snapshot out.png                 # menu bar panel
SyncBar.app/Contents/MacOS/SyncBar --snapshot out.png new             # new task window
SyncBar.app/Contents/MacOS/SyncBar --snapshot out.png <task label>    # editing a task
SyncBar.app/Contents/MacOS/SyncBar --snapshot out.png setup-missing   # setup window (Debug builds: setup / setup-missing / setup-denied)
```

Set the environment variable `SYNCBAR_LOGS=<folder>` to make SyncBar read a different log folder, for previewing failed, warning and other states with fake logs. `SYNCBAR_AGENTS=<folder>` does the same for the launch agents it reads tasks from.

The README screenshots are rendered from demo tasks, so no real folder names show up. Regenerate them (both languages) after changing the interface:

```bash
scripts/make-screenshots.sh
```

### Localization

The interface's source language is Simplified Chinese; the English translation lives in `SyncBar/Localizable.xcstrings` (a String Catalog), and Xcode extracts new strings from the code when building. To check for untranslated strings:

```bash
xcodebuild -exportLocalizations -project SyncBar.xcodeproj -localizationPath /tmp/loc -exportLanguage en
```

To render the interface in a given language: `SyncBar.app/Contents/MacOS/SyncBar --snapshot out.png -AppleLanguages "(en)"`.

SyncBar doesn't rely on the wording of FreeFileSync's logs (FreeFileSync writes them in its own interface language). It reads the result icons' file names, the numbers and the error codes instead, so it works whatever language FreeFileSync is set to.

### Releasing

`scripts/release.sh` does everything in one command: archive → Developer ID signing → notarize and staple the app → build the DMG → sign and notarize the DMG → Gatekeeper check. The result is `build/release/SyncBar-<version>.dmg`.

Before the first run, store the notarization credentials in the keychain (this needs an app-specific password for your Apple ID):

```bash
xcrun notarytool store-credentials SyncBar-notary --apple-id <Apple ID> --team-id 3TJQ367JDZ
```

To release a new version, change `MARKETING_VERSION` in Xcode, then run:

```bash
scripts/release.sh
```

Add `--skip-notarize` to check signing and packaging without submitting for notarization.

Publish it on GitHub. The DMG is uploaded as `SyncBar.dmg` so that the README's download link (`releases/latest/download/SyncBar.dmg`) always points to the newest version:

```bash
cp build/release/SyncBar-1.1.dmg build/release/SyncBar.dmg
gh release create v1.1 build/release/SyncBar.dmg --title "SyncBar 1.1" --notes "…"
```

## License

SyncBar is released under the [MIT License](LICENSE).

SyncBar contains no FreeFileSync code. It only runs the copy of FreeFileSync the user installed, and doesn't bundle or distribute it. FreeFileSync itself is licensed under GPL-3.0.
