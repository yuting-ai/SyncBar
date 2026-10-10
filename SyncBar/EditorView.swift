import SwiftUI

struct EditorView: View {
    @Bindable var store: SyncStore
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var saveError: String?
    @State private var confirmingDelete = false

    private var draft: TaskDraft { store.draft }
    private var existingTask: SyncTask? { store.tasks.first { $0.label == draft.label } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("名称", text: $store.draft.name, prompt: Text("例如：论文-移动硬盘"))
                    FolderField(title: "源文件夹", path: $store.draft.source, canCreate: false) { picked in
                        if store.draft.name.isEmpty { store.draft.name = picked.lastPathComponent }
                    }
                    FolderField(title: "目标文件夹", path: $store.draft.target, canCreate: true)
                    if !draft.source.isEmpty {
                        Toggle("在目标里新建「\(draft.sourceFolderName)」文件夹", isOn: $store.draft.createSubfolder)
                    }
                    destinationPreview
                }

                Section("同步方式") {
                    Picker("同步方式", selection: $store.draft.mode) {
                        Text("更新").tag(SyncMode.update)
                        Text("镜像").tag(SyncMode.mirror)
                        if draft.mode == .custom || existingTask?.mode == .custom {
                            Text("自定义").tag(SyncMode.custom)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    modeExplanation
                }

                Section("过滤") {
                    Toggle("排除隐藏文件（以 . 开头的文件和文件夹）", isOn: $store.draft.excludeHidden)
                    Toggle("但保留 .git 文件夹（Git 仓库的历史记录）", isOn: $store.draft.includeGit)
                        .disabled(!draft.excludeHidden)
                        .padding(.leading, 18)
                }

                Section("什么时候同步") {
                    Picker("运行方式", selection: $store.draft.schedule.kind) {
                        Text("仅手动").tag(Schedule.Kind.manual)
                        Text("每天").tag(Schedule.Kind.daily)
                        Text("每周").tag(Schedule.Kind.weekly)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch draft.schedule.kind {
                    case .manual:
                        Text("只在你点菜单栏里的 ▶ 时同步一次。")
                            .font(.callout).foregroundStyle(.secondary)
                    case .daily:
                        timePicker
                    case .weekly:
                        WeekdayPicker(days: $store.draft.schedule.weekdays)
                        timePicker
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            footer.padding(16)
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle(draft.isNew ? "新建同步任务" : "编辑：\(existingTask?.name ?? draft.name)")
        .confirmationDialog("删除任务「\(draft.name)」？", isPresented: $confirmingDelete) {
            Button("删除任务", role: .destructive) {
                if let existingTask { store.delete(existingTask) }
                dismissWindow(id: SyncBarApp.editorID)
            }
        } message: {
            Text("只删除这个同步任务和它的定时设置（会移到废纸篓），已经同步过去的文件不受影响。")
        }
    }

    /// Spells out where files will land, and warns before mixing them into a folder that has other content.
    @ViewBuilder private var destinationPreview: some View {
        if !draft.source.isEmpty && !draft.target.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("同步到：\(TaskLoader.shorten(draft.effectiveTarget))", systemImage: "arrow.turn.down.right")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !draft.createSubfolder && Self.hasVisibleContent(draft.target) {
                    Label("目标文件夹里已经有其他内容，「\(draft.sourceFolderName)」里的文件会直接和它们放在一起。",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private static func hasVisibleContent(_ path: String) -> Bool {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return items.contains { !$0.hasPrefix(".") }
    }

    @ViewBuilder private var modeExplanation: some View {
        switch draft.mode {
        case .update:
            Text("把新增和修改过的文件复制到目标，不删除目标里的任何文件。")
                .font(.callout).foregroundStyle(.secondary)
        case .mirror:
            Label("让目标和源完全一致：源里删掉的文件，目标里也会删掉（移到废纸篓或云端回收站）。",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
        case .custom:
            Text("这个任务用的是在 FreeFileSync 里设置的同步规则（比如双向同步），保存时不会改动。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var timePicker: some View {
        DatePicker("时间", selection: Binding(
            get: { Calendar.current.date(from: DateComponents(hour: draft.schedule.hour,
                                                               minute: draft.schedule.minute)) ?? .now },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                store.draft.schedule.hour = c.hour ?? 0
                store.draft.schedule.minute = c.minute ?? 0
            }), displayedComponents: .hourAndMinute)
    }

    private var footer: some View {
        HStack {
            if !draft.isNew {
                Button("删除…", role: .destructive) { confirmingDelete = true }
                Button("高级设置") {
                    if let existingTask { store.edit(existingTask) }
                }
                .help("在 FreeFileSync 中打开这个任务的全部设置")
            }
            Spacer()
            if let message = saveError ?? store.validationError() {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(saveError == nil ? Color.secondary : .red)
                    .lineLimit(2)
            }
            Button("取消") { dismissWindow(id: SyncBarApp.editorID) }
                .keyboardShortcut(.cancelAction)
            Button("保存并同步") { save(runAfter: true) }
                .disabled(store.validationError() != nil || draft.requiresVolumeMissing)
            Button("保存") { save(runAfter: false) }
                .keyboardShortcut(.defaultAction)
                .disabled(store.validationError() != nil)
        }
    }

    private func save(runAfter: Bool) {
        do {
            let label = try store.saveDraft()
            saveError = nil
            if runAfter { store.runNow(label: label) }
            dismissWindow(id: SyncBarApp.editorID)
        } catch {
            saveError = "保存失败：\(error.localizedDescription)"
        }
    }
}

private extension TaskDraft {
    var requiresVolumeMissing: Bool {
        let volume = LaunchAgent.requiredVolume(source: source, target: target)
        return !volume.isEmpty && !FileManager.default.fileExists(atPath: volume)
    }
}

private struct FolderField: View {
    let title: String
    @Binding var path: String
    let canCreate: Bool
    var onPick: (URL) -> Void = { _ in }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if path.isEmpty {
                    Text("未选择").foregroundStyle(.tertiary)
                } else {
                    Label(TaskLoader.shorten(path), systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                }
                Button("选择…", action: choose)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = canCreate
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择\(title)"
        if !path.isEmpty { panel.directoryURL = URL(filePath: path) }
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.folderPath
        onPick(url)
    }
}

/// Monday-first day toggles; values use launchd numbering (1 = Monday … 7 = Sunday).
private struct WeekdayPicker: View {
    @Binding var days: Set<Int>
    private let names = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        LabeledContent("星期") {
            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { day in
                    Toggle(names[day - 1], isOn: Binding(
                        get: { days.contains(day) },
                        set: { if $0 { days.insert(day) } else { days.remove(day) } }))
                        .toggleStyle(.button)
                }
            }
        }
    }
}
