import AppKit

enum FreeFileSync {
    static let bundleID = "org.freefilesync.FreeFileSync"
    static let downloadURL = URL(string: "https://freefilesync.org/download.php")!
    static let fullDiskAccessSettings =
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!

    /// Wherever Launch Services finds FreeFileSync, not only /Applications.
    static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static var version: String? {
        appURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
    }
}

/// Finds out whether FreeFileSync has Full Disk Access by letting it try.
///
/// macOS won't tell one app about another's privacy permissions, so this runs a throwaway batch job
/// whose source is a folder only Full Disk Access can list. A filter matching nothing means no file
/// is ever copied. FreeFileSync is started through Launch Services so it runs with its own
/// permissions, not SyncBar's.
enum PermissionProbe {
    enum Result { case granted, denied, unknown }

    static let protectedFolder = "/Library/Application Support/com.apple.TCC"

    static func run() async -> Result {
        await Task.detached(priority: .utility) { runBlocking() }.value
    }

    private static func runBlocking() -> Result {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "syncbar-probe-\(UUID().uuidString)")
        let logs = dir.appending(path: "logs")
        let target = dir.appending(path: "target")
        defer { try? fm.removeItem(at: dir) }
        do {
            try fm.createDirectory(at: logs, withIntermediateDirectories: true)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            let batchURL = dir.appending(path: "probe.ffs_batch")
            try BatchFile.probe(source: protectedFolder, target: target.folderPath, logFolder: logs.folderPath)
                .write(to: batchURL)

            // -W waits for FreeFileSync to quit; -n avoids handing the job to an open FreeFileSync window.
            let open = Process()
            open.executableURL = URL(filePath: "/usr/bin/open")
            open.arguments = ["-W", "-g", "-n", "-b", FreeFileSync.bundleID, batchURL.folderPath]
            try open.run()
            let deadline = Date.now + 60
            while open.isRunning && Date.now < deadline { Thread.sleep(forTimeInterval: 0.2) }
            if open.isRunning { open.terminate(); return .unknown }

            guard let log = try fm.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil).first,
                  let text = try? String(contentsOf: log, encoding: .utf8)
            else { return .unknown }
            return text.contains("Cannot open directory") ? .denied : .granted
        } catch {
            return .unknown
        }
    }
}
