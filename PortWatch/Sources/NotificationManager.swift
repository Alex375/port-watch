import Foundation
import UserNotifications

/// Manages macOS notifications for PortWatch. Notifications are off by default.
@MainActor
final class NotificationManager: Sendable {
    static let shared = NotificationManager()

    private init() {}

    /// Request notification permission from the system.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Send a notification for a newly detected port.
    func notifyNewPort(port: UInt16, processName: String, projectName: String) {
        let content = UNMutableNotificationContent()
        content.title = "New port detected"
        content.body = ":\(port) — \(processName)"
        if projectName != "Other" {
            content.body += " (\(projectName))"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "new-port-\(port)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Send a notification for a port conflict (multiple PIDs on same port).
    func notifyPortConflict(port: UInt16, processNames: [String]) {
        let content = UNMutableNotificationContent()
        content.title = "Port conflict on :\(port)"
        content.body = "Multiple processes listening: \(processNames.joined(separator: ", "))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "conflict-\(port)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
