import Combine
import Foundation

@MainActor
final class DoseFlowStore: ObservableObject {
    @Published private(set) var regimen: Regimen
    @Published private(set) var logs: [DoseLog]
    @Published private(set) var deferrals: [DoseDeferral]
    @Published private(set) var remindersEnabled: Bool
    @Published var selectedDate: Date
    @Published var presentedMessage: String?

    private let engine = ScheduleEngine()
    private let userDefaults: UserDefaults?
    private let notificationScheduler = MedicationNotificationScheduler()

    private enum StorageKey {
        static let regimen = "doseflow.regimen.v2"
        static let logs = "doseflow.logs.v1"
        static let deferrals = "doseflow.deferrals.v1"
        static let remindersEnabled = "doseflow.reminders.enabled"
    }

    init(userDefaults: UserDefaults? = .standard) {
        self.userDefaults = userDefaults
        let decoder = JSONDecoder()

        if let data = userDefaults?.data(forKey: StorageKey.regimen),
           let savedRegimen = try? decoder.decode(Regimen.self, from: data) {
            regimen = savedRegimen
        } else {
            regimen = DemoRegimen.make(startDate: Date())
        }

        let loadedLogs: [DoseLog]
        if let data = userDefaults?.data(forKey: StorageKey.logs),
           let savedLogs = try? decoder.decode([DoseLog].self, from: data) {
            loadedLogs = savedLogs
        } else {
            loadedLogs = []
        }
        logs = loadedLogs

        if let data = userDefaults?.data(forKey: StorageKey.deferrals),
           let savedDeferrals = try? decoder.decode([DoseDeferral].self, from: data) {
            let loggedOccurrenceIDs = Set(loadedLogs.map(\.occurrenceID))
            deferrals = savedDeferrals.filter {
                !loggedOccurrenceIDs.contains($0.occurrenceID)
            }
        } else {
            deferrals = []
        }

        remindersEnabled = userDefaults?.bool(forKey: StorageKey.remindersEnabled) ?? false
        selectedDate = Date()
    }

    func schedule(on date: Date) -> DailySchedule? {
        engine.schedule(on: date, regimen: regimen)
    }

    func changes(on date: Date) -> [DoseChange] {
        engine.changes(on: date, regimen: regimen)
    }

    func log(for occurrenceID: String) -> DoseLog? {
        logs.first { $0.occurrenceID == occurrenceID }
    }

    func deferral(for occurrenceID: String) -> DoseDeferral? {
        guard log(for: occurrenceID) == nil else { return nil }
        return deferrals.first { $0.occurrenceID == occurrenceID }
    }

    func markTaken(_ dose: ScheduledDose) {
        upsertLog(for: dose, status: .taken)
        removeDeferral(for: dose.occurrenceID)
        persistLogs()
        persistDeferrals()

        Task {
            await notificationScheduler.cancelScheduledDose(occurrenceID: dose.occurrenceID)
            await notificationScheduler.cancelDeferredDose(occurrenceID: dose.occurrenceID)
        }
    }

    func markRemainingTaken(_ schedule: DailySchedule) {
        let remainingDoses = schedule.doses.filter {
            log(for: $0.occurrenceID) == nil && deferral(for: $0.occurrenceID) == nil
        }
        for dose in remainingDoses {
            upsertLog(for: dose, status: .taken)
        }
        persistLogs()

        Task {
            for dose in remainingDoses {
                await notificationScheduler.cancelScheduledDose(occurrenceID: dose.occurrenceID)
            }
        }
    }

    func markAllSkipped(_ schedule: DailySchedule) {
        let incompleteDoses = schedule.doses.filter { log(for: $0.occurrenceID) == nil }
        for dose in incompleteDoses {
            upsertLog(for: dose, status: .skipped)
            removeDeferral(for: dose.occurrenceID)
        }
        persistLogs()
        persistDeferrals()

        Task {
            for dose in incompleteDoses {
                await notificationScheduler.cancelScheduledDose(occurrenceID: dose.occurrenceID)
                await notificationScheduler.cancelDeferredDose(occurrenceID: dose.occurrenceID)
            }
        }
    }

    func clearLogs(for schedule: DailySchedule) {
        let occurrenceIDs = Set(schedule.doses.map(\.occurrenceID))
        logs.removeAll { occurrenceIDs.contains($0.occurrenceID) }
        persistLogs()

        if remindersEnabled {
            Task { await rescheduleNotifications() }
        }
    }

    func postpone(_ dose: ScheduledDose, by interval: TimeInterval = 60 * 60) async {
        guard interval > 0, log(for: dose.occurrenceID) == nil else { return }

        do {
            let granted = try await notificationScheduler.requestAuthorization()
            guard granted else {
                presentedMessage = "通知权限未开启，无法设置延后提醒。请在系统设置中允许药序发送通知。"
                return
            }
            guard log(for: dose.occurrenceID) == nil else { return }

            let deferral = DoseDeferral(
                occurrenceID: dose.occurrenceID,
                medicationID: dose.medication.id,
                medicationName: dose.medication.name,
                medicationUnit: dose.medication.unit,
                amount: dose.amount,
                originalScheduledAt: dose.scheduledAt,
                remindAt: Date().addingTimeInterval(interval)
            )
            try await notificationScheduler.scheduleDeferredDose(deferral)
            guard log(for: dose.occurrenceID) == nil else {
                await notificationScheduler.cancelDeferredDose(occurrenceID: dose.occurrenceID)
                return
            }
            await notificationScheduler.cancelScheduledDose(occurrenceID: dose.occurrenceID)

            if let index = deferrals.firstIndex(where: { $0.occurrenceID == dose.occurrenceID }) {
                deferrals[index] = deferral
            } else {
                deferrals.append(deferral)
            }
            persistDeferrals()
        } catch {
            presentedMessage = "延后提醒设置失败：\(error.localizedDescription)"
        }
    }

    func saveRegimen(_ updatedRegimen: Regimen) async {
        regimen = updatedRegimen
        persistRegimen()
        deferrals.removeAll()
        persistDeferrals()
        await notificationScheduler.cancelAllDeferredDoseNotifications()
        if remindersEnabled {
            await rescheduleNotifications()
        }
    }

    func setRemindersEnabled(_ enabled: Bool) async {
        if enabled {
            do {
                let granted = try await notificationScheduler.requestAuthorization()
                guard granted else {
                    remindersEnabled = false
                    presentedMessage = "通知权限未开启，请在系统设置中允许药序发送通知。"
                    return
                }
                remindersEnabled = true
                persistReminderPreference()
                await rescheduleNotifications()
            } catch {
                remindersEnabled = false
                presentedMessage = "提醒开启失败：\(error.localizedDescription)"
            }
        } else {
            remindersEnabled = false
            persistReminderPreference()
            deferrals.removeAll()
            persistDeferrals()
            await notificationScheduler.cancelDoseFlowNotifications()
        }
    }

    func refreshNotificationsIfNeeded() async {
        guard remindersEnabled else { return }
        await rescheduleNotifications()
    }

    private func upsertLog(for dose: ScheduledDose, status: DoseLogStatus) {
        if let index = logs.firstIndex(where: { $0.occurrenceID == dose.occurrenceID }) {
            logs[index].status = status
            logs[index].recordedAt = Date()
            logs[index].actualAmount = dose.amount
        } else {
            logs.append(
                DoseLog(
                    occurrenceID: dose.occurrenceID,
                    regimenRevisionID: regimen.revisionID,
                    plannedDoseID: dose.plannedDoseID,
                    medicationID: dose.medication.id,
                    medicationName: dose.medication.name,
                    medicationUnit: dose.medication.unit,
                    scheduledAt: dose.scheduledAt,
                    status: status,
                    actualAmount: dose.amount
                )
            )
        }
    }

    private func removeDeferral(for occurrenceID: String) {
        deferrals.removeAll { $0.occurrenceID == occurrenceID }
    }

    private func rescheduleNotifications() async {
        do {
            let resolvedOccurrenceIDs = Set(logs.map(\.occurrenceID))
                .union(deferrals.map(\.occurrenceID))
            try await notificationScheduler.scheduleNext30Days(
                regimen: regimen,
                engine: engine,
                from: Date(),
                excluding: resolvedOccurrenceIDs
            )
        } catch {
            presentedMessage = "提醒更新失败：\(error.localizedDescription)"
        }
    }

    private func persistRegimen() {
        guard let data = try? JSONEncoder().encode(regimen) else { return }
        userDefaults?.set(data, forKey: StorageKey.regimen)
    }

    private func persistLogs() {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        userDefaults?.set(data, forKey: StorageKey.logs)
    }

    private func persistDeferrals() {
        guard let data = try? JSONEncoder().encode(deferrals) else { return }
        userDefaults?.set(data, forKey: StorageKey.deferrals)
    }

    private func persistReminderPreference() {
        userDefaults?.set(remindersEnabled, forKey: StorageKey.remindersEnabled)
    }
}
