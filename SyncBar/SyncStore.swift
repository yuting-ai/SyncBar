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
    /// Runs started from SyncBar (label → start time), cleared when their log appears.
    private(set) var pending: [String: Date] = [:]
    private(set) var now = Date.now
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var lastError: String?

    private var summaries: [URL: String] = [:]
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

    func isStale(_ task: SyncTask) -> Bool {
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
            if summaries[log.url] == nil { summaries[log.url] = LogReader.summary(of: log.url) ?? "" }
            latest[name]?.summary = summaries[log.url].flatMap { $0.isEmpty ? nil : $0 }
        }
        logs = latest

        // Log files are named after the run's start time, so a log at or after
        // the kickstart (minus clock slack) belongs to our run.
        for task in tasks {
            guard let started = pending[task.label] else { continue }
            let finished = logs[task.name].map { $0.date >= started.addingTimeInterval(-2) } ?? false
            if finished || now.timeIntervalSince(started) > 1800 { pending[task.label] = nil }
        }
    }

    func runNow(_ task: SyncTask) {
        guard !isRunning(task), !task.isVolumeMissing else { return }
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = ["kickstart", "gui/\(getuid())/\(task.label)"]
        do {
            try process.run()
            pending[task.label] = .now
            lastError = nil
        } catch {
            lastError = "无法启动 \(task.name)：\(error.localizedDescription)"
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
        NSWorkspace.shared.openApplication(at: Paths.freeFileSyncApp, configuration: config)
    }

    func openFreeFileSync() {
        NSWorkspace.shared.openApplication(at: Paths.freeFileSyncApp, configuration: .init())
    }

    func openLogsFolder() {
        NSWorkspace.shared.open(Paths.logs)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = "无法更改登录项：\(error.localizedDescription)"
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
