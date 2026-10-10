import SwiftUI

struct MenuView: View {
    let store: SyncStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()

            if store.tasks.isEmpty {
                Text("没有找到 FreeFileSync 定时任务")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                VStack(spacing: 2) {
                    ForEach(store.tasks) { task in
                        TaskRow(task: task, store: store)
                    }
                }
                .padding(6)
            }

            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            Divider()

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 380)
        .onAppear { store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: store.overall.symbol)
                .font(.title2)
                .foregroundStyle(overallColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("文件同步").font(.headline)
                Text(overallText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新")
        }
    }

    private var footer: some View {
        HStack {
            Toggle("登录时启动", isOn: Binding(get: { store.launchAtLogin },
                                           set: { store.setLaunchAtLogin($0) }))
                .toggleStyle(.checkbox)
                .font(.callout)
            Spacer()
            Button("FreeFileSync") { store.openFreeFileSync() }
            Button("日志") { store.openLogsFolder() }
            Button("退出") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private var overallColor: Color {
        switch store.overall {
        case .ok: .green
        case .syncing: .accentColor
        case .attention: .orange
        }
    }

    private var overallText: String {
        switch store.overall {
        case .syncing:
            return "正在同步…"
        case .attention:
            let count = store.tasks.filter(store.needsAttention).count
            return "\(count) 个任务需要注意"
        case .ok:
            return "\(store.tasks.count) 个任务，全部正常"
        }
    }
}

private struct TaskRow: View {
    let task: SyncTask
    let store: SyncStore
    @State private var hovering = false

    private var log: SyncLog? { store.logs[task.name] }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                    .font(.system(.body, weight: .semibold))
                Text("\(task.source)  →  \(task.target)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                lastRunLine
                nextRunLine
            }

            Spacer(minLength: 4)

            actions
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Color.primary.opacity(0.06) : .clear))
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var statusIcon: some View {
        if store.isRunning(task) {
            ProgressView().controlSize(.small)
        } else if let log, !store.isStale(task) {
            switch log.result {
            case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .error: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }
        } else {
            Image(systemName: "clock.badge.exclamationmark.fill").foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var lastRunLine: some View {
        if store.isRunning(task) {
            Text("正在同步…").font(.caption).foregroundStyle(Color.accentColor)
        } else if let log {
            let parts = ["上次 " + DateText.describe(log.date, now: store.now), resultText(log)]
            Button {
                store.openLog(task)
            } label: {
                Text(parts.compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(store.isStale(task) ? .orange : log.result == .success ? .secondary : resultColor(log))
            }
            .buttonStyle(.plain)
            .help("打开这次同步的日志")
        } else {
            Text("还没有同步记录").font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var nextRunLine: some View {
        if task.isVolumeMissing {
            Label("\(task.requiredVolume.map { URL(filePath: $0).lastPathComponent } ?? "移动硬盘") 未连接，到时会跳过",
                  systemImage: "externaldrive.badge.xmark")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let next = task.nextRun(after: store.now) {
            Text("下次 " + DateText.describe(next, now: store.now))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            Button {
                store.edit(task)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("在 FreeFileSync 中编辑")

            Button {
                store.runNow(task)
            } label: {
                Image(systemName: "play.fill")
            }
            .disabled(store.isRunning(task) || task.isVolumeMissing)
            .help(task.isVolumeMissing ? "移动硬盘未连接" : "立即同步")
        }
        .buttonStyle(.borderless)
        .opacity(hovering || store.isRunning(task) ? 1 : 0.55)
    }

    private func resultText(_ log: SyncLog) -> String? {
        if store.isStale(task) {
            let days = Int(store.now.timeIntervalSince(log.date) / 86_400)
            return "已 \(days) 天未同步"
        }
        switch log.result {
        case .success: return log.summary
        case .warning: return "有警告" + (log.summary.map { "（\($0)）" } ?? "")
        case .error: return "有错误，点此查看"
        }
    }

    private func resultColor(_ log: SyncLog) -> Color {
        log.result == .error ? .red : .orange
    }
}

enum DateText {
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayAndTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    static func describe(_ date: Date, now: Date) -> String {
        let cal = Calendar.current
        let hm = time.string(from: date)
        if cal.isDate(date, inSameDayAs: now) { return "今天 " + hm }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) { return "昨天 " + hm }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: t) { return "明天 " + hm }
        return dayAndTime.string(from: date)
    }
}
