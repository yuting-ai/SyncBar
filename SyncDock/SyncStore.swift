import AppKit
import Observation
import ServiceManagement

@MainActor @Observable
final class SyncStore {
    enum Overall {
        case ok, syncing, attention

        var symbol: String {
            switch self {
            case .ok: "externaldrive.badge.checkmark"
            case .syncing: "arrow.triangle.2.circlepath"
            case .attention: "externaldrive.badge.exclamationmark"
            }
        }
    }

    /// A task whose last log is older than this is flagged as overdue.
    static let staleAfter: TimeInterval = 48 * 3600

    private(set) var tasks: [SyncTask] = []
    private(set) var logs: [String: SyncLog] = [:]
    /// Runs started from SyncDock (label → start time), cleared when their log appears.
    private(set) var pending: [String: Date] = [:]
    private(set) var now = Date.now
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var lastError: String?

    private var logDetails: [URL: LogReader.Details] = [:]
    private var timer: Timer?
    private var watcher: DispatchSourceFileSystemObject?

    init(watch: Bool = true) {
        refresh()
        if watch { startWatching() }
    }

    var overall: Overall {
        if !pending.isEmpty { return .syncing }
        return tasks.contains(where: needsAttention) ? .attention : .ok
    }

    func isRunning(_ task: SyncTask) -> Bool { pending[task.label] != nil }

    /// Only scheduled tasks can fall behind; manual ones run when the user says so.
    func isStale(_ task: SyncTask) -> Bool {
        guard task.schedule.kind != .manual else { return false }
        guard let log = logs[task.name] else { return true }
        return now.timeIntervalSince(log.date) > Self.staleAfter
    }

    func needsAttention(_ task: SyncTask) -> Bool {
        isStale(task) || (logs[task.name].map { $0.result != .success } ?? false)
    }

    func refresh() {
        now = .now
        tasks = TaskLoader.loadTasks(now: now)
        var latest = LogReader.latestLogs(for: tasks.map(\.name))
        for (name, log) in latest {
            // Only cache logs that were complete: one still being written is read again next time.
            if logDetails[log.url] == nil, let details = LogReader.details(of: log.url), details.result != nil {
                logDetails[log.url] = details
            }
            guard let details = logDetails[log.url] else { continue }
            latest[name]?.summary = LogReader.summary(details)
            if let result = details.result { latest[name]?.result = result }
        }
        logs = latest
        freeFileSyncInstalled = FreeFileSync.appURL != nil
        noticePermissionErrors()

        // Log files are named after the run's start time, so a log at or after
        // the kickstart (minus clock slack) belongs to our run.
        for task in tasks {
            guard let started = pending[task.label] else { continue }
            let finished = logs[task.name].map { $0.date >= started.addingTimeInterval(-2) } ?? false
            if finished || now.timeIntervalSince(started) > 1800 { pending[task.label] = nil }
        }
    }

    /// Runs the job right away. A missing target folder is created first: when the user starts a run
    /// themselves that's expected, so FreeFileSync shouldn't flag it. Scheduled runs still warn, since a
    /// backup folder vanishing unattended is worth knowing about.
    func runNow(_ task: SyncTask) {
        guard !isRunning(task), !task.isVolumeMissing else { return }
        try? Self.createFolderIfMissing(task.targetPath)
        if launchctl("kickstart", "gui/\(getuid())/\(task.label)") == 0 {
            pending[task.label] = .now
            lastError = nil
        } else {
            lastError = String(localized: "无法启动 \(task.name)")
        }
    }

    // MARK: Setup

    enum Permission { case unknown, checking, granted, denied }

    private static let verifiedAtKey = "fullDiskAccessVerifiedAt"

    private(set) var freeFileSyncInstalled = FreeFileSync.appURL != nil
    /// Whether FreeFileSync has Full Disk Access, remembered from the last successful check.
    private(set) var permission: Permission =
        UserDefaults.standard.object(forKey: SyncStore.verifiedAtKey) == nil ? .unknown : .granted

    var setupComplete: Bool { freeFileSyncInstalled && permission == .granted }

    /// Re-detects FreeFileSync and, unless already verified (or `force`), probes its permission.
    func checkSetup(force: Bool = false) async {
        freeFileSyncInstalled = FreeFileSync.appURL != nil
        guard freeFileSyncInstalled, permission != .checking, force || permission != .granted else { return }
        permission = .checking
        switch await PermissionProbe.run() {
        case .granted:
            permission = .granted
            UserDefaults.standard.set(Date.now, forKey: Self.verifiedAtKey)
        case .denied:
            permission = .denied
            UserDefaults.standard.removeObject(forKey: Self.verifiedAtKey)
        case .unknown:
            permission = .unknown
        }
    }

    #if DEBUG
    /// Forces a setup state for layout snapshots.
    func previewSetup(installed: Bool, permission: Permission) {
        freeFileSyncInstalled = installed
        self.permission = permission
    }
    #endif

    /// A run that failed with EPERM after the last successful check means access was revoked.
    private func noticePermissionErrors() {
        guard permission == .granted,
              let verifiedAt = UserDefaults.standard.object(forKey: Self.verifiedAtKey) as? Date else { return }
        for log in logs.values where log.result != .success && log.date > verifiedAt {
            if logDetails[log.url]?.permissionDenied == true {
                permission = .denied
                UserDefaults.standard.removeObject(forKey: Self.verifiedAtKey)
                return
            }
        }
    }

    // MARK: Editing

    /// The task being edited in the editor window.
    var draft = TaskDraft()

    func beginNewTask() {
        draft = TaskDraft()
    }

    func beginEditing(_ task: SyncTask) {
        draft = task.draft
    }

    func validationError() -> String? {
        draft.validationError(existingBatchURLs: tasks.map(\.batchURL))
    }

    /// Writes the batch job and launch agent for `draft`, then (re)loads the agent.
    /// Returns the saved task's label.
    @discardableResult
    func saveDraft() throws -> String {
        let draft = self.draft
        let label = draft.label ?? LaunchAgent.newLabel()
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.jobs, withIntermediateDirectories: true)

        // Create the destination up front so FreeFileSync doesn't warn about a missing folder.
        try Self.createFolderIfMissing(draft.effectiveTarget)

        var batch = try draft.originalBatchURL.map(BatchFile.init(url:)) ?? BatchFile()
        batch.apply(draft, isNew: draft.isNew)
        try batch.write(to: draft.batchURL)
        // Renamed: drop the old file (to the Trash, so it can be recovered).
        if let old = draft.originalBatchURL, old.standardizedFileURL != draft.batchURL.standardizedFileURL {
            try? fm.trashItem(at: old, resultingItemURL: nil)
        }

        let agentURL = LaunchAgent.url(for: label)
        try LaunchAgent.write(LaunchAgent.plist(label: label, batchURL: draft.batchURL, draft: draft), to: agentURL)
        try reload(label: label, agentURL: agentURL)

        self.draft.label = label
        self.draft.originalBatchURL = draft.batchURL
        refresh()
        return label
    }

    /// Unloads the task and moves its launch agent and batch job to the Trash.
    func delete(_ task: SyncTask) {
        let fm = FileManager.default
        launchctl("bootout", "gui/\(getuid())/\(task.label)")
        try? fm.trashItem(at: LaunchAgent.url(for: task.label), resultingItemURL: nil)
        try? fm.trashItem(at: task.batchURL, resultingItemURL: nil)
        pending[task.label] = nil
        refresh()
    }

    func runNow(label: String) {
        if let task = tasks.first(where: { $0.label == label }) { runNow(task) }
    }

    /// Creates `path` when only its last component is missing. Deeper gaps (e.g. an unplugged
    /// drive's mount point) are left alone so nothing gets written onto the internal disk.
    private static func createFolderIfMissing(_ path: String) throws {
        let fm = FileManager.default
        let url = URL(filePath: path)
        guard !path.isEmpty, !fm.fileExists(atPath: path),
              fm.fileExists(atPath: url.deletingLastPathComponent().folderPath) else { return }
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
    }

    private func reload(label: String, agentURL: URL) throws {
        let domain = "gui/\(getuid())"
        launchctl("bootout", "\(domain)/\(label)")
        // bootout finishes asynchronously; bootstrap fails with EIO until it has.
        for _ in 0..<20 {
            if launchctl("bootstrap", domain, agentURL.path(percentEncoded: false)) == 0 { return }
            Thread.sleep(forTimeInterval: 0.15)
        }
        throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: String(localized: "无法加载定时任务 \(label)")])
    }

    @discardableResult
    private func launchctl(_ args: String...) -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    func openLog(_ task: SyncTask) {
        guard let url = logs[task.name]?.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the batch job in FreeFileSync's editor without running it.
    func edit(_ task: SyncTask) {
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["-edit", task.batchURL.path(percentEncoded: false)]
        config.createsNewApplicationInstance = true
        guard let app = FreeFileSync.appURL else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: config)
    }

    func openFreeFileSync() {
        guard let app = FreeFileSync.appURL else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }

    func openLogsFolder() {
        NSWorkspace.shared.open(Paths.logs)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = String(localized: "无法更改登录项：\(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func startWatching() {
        // New log files appear when a run finishes; refresh right away.
        let fd = open(Paths.logs.path(percentEncoded: false), O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watcher = source
        }
        // Keeps relative times, volume state and run timeouts current.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
