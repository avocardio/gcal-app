import SwiftUI

@main
struct GCalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup(id: "main") {
            CalendarWebView()
                .ignoresSafeArea()
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Navigation") {
                Button("Reload") { notify(.reload) }
                    .keyboardShortcut("r")
                Divider()
                Button("Back") { notify(.goBack) }
                    .keyboardShortcut("[")
                Button("Forward") { notify(.goForward) }
                    .keyboardShortcut("]")
                Divider()
                Button("Go to Today") { notify(.goHome) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarContent(count: EventCount.shared.count)
        } label: {
            let count = EventCount.shared.count
            if let n = count {
                Image(systemName: "\(min(n, 50)).circle")
            } else {
                Image(systemName: "calendar")
            }
        }
    }

    private func notify(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

// MARK: - Shared Event Count

@Observable
final class EventCount {
    static let shared = EventCount()
    var count: Int? = nil
}

// MARK: - Menu Bar

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    let count: Int?

    var body: some View {
        Button("Open Calendar") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")

        if let n = count {
            Divider()
            Text("\(n) events today")
        }

        Divider()
        Button("Quit GCal") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let reload = Notification.Name("gcal.reload")
    static let goBack = Notification.Name("gcal.goBack")
    static let goForward = Notification.Name("gcal.goForward")
    static let goHome = Notification.Name("gcal.goHome")
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
