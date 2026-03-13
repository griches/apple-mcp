import Foundation
import UserNotifications

protocol AppNotifying: Sendable {
    func deliver(title: String, body: String) async
}

actor AppNotificationManager: AppNotifying {
    private var didRequestAuthorization = false

    func deliver(title: String, body: String) async {
        if !didRequestAuthorization {
            _ = await requestAuthorization()
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    private func requestAuthorization() async -> Bool {
        didRequestAuthorization = true
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert])) ?? false
    }
}

actor NullNotificationManager: AppNotifying {
    func deliver(title _: String, body _: String) async {}
}
