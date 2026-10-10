import SwiftUI

@main
struct SyncBarApp: App {
    static let editorID = "editor"
    static let setupID = "setup"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SyncStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("设置 SyncBar", id: Self.setupID) {
            SetupView(store: store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("同步任务", id: Self.editorID) {
            EditorView(store: store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

/// The menu bar icon. It lives for the whole session, so it also runs the launch-time setup check.
private struct MenuBarLabel: View {
    let store: SyncStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: store.overall.symbol)
            .task {
                await store.checkSetup()
                if !store.setupComplete {
                    openWindow(id: SyncBarApp.setupID)
                    NSApp.activate()
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `SyncBar --snapshot out.png [task-label|new|setup|setup-missing|setup-denied]` renders the
        // panel, the editor or the setup window to a file and quits; used for checking the layout.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated {
                // A following "-AppleLanguages (en)" style option is not a view name.
                let view = i + 2 < args.count && !args[i + 2].hasPrefix("-") ? args[i + 2] : nil
                Snapshot.render(to: URL(filePath: args[i + 1]), editing: view)
            }
            exit(0)
        }
    }
}

@MainActor
enum Snapshot {
    static func render(to url: URL, editing: String?) {
        let store = SyncStore(watch: false)
        let root: AnyView
        if let editing, editing.hasPrefix("setup") {
            #if DEBUG
            // "setup", "setup-missing" or "setup-denied"
            store.previewSetup(installed: editing != "setup-missing",
                               permission: editing == "setup-denied" ? .denied : .granted)
            #endif
            root = AnyView(SetupView(store: store))
        } else if let editing {
            if let task = store.tasks.first(where: { $0.label == editing }) {
                store.beginEditing(task)
            } else {
                store.beginNewTask()
            }
            root = AnyView(EditorView(store: store))
        } else {
            root = AnyView(MenuView(store: store))
        }

        let host = NSHostingView(rootView: root)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.backgroundColor = .windowBackgroundColor
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
