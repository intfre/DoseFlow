import Foundation
import UserNotifications

actor MedicationNotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    private let scheduledIdentifierPrefix = "doseflow.dose."
    private let deferredIdentifierPrefix = "doseflow.deferred."
    private let maximumScheduledDoseNotifications = 60

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func scheduleNext30Days(
        regimen: Regimen,
        engine: ScheduleEngine,
        from startDate: Date,
        excluding excludedOccurrenceIDs: Set<String> = []
    ) async throws {
        await cancelScheduledNotifications()
        let calendar = engine.calendar(for: regimen)
        var scheduledCount = 0

        dayLoop: for dayOffset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate),
                  let schedule = engine.schedule(on: date, regimen: regimen) else {
                continue
            }

            for dose in schedule.doses where !excludedOccurrenceIDs.contains(dose.occurrenceID) {
                guard scheduledCount < maximumScheduledDoseNotifications else {
                    break dayLoop
                }
                guard let deliveryDate = calendar.date(
                    bySettingHour: dose.time.hour,
                    minute: dose.time.minute,
                    second: 0,
                    of: date
                ), deliveryDate > Date() else {
                    continue
                }

                let content = UNMutableNotificationContent()
                content.title = "用药提醒 · \(dose.medication.name)"
                let mealText = dose.mealRelation.displayName.isEmpty ? "" : " · \(dose.mealRelation.displayName)"
                content.body = "\(dose.scheduleGroupName)：\(dose.amount.displayText)\(dose.medication.unit.displayName)\(mealText)"
                content.sound = .default
                content.userInfo = [
                    "occurrenceID": dose.occurrenceID,
                    "scheduledAt": deliveryDate.timeIntervalSince1970
                ]

                let dateComponents = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: deliveryDate
                )
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: dateComponents,
                    repeats: false
                )
                try await center.add(
                    UNNotificationRequest(
                        identifier: scheduledIdentifier(for: dose.occurrenceID),
                        content: content,
                        trigger: trigger
                    )
                )
                scheduledCount += 1
            }
        }
    }

    func scheduleDeferredDose(_ deferral: DoseDeferral) async throws {
        let interval = max(1, deferral.remindAt.timeIntervalSinceNow)
        let content = UNMutableNotificationContent()
        content.title = "延后用药提醒 · \(deferral.medicationName)"
        content.body = "\(deferral.amount.displayText)\(deferral.medicationUnit.displayName)仍待服用，请按已确认的用药计划处理。"
        content.sound = .default
        content.userInfo = [
            "occurrenceID": deferral.occurrenceID,
            "remindAt": deferral.remindAt.timeIntervalSince1970
        ]

        let identifier = deferredIdentifier(for: deferral.occurrenceID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try await center.add(
            UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
        )
    }

    func cancelScheduledDose(occurrenceID: String) {
        center.removePendingNotificationRequests(
            withIdentifiers: [scheduledIdentifier(for: occurrenceID)]
        )
    }

    func cancelDeferredDose(occurrenceID: String) {
        center.removePendingNotificationRequests(
            withIdentifiers: [deferredIdentifier(for: occurrenceID)]
        )
    }

    func cancelAllDeferredDoseNotifications() async {
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(deferredIdentifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelDoseFlowNotifications() async {
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter {
                $0.hasPrefix(scheduledIdentifierPrefix)
                    || $0.hasPrefix(deferredIdentifierPrefix)
            }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func cancelScheduledNotifications() async {
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(scheduledIdentifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func scheduledIdentifier(for occurrenceID: String) -> String {
        scheduledIdentifierPrefix + occurrenceID
    }

    private func deferredIdentifier(for occurrenceID: String) -> String {
        deferredIdentifierPrefix + occurrenceID
    }
}
