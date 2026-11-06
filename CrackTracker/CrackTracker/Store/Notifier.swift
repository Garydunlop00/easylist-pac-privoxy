import BackgroundTasks
import Foundation
import UserNotifications

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func gameCracked(_ game: Game) {
        let content = UNMutableNotificationContent()
        content.title = "\(game.title) has been cracked"
        var parts: [String] = []
        if let days = game.daysToCrack { parts.append("after \(Fmt.longDays(days))") }
        if !game.groups.isEmpty { parts.append("by \(game.groups.joined(separator: ", "))") }
        content.body = parts.isEmpty ? "Reported by \(game.sourceNames.joined(separator: ", "))." : parts.joined(separator: " ").capitalizedFirst + "."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "cracked-\(game.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum BackgroundRefresh {
    static let identifier = (Bundle.main.bundleIdentifier ?? "com.example.cracktracker") + ".refresh"

    /// Asks iOS to wake the app every few hours to check for new cracks.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
