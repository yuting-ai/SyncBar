import Foundation

/// One FreeFileSync batch job scheduled by a `local.freefilesync.*` launch agent.
struct SyncTask: Identifiable, Equatable {
    let label: String
    let name: String
    let batchURL: URL
    let hour: Int
    let minute: Int
    /// Volume that must be mounted for the job to run (nil for local/cloud targets).
    let requiredVolume: String?
    let source: String
    let target: String

    var id: String { label }

    var isVolumeMissing: Bool {
        guard let requiredVolume else { return false }
        return !FileManager.default.fileExists(atPath: requiredVolume)
    }

    func nextRun(after date: Date = .now) -> Date? {
        Calendar.current.nextDate(after: date,
                                  matching: DateComponents(hour: hour, minute: minute),
                                  matchingPolicy: .nextTime)
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
    static let freeFileSyncApp = URL(filePath: "/Applications/FreeFileSync.app")
    static let labelPrefix = "local.freefilesync."
}

enum TaskLoader {
    /// Reads every `local.freefilesync.*.plist` launch agent, soonest next run first.
    static func loadTasks(now: Date = .now) -> [SyncTask] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.launchAgents,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix(Paths.labelPrefix) && $0.pathExtension == "plist" }
            .compactMap(loadTask)
            .sorted { ($0.nextRun(after: now) ?? .distantFuture) < ($1.nextRun(after: now) ?? .distantFuture) }
    }

    private static func loadTask(from url: URL) -> SyncTask? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String,
              let args = plist["ProgramArguments"] as? [String],
              let batchPath = args.last,
              let interval = plist["StartCalendarInterval"] as? [String: Int],
              let hour = interval["Hour"], let minute = interval["Minute"]
        else { return nil }

        // Arguments are: /bin/sh -c <script> sh <volume> <batch>
        let volume = args.count >= 6 ? args[args.count - 2] : ""
        let batchURL = URL(filePath: batchPath)
        let (source, target) = folderPair(in: batchURL)
        return SyncTask(label: label,
                        name: batchURL.deletingPathExtension().lastPathComponent,
                        batchURL: batchURL,
                        hour: hour,
                        minute: minute,
                        requiredVolume: volume.isEmpty ? nil : volume,
                        source: source,
                        target: target)
    }

    private static func folderPair(in batchURL: URL) -> (String, String) {
        guard let doc = try? XMLDocument(contentsOf: batchURL),
              let left = try? doc.nodes(forXPath: "//FolderPairs/Pair[1]/Left").first?.stringValue,
              let right = try? doc.nodes(forXPath: "//FolderPairs/Pair[1]/Right").first?.stringValue
        else { return ("", "") }
        return (shorten(left), shorten(right))
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
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // The summary sits at the top; logs of big runs can be several MB.
        guard let head = try? handle.read(upToCount: 16_384),
              let html = String(data: head, encoding: .utf8)
        else { return nil }
        let text = html.replacing(/<[^>]+>/, with: " ")
        guard let m = text.firstMatch(of: /Elements processed:\s*([\d,]+)\s*\(([^)]+)\)/) else { return nil }
        let count = m.1.replacing(",", with: "")
        return count == "0" ? "无变化" : "\(count) 项 · \(m.2)"
    }
}
