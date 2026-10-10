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
    let result: Result
    /// e.g. "75 项 · 1.64 GB", nil when the log could not be summarised.
    var summary: String?
}

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let launchAgents = home.appending(path: "Library/LaunchAgents")
    /// `SYNCBAR_LOGS` overrides the log folder, for previewing states without touching real logs.
    static let logs = ProcessInfo.processInfo.environment["SYNCBAR_LOGS"].map { URL(filePath: $0) }
        ?? home.appending(path: "Library/Application Support/FreeFileSync/Logs")
    static let labelPrefix = "local.freefilesync."
    /// Where SyncBar keeps the batch jobs it creates.
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
        for (prefix, replacement) in [(home + "Library/CloudStorage/", ""), ("/Volumes/", ""),
                                      (home + "Desktop/", "桌面/"), (home, "~/")] where p.hasPrefix(prefix) {
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

    /// Pulls "Elements processed: 75 (1.64 GB)" out of a FreeFileSync HTML log.
    static func summary(of url: URL) -> String? {
        guard let text = head(of: url) else { return nil }
        guard let m = text.firstMatch(of: /Elements processed:\s*([\d,]+)\s*\(([^)]+)\)/) else { return nil }
        let count = m.1.replacing(",", with: "")
        return count == "0" ? "无变化" : "\(count) 项 · \(m.2)"
    }

    /// Whether the run hit macOS privacy protection, i.e. FreeFileSync lacks Full Disk Access.
    static func mentionsPermissionDenied(_ url: URL) -> Bool {
        guard let text = head(of: url) else { return false }
        return text.contains("EPERM") || text.contains("Operation not permitted")
    }

    /// The text of the log's first 16 KB, where the summary and errors sit; big runs' logs can be several MB.
    private static func head(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16_384) else { return nil }
        return String(decoding: data, as: UTF8.self).replacing(/<[^>]+>/, with: " ")
    }
}
