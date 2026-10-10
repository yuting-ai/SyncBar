import SwiftUI

/// First-run checklist: FreeFileSync installed, FreeFileSync has Full Disk Access, optional login item.
struct SetupView: View {
    let store: SyncStore
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("欢迎使用 SyncBar").font(.title2.bold())
                    Text("SyncBar 借助 FreeFileSync 在后台同步文件。开始之前，先完成下面两步。")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 22) {
                installStep
                permissionStep
                loginStep
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                Button("稍后再说") { dismissWindow(id: SyncBarApp.setupID) }
                    .keyboardShortcut(.cancelAction)
                Button("开始使用") { dismissWindow(id: SyncBarApp.setupID) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.setupComplete)
            }
            .padding(16)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle("设置 SyncBar")
        // Coming back from System Settings or a download: check again without making the user click.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.checkSetup() }
        }
        .task { await store.checkSetup() }
    }

    private var installStep: some View {
        Step(number: 1, title: "安装 FreeFileSync", state: store.freeFileSyncInstalled ? .done : .todo) {
            if store.freeFileSyncInstalled {
                Group {
                    if let version = FreeFileSync.version {
                        Text("已安装 FreeFileSync \(version)")
                    } else {
                        Text("已安装")
                    }
                }
                .foregroundStyle(.secondary)
            } else {
                Text("FreeFileSync 是免费开源的同步工具，SyncBar 用它来执行同步。下载后打开安装包，按提示安装即可。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("下载 FreeFileSync") { NSWorkspace.shared.open(FreeFileSync.downloadURL) }
                    Button("已经装好了，重新检查") { Task { await store.checkSetup() } }
                }
            }
        }
    }

    private var permissionStep: some View {
        Step(number: 2, title: "允许 FreeFileSync 访问所有文件", state: permissionState) {
            switch store.permission {
            case _ where !store.freeFileSyncInstalled:
                Text("装好 FreeFileSync 后再做这一步。").foregroundStyle(.secondary)
            case .granted:
                Text("已确认 FreeFileSync 拥有「完全磁盘访问权限」。").foregroundStyle(.secondary)
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在检查…").foregroundStyle(.secondary)
                }
            case .unknown, .denied:
                Text("定时同步在后台运行，没人能点「允许」，所以要提前授权，FreeFileSync 才能读取桌面、文稿和移动硬盘。")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("1. 点「打开系统设置」")
                    Text("2. 点列表下方的 ＋，在「应用程序」里选择 FreeFileSync")
                    Text("3. 打开 FreeFileSync 旁边的开关，然后回到这里")
                }
                .font(.callout)
                if store.permission == .denied {
                    Label("还没有权限。如果刚打开开关，FreeFileSync 正在运行的话需要先退出它。",
                          systemImage: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("打开系统设置") { NSWorkspace.shared.open(FreeFileSync.fullDiskAccessSettings) }
                    Button("检查") { Task { await store.checkSetup(force: true) } }
                }
            }
        }
        .disabled(!store.freeFileSyncInstalled)
        .opacity(store.freeFileSyncInstalled ? 1 : 0.5)
    }

    private var permissionState: Step.State {
        guard store.freeFileSyncInstalled else { return .todo }
        return switch store.permission {
        case .granted: .done
        case .denied: .failed
        case .checking, .unknown: .todo
        }
    }

    private var loginStep: some View {
        Step(number: 3, title: "登录时自动启动 SyncBar（推荐）", state: store.launchAtLogin ? .done : .optional) {
            Toggle("开机登录后在菜单栏显示同步状态", isOn: Binding(get: { store.launchAtLogin },
                                                      set: { store.setLaunchAtLogin($0) }))
                .toggleStyle(.checkbox)
        }
    }
}

private struct Step: View {
    enum State { case todo, done, failed, optional }

    let number: Int
    let title: LocalizedStringKey
    let state: State
    let content: AnyView

    init(number: Int, title: LocalizedStringKey, state: State, @ViewBuilder content: () -> some View) {
        self.number = number
        self.title = title
        self.state = state
        self.content = AnyView(content())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            badge.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var badge: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.red)
        case .todo, .optional:
            Text("\(number)")
                .font(.callout.bold())
                .frame(width: 22, height: 22)
                .background(Circle().strokeBorder(state == .todo ? Color.accentColor : .secondary, lineWidth: 1.5))
                .foregroundStyle(state == .todo ? Color.accentColor : .secondary)
        }
    }
}
