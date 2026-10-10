import SwiftUI

@main
struct SyncBarApp: App {
    static let editorID = "editor"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SyncStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
        } label: {
            Image(systemName: store.overall.symbol)
        }
        .menuBarExtraStyle(.window)

        Window("同步任务", id: Self.editorID) {
            EditorView(store: store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `SyncBar --snapshot out.png [editor-label|new]` renders the panel (or the editor) to a file
        // and quits; used for checking the layout.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated {
                Snapshot.render(to: URL(filePath: args[i + 1]), editing: i + 2 < args.count ? args[i + 2] : nil)
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
        if let editing {
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
