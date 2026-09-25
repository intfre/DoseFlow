import Foundation
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

struct NotificationScheduleSummary: Sendable {
    let scheduledCount: Int
    let nextDeliveryDate: Date?
}

actor MedicationNotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    private let scheduledIdentifierPrefix = "doseflow.dose."
    private let deferredIdentifierPrefix = "doseflow.deferred."
    private let testIdentifier = "doseflow.test"
    private let maximumScheduledDoseNotifications = 60

    func requestAuthorization() async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func scheduleNext30Days(
        regimen: Regimen,
        engine: ScheduleEngine,
        from startDate: Date,
        excluding excludedOccurrenceIDs: Set<String> = [],
        allowCurrentMinute: Bool = false
    ) async throws -> NotificationScheduleSummary {
        await cancelScheduledNotifications()
        let calendar = engine.calendar(for: regimen)
        let now = Date()
        var scheduledCount = 0
        var nextDeliveryDate: Date?

        dayLoop: for dayOffset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate),
                  let schedule = engine.schedule(on: date, regimen: regimen) else {
                continue
            }

            for dose in schedule.doses where !excludedOccurrenceIDs.contains(dose.occurrenceID) {
                guard scheduledCount < maximumScheduledDoseNotifications else {
                    break dayLoop
                }
                guard let plannedDeliveryDate = calendar.date(
                    bySettingHour: dose.time.hour,
                    minute: dose.time.minute,
                    second: 0,
                    of: date
                ) else {
                    continue
                }

                let deliveryDate: Date
                if plannedDeliveryDate > now {
                    deliveryDate = plannedDeliveryDate
                } else if allowCurrentMinute,
                          now.timeIntervalSince(plannedDeliveryDate) < 60 {
                    deliveryDate = now.addingTimeInterval(2)
                } else {
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
                    [.year, .month, .day, .hour, .minute, .second],
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
                if nextDeliveryDate == nil || deliveryDate < nextDeliveryDate! {
                    nextDeliveryDate = deliveryDate
                }
            }
        }

        return NotificationScheduleSummary(
            scheduledCount: scheduledCount,
            nextDeliveryDate: nextDeliveryDate
        )
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

    func scheduleTestReminder(after interval: TimeInterval = 5) async throws {
        let content = UNMutableNotificationContent()
        content.title = "药序测试提醒"
        content.body = "通知功能正常，之后会按疗程计划提醒用药。"
        content.sound = .default

        center.removePendingNotificationRequests(withIdentifiers: [testIdentifier])
        try await center.add(
            UNNotificationRequest(
                identifier: testIdentifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, interval),
                    repeats: false
                )
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

    func cancelScheduledDoseNotifications() async {
        await cancelScheduledNotifications()
    }

    func cancelDoseFlowNotifications() async {
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter {
                $0.hasPrefix(scheduledIdentifierPrefix)
                    || $0.hasPrefix(deferredIdentifierPrefix)
                    || $0 == testIdentifier
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

actor MedicationAlarmScheduler {
    private let alarmIdentifierStorageKey = "doseflow.alarm.identifiers.v1"
    private let maximumScheduledAlarms = 30
    private let userDefaults: UserDefaults

    init() {
        userDefaults = .standard
    }

    func requestAuthorization() async throws -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized:
                return true
            case .notDetermined:
                return try await AlarmManager.shared.requestAuthorization() == .authorized
            case .denied:
                return false
            @unknown default:
                return false
            }
        }
        #endif
        return false
    }

    func isAuthorized() -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
        #endif
        return false
    }

    func scheduleNext30Days(
        regimen: Regimen,
        engine: ScheduleEngine,
        from startDate: Date,
        excluding excludedOccurrenceIDs: Set<String> = [],
        allowCurrentMinute: Bool = false
    ) async throws -> NotificationScheduleSummary {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return try await scheduleAlarms(
                regimen: regimen,
                engine: engine,
                from: startDate,
                excluding: excludedOccurrenceIDs,
                allowCurrentMinute: allowCurrentMinute
            )
        }
        #endif
        return NotificationScheduleSummary(scheduledCount: 0, nextDeliveryDate: nil)
    }

    func scheduleTestAlarm(after interval: TimeInterval = 10) async throws -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let id = UUID()
            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(
                    alert: alarmAlert(title: "药序测试闹钟")
                ),
                metadata: MedicationAlarmMetadata(
                    occurrenceIDs: ["doseflow.test.alarm"]
                ),
                tintColor: Color(red: 0.14, green: 0.48, blue: 0.29)
            )
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(Date().addingTimeInterval(max(1, interval))),
                attributes: attributes
            )
            _ = try await AlarmManager.shared.schedule(
                id: id,
                configuration: configuration
            )
            var identifiers = storedAlarmIdentifiers()
            identifiers.append(id)
            persistAlarmIdentifiers(identifiers)
            return true
        }
        #endif
        return false
    }

    func cancelAll() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for id in storedAlarmIdentifiers() {
                try? AlarmManager.shared.cancel(id: id)
            }
        }
        #endif
        persistAlarmIdentifiers([])
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func scheduleAlarms(
        regimen: Regimen,
        engine: ScheduleEngine,
        from startDate: Date,
        excluding excludedOccurrenceIDs: Set<String>,
        allowCurrentMinute: Bool
    ) async throws -> NotificationScheduleSummary {
        cancelAll()

        let calendar = engine.calendar(for: regimen)
        let now = Date()
        var groupedDoses: [Date: [ScheduledDose]] = [:]

        for dayOffset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate),
                  let schedule = engine.schedule(on: date, regimen: regimen) else {
                continue
            }

            for dose in schedule.doses where !excludedOccurrenceIDs.contains(dose.occurrenceID) {
                guard let plannedDeliveryDate = calendar.date(
                    bySettingHour: dose.time.hour,
                    minute: dose.time.minute,
                    second: 0,
                    of: date
                ) else {
                    continue
                }

                let deliveryDate: Date
                if plannedDeliveryDate > now {
                    deliveryDate = plannedDeliveryDate
                } else if allowCurrentMinute,
                          now.timeIntervalSince(plannedDeliveryDate) < 60 {
                    deliveryDate = now.addingTimeInterval(2)
                } else {
                    continue
                }

                groupedDoses[deliveryDate, default: []].append(dose)
            }
        }

        let upcomingGroups = groupedDoses
            .sorted { $0.key < $1.key }
            .prefix(maximumScheduledAlarms)
        var scheduledIdentifiers: [UUID] = []
        var nextDeliveryDate: Date?

        do {
            for (deliveryDate, doses) in upcomingGroups {
                let id = UUID()
                let title = alarmTitle(for: doses)
                let presentation = AlarmPresentation(
                    alert: alarmAlert(title: title)
                )
                let attributes = AlarmAttributes(
                    presentation: presentation,
                    metadata: MedicationAlarmMetadata(
                        occurrenceIDs: doses.map(\.occurrenceID)
                    ),
                    tintColor: Color(red: 0.14, green: 0.48, blue: 0.29)
                )
                let configuration = AlarmManager.AlarmConfiguration.alarm(
                    schedule: .fixed(deliveryDate),
                    attributes: attributes
                )

                do {
                    _ = try await AlarmManager.shared.schedule(
                        id: id,
                        configuration: configuration
                    )
                } catch AlarmManager.AlarmError.maximumLimitReached {
                    break
                }
                scheduledIdentifiers.append(id)
                if nextDeliveryDate == nil {
                    nextDeliveryDate = deliveryDate
                }
            }
        } catch {
            persistAlarmIdentifiers(scheduledIdentifiers)
            throw error
        }

        persistAlarmIdentifiers(scheduledIdentifiers)
        return NotificationScheduleSummary(
            scheduledCount: scheduledIdentifiers.count,
            nextDeliveryDate: nextDeliveryDate
        )
    }

    @available(iOS 26.0, *)
    private func alarmAlert(title: String) -> AlarmPresentation.Alert {
        let localizedTitle = LocalizedStringResource(stringLiteral: title)
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: localizedTitle)
        }
        return AlarmPresentation.Alert(
            title: localizedTitle,
            stopButton: AlarmButton(
                text: "停止",
                textColor: .white,
                systemImageName: "stop.fill"
            )
        )
    }

    @available(iOS 26.0, *)
    private func alarmTitle(for doses: [ScheduledDose]) -> String {
        let doseText = doses.prefix(3).map {
            "\($0.medication.name) \($0.amount.displayText)\($0.medication.unit.displayName)"
        }.joined(separator: "、")
        let remainder = doses.count > 3 ? "等 \(doses.count) 项" : ""
        return "服药提醒：\(doseText)\(remainder)"
    }

    @available(iOS 26.0, *)
    private func storedAlarmIdentifiers() -> [UUID] {
        (userDefaults.stringArray(forKey: alarmIdentifierStorageKey) ?? [])
            .compactMap(UUID.init(uuidString:))
    }
    #endif

    private func persistAlarmIdentifiers(_ identifiers: [UUID]) {
        userDefaults.set(
            identifiers.map(\.uuidString),
            forKey: alarmIdentifierStorageKey
        )
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct MedicationAlarmMetadata: AlarmMetadata {
    let occurrenceIDs: [String]
}
#endif
