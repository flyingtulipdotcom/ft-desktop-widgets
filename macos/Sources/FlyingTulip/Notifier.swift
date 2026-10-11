import Foundation
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter? {
        // Only a real app bundle can use notifications.
        Bundle.main.bundleIdentifier == nil || Bundle.main.bundleURL.pathExtension != "app" ? nil : UNUserNotificationCenter.current()
    }

    func requestAuthorization() {
        guard let c = center else { return }
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func show(_ t: (critical: Bool, title: String, body: String)) {
        guard let c = center else { return }
        c.delegate = self
        let content = UNMutableNotificationContent()
        content.title = t.title
        content.subtitle = "Flying Tulip"
        content.body = t.body
        content.sound = t.critical ? UNNotificationSound.defaultCritical : .default
        c.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
