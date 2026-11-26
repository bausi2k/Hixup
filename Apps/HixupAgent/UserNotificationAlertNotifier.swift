import Foundation
import HixupCore
import UserNotifications

struct UserNotificationAlertNotifier: AlertNotifier {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(_ alert: Alert) async {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = StatusPresentation.alertBody(for: alert)
        content.sound = .default
        content.interruptionLevel = alert.severity == .critical ? .timeSensitive : .active

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
