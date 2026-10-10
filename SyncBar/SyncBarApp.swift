import SwiftUI

@main
struct SyncBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SyncStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
        } label: {
            Image(systemName: store.overall.symbol)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `SyncBar --snapshot out.png` renders the panel to a file and quits (used for checking the layout).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated {
                Snapshot.render(to: URL(filePath: args[i + 1]))
            }
            exit(0)
        }
    }
}

@MainActor
enum Snapshot {
    static func render(to url: URL) {
        let host = NSHostingView(rootView: MenuView(store: SyncStore(watch: false)))
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
