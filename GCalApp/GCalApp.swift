import SwiftUI
import EventKit

@main
struct GCalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var counter = EventCounter()

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
            MenuBarContent(remaining: counter.remaining, authorized: counter.authorized)
        } label: {
            if counter.authorized {
                Image(systemName: "\(min(counter.remaining, 50)).circle")
            } else {
                Image(systemName: "calendar")
            }
        }
    }

    private func notify(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

// MARK: - Menu Bar

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    let remaining: Int
    let authorized: Bool

    var body: some View {
        Button("Open Calendar") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")

        if authorized {
            Divider()
            Text("\(remaining) events remaining today")
        }

        Divider()
        Button("Quit GCal") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

// MARK: - Event Counter (EventKit)

@Observable
final class EventCounter {
    private(set) var remaining = 0
    private(set) var authorized = false
    private let store = EKEventStore()
    private var observers: [Any] = []

    init() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
                guard granted else { return }
                self?.refresh()
                self?.startObserving()
            }
        }
    }

    func refresh() {
        let now = Date()
        let end = Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
        let pred = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        remaining = store.events(matching: pred).count
    }

    private func startObserving() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: .main
            ) { [weak self] _ in self?.refresh() }
        )
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
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
