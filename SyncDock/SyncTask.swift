import Foundation

/// One FreeFileSync batch job run by a `local.freefilesync.*` launch agent.
struct SyncTask: Identifiable, Equatable {
    let label: String
    let name: String
    let batchURL: URL
    let schedule: Schedule
    /// Volume that must be mounted for the job to run (nil for local/cloud targets).
    let requiredVolume: String?
    /// Full folder paths; use `TaskLoader.shorten` for display.
    let sourcePath: String
    let targetPath: String
    let mode: SyncMode
    let excludeHidden: Bool
    let includeGit: Bool

    var id: String { label }
    var source: String { TaskLoader.shorten(sourcePath) }
    var target: String { TaskLoader.shorten(targetPath) }

    var isVolumeMissing: Bool {
        guard let requiredVolume else { return false }
        return !FileManager.default.fileExists(atPath: requiredVolume)
    }

    func nextRun(after date: Date = .now) -> Date? {
        schedule.nextRun(after: date)
    }

    var draft: TaskDraft {
        // A target named like the source folder was set up as "target/<source name>".
        let targetURL = URL(filePath: targetPath)
        let nested = !sourcePath.isEmpty && targetURL.lastPathComponent == URL(filePath: sourcePath).lastPathComponent
        return TaskDraft(label: label, originalBatchURL: batchURL, name: name, source: sourcePath,
                         target: nested ? targetURL.deletingLastPathComponent().folderPath : targetPath,
                         createSubfolder: nested, mode: mode, excludeHidden: excludeHidden,
                         includeGit: includeGit, schedule: schedule)
    }
}

extension URL {
    /// The path without the trailing slash Foundation adds to directory URLs ("/" stays "/").
    var folderPath: String {
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

struct SyncLog: Equatable {
    enum Result { case success, warning, error }

    let url: URL
    let date: Date
    /// From the file name; replaced by the log's own result icon once it has been read.
    var result: Result
    /// e.g. "75 项 · 1.64 GB", nil when the log could not be summarised.
    var summary: String?
}

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    /// `SYNCDOCK_AGENTS` overrides where tasks are read from, for screenshots with demo tasks.
    static let launchAgents = ProcessInfo.processInfo.environment["SYNCDOCK_AGENTS"].map { URL(filePath: $0) }
        ?? home.appending(path: "Library/LaunchAgents")
    /// `SYNCDOCK_LOGS` overrides the log folder, for previewing states without touching real logs.
    static let logs = ProcessInfo.processInfo.environment["SYNCDOCK_LOGS"].map { URL(filePath: $0) }
        ?? home.appending(path: "Library/Application Support/FreeFileSync/Logs")
    static let labelPrefix = "local.freefilesync."
    /// Where SyncDock keeps the batch jobs it creates.
    static let jobs = home.appending(path: "FreeFileSync")
}

enum TaskLoader {
    /// Reads every `local.freefilesync.*.plist` launch agent.
    static func loadTasks(now: Date = .now) -> [SyncTask] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.launchAgents,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix(Paths.labelPrefix) && $0.pathExtension == "plist" }
            .compactMap(loadTask)
            .sorted {
                // Soonest scheduled first, then manual-only jobs by name.
                let (a, b) = ($0.nextRun(after: now) ?? .distantFuture, $1.nextRun(after: now) ?? .distantFuture)
                return a != b ? a < b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private static func loadTask(from url: URL) -> SyncTask? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String,
              let args = plist["ProgramArguments"] as? [String],
              let batchPath = args.last
        else { return nil }

        // Arguments are: /bin/sh -c <script> sh <volume> <batch>
        let volume = args.count >= 6 ? args[args.count - 2] : ""
        let batchURL = URL(filePath: batchPath)
        let batch = try? BatchFile(url: batchURL)
        return SyncTask(label: label,
                        name: batchURL.deletingPathExtension().lastPathComponent,
                        batchURL: batchURL,
                        schedule: Schedule(plistValue: plist["StartCalendarInterval"]),
                        requiredVolume: volume.isEmpty ? nil : volume,
                        sourcePath: batch?.source ?? "",
                        targetPath: batch?.target ?? "",
                        mode: batch?.mode ?? .custom,
                        excludeHidden: batch?.excludeHidden ?? false,
                        includeGit: batch?.includeGit ?? false)
    }

    /// Makes paths readable: "桌面/Mphil", "SSD-BAI/BityDev/BityDev", "OneDrive-Curtin/…/Mphil".
    static func shorten(_ path: String) -> String {
        let home = Paths.home.path(percentEncoded: false)
        var p = path
        let desktop = FileManager.default.displayName(atPath: home + "Desktop")
        for (prefix, replacement) in [(home + "Library/CloudStorage/", ""), ("/Volumes/", ""),
                                      (home + "Desktop/", desktop + "/"), (home, "~/")] where p.hasPrefix(prefix) {
            p = replacement + p.dropFirst(prefix.count)
            break
        }
        let parts = p.split(separator: "/")
        return parts.count > 3 ? "\(parts.first!)/…/\(parts.last!)" : p
    }
}

enum LogReader {
    // "<name> 2026-10-10 092842.502.html" or "... [Warning].html" / "... [Error].html"
    private static let pattern = /^(\d{4}-\d{2}-\d{2} \d{6})\.\d{3}(?: \[(\w+)\])?\.html$/

    private static let fileDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmmss"
        return f
    }()

    /// Latest log per task name. Names are compared in NFC since file names may be decomposed.
    static func latestLogs(for names: [String]) -> [String: SyncLog] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Paths.logs.path(percentEncoded: false))) ?? []
        var result: [String: SyncLog] = [:]
        for file in files {
            let nfc = file.precomposedStringWithCanonicalMapping
            for name in names {
                let prefix = name.precomposedStringWithCanonicalMapping + " "
                guard nfc.hasPrefix(prefix),
                      let match = try? pattern.wholeMatch(in: String(nfc.dropFirst(prefix.count))),
                      let date = fileDate.date(from: String(match.1))
                else { continue }
                if let existing = result[name], existing.date >= date { continue }
                let status: SyncLog.Result = switch match.2.map(String.init) {
                case nil: .success
                case "Warning": .warning
                default: .error
                }
                result[name] = SyncLog(url: Paths.logs.appending(path: file), date: date, result: status)
            }
        }
        return result
    }

    /// What a log says, read from its HTML structure rather than its wording: FreeFileSync writes
    /// logs in its own UI language, but the icon file names and the numbers are the same in all of them.
    struct Details {
        var result: SyncLog.Result?
        var processedCount: Int?
        /// e.g. "1.64 GB"; unit names may be in FreeFileSync's language.
        var processedSize: String?
        /// Messages next to an error icon in the log's message list.
        var errors: [String]
        /// Messages next to a warning icon, one line per `<br>`.
        var warnings: [String] = []

        var permissionDenied: Bool { errors.contains { $0.contains("EPERM") } }

        /// Whether every warning is FreeFileSync's "files synced as part of multiple folder pairs",
        /// listing only paths under `target`. A task that keeps `.git` uses a second pair with the same
        /// folders, so both pairs create each new project folder and FreeFileSync warns about it. Batch
        /// jobs can't turn that check off, so it's recognised here instead: the warning lists every
        /// written path as "<base folder> 💾 <relative path>", and the 💾 mark is the same in every language.
        func onlyFolderPairOverlaps(under target: String) -> Bool {
            !warnings.isEmpty && warnings.allSatisfy { message in
                let lines = message.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                // 👓 marks a pair that only reads the path; that's a different kind of dependency.
                guard !lines.contains(where: { $0.contains(" 👓 ") }) else { return false }
                let written = lines.filter { $0.contains(" 💾 ") }
                return !written.isEmpty && written.allSatisfy {
                    $0.components(separatedBy: " 💾 ").first?.trimmingCharacters(in: .whitespaces) == target
                }
            }
        }
    }

    /// Reads the first 16 KB of a log, where the summary and the errors and warnings sit
    /// (logs of big runs can be several MB).
    static func details(of url: URL) -> Details? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16_384), !data.isEmpty else { return nil }
        return details(html: String(decoding: data, as: UTF8.self))
    }

    static func details(html: String) -> Details {
        var details = Details(errors: [])
        if html.contains("images/log/result-error") || html.contains("images/log/result-cancel") {
            details.result = .error
        } else if html.contains("images/log/result-warning") {
            details.result = .warning
        } else if html.contains("images/log/result-succes") {
            details.result = .success
        }

        // Summary row: <img …file.png …></td> <td><span …>75</span> (1.64 GB)</td>
        if let cell = html.firstMatch(of: /images\/log\/file\.png"[^>]*><\/td>\s*<td>(.*?)<\/td>/.dotMatchesNewlines()) {
            let text = plainText(String(cell.1))
            let count = text.prefix { $0 != "(" }.filter(\.isNumber)
            details.processedCount = Int(count)
            if let size = text.firstMatch(of: /\(([^)]*)\)/) { details.processedSize = String(size.1) }
        }

        // Message rows use 16-pixel icons; the summary table's are 24 pixels. Errors are listed once in
        // the "errors and warnings" section and again in the full log, so keep each message once.
        for row in html.matches(of: /images\/log\/msg-error\.png" width="16"[^>]*><\/td>\s*<td>(.*?)<\/td>/.dotMatchesNewlines()) {
            let message = plainText(String(row.1))
            if !details.errors.contains(message) { details.errors.append(message) }
        }
        for row in html.matches(of: /images\/log\/msg-warning\.png" width="16"[^>]*><\/td>\s*<td>(.*?)<\/td>/.dotMatchesNewlines()) {
            let message = plainText(String(row.1).replacing(/<br\s*\/?>/, with: "\n"))
            if !details.warnings.contains(message) { details.warnings.append(message) }
        }
        return details
    }

    /// e.g. "75 项 · 1.64 GB", or "无变化" when nothing was copied.
    static func summary(_ details: Details) -> String? {
        guard let count = details.processedCount else { return nil }
        if count == 0 { return String(localized: "无变化") }
        return [String(localized: "\(count) 项"), details.processedSize].compactMap { $0 }.joined(separator: " · ")
    }

    private static func plainText(_ html: String) -> String {
        html.replacing(/<[^>]+>/, with: " ")
            .replacing("&quot;", with: "\"").replacing("&amp;", with: "&").replacing("&nbsp;", with: " ")
            .replacing("&lt;", with: "<").replacing("&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
