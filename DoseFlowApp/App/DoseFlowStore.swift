import Combine
import Foundation

@MainActor
final class DoseFlowStore: ObservableObject {
    @Published private(set) var regimen: Regimen
    @Published private(set) var logs: [DoseLog]
    @Published private(set) var deferrals: [DoseDeferral]
    @Published private(set) var remindersEnabled: Bool
    @Published private(set) var strongAlarmsEnabled: Bool
    @Published private(set) var reminderScheduleText: String?
    @Published var selectedDate: Date
    @Published var presentedMessage: String?

    private let engine = ScheduleEngine()
    private let userDefaults: UserDefaults?
    private let notificationScheduler = MedicationNotificationScheduler()
    private let alarmScheduler = MedicationAlarmScheduler()

    private enum StorageKey {
        static let regimen = "doseflow.regimen.v2"
        static let logs = "doseflow.logs.v1"
        static let deferrals = "doseflow.deferrals.v1"
        static let remindersEnabled = "doseflow.reminders.enabled"
        static let strongAlarmsEnabled = "doseflow.alarms.enabled"
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

        let storedRemindersEnabled = userDefaults?.bool(forKey: StorageKey.remindersEnabled) ?? false
        remindersEnabled = storedRemindersEnabled
        if #available(iOS 26.0, *) {
            strongAlarmsEnabled = storedRemindersEnabled
                && (userDefaults?.bool(forKey: StorageKey.strongAlarmsEnabled) ?? false)
        } else {
            strongAlarmsEnabled = false
        }
        reminderScheduleText = nil
        selectedDate = Date()
    }

    var supportsStrongAlarms: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
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
            if strongAlarmsEnabled {
                await rescheduleNotifications()
            }
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
            if strongAlarmsEnabled {
                await rescheduleNotifications()
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
            if strongAlarmsEnabled {
                await rescheduleNotifications()
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
            if strongAlarmsEnabled {
                await rescheduleNotifications()
            }
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
            await rescheduleNotifications(allowCurrentMinute: true)
        } else {
            presentedMessage = "计划已保存，但“本地用药提醒”尚未开启。服药时间只会显示在计划中，开启提醒后才会发送系统通知。"
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
                await rescheduleNotifications(
                    allowCurrentMinute: true,
                    showConfirmation: true
                )
            } catch {
                remindersEnabled = false
                presentedMessage = "提醒开启失败：\(error.localizedDescription)"
            }
        } else {
            remindersEnabled = false
            strongAlarmsEnabled = false
            reminderScheduleText = nil
            persistReminderPreference()
            persistStrongAlarmPreference()
            deferrals.removeAll()
            persistDeferrals()
            await notificationScheduler.cancelDoseFlowNotifications()
            await alarmScheduler.cancelAll()
        }
    }

    func setStrongAlarmsEnabled(_ enabled: Bool) async {
        guard supportsStrongAlarms else {
            strongAlarmsEnabled = false
            presentedMessage = "强提醒闹钟需要 iOS 26 或更高版本。当前系统仍可使用普通用药通知。"
            return
        }

        if enabled {
            guard remindersEnabled else {
                strongAlarmsEnabled = false
                presentedMessage = "请先开启本地用药提醒，再开启强提醒闹钟。"
                return
            }
            do {
                let granted = try await alarmScheduler.requestAuthorization()
                guard granted else {
                    strongAlarmsEnabled = false
                    persistStrongAlarmPreference()
                    presentedMessage = "闹钟权限未开启。请在系统设置中允许药序使用闹钟。"
                    return
                }
                strongAlarmsEnabled = true
                persistStrongAlarmPreference()
                await rescheduleNotifications(
                    allowCurrentMinute: true,
                    showConfirmation: true
                )
            } catch {
                strongAlarmsEnabled = false
                persistStrongAlarmPreference()
                await rescheduleNotifications()
                presentedMessage = "强提醒开启失败，已保留普通通知：\(error.localizedDescription)"
            }
        } else {
            strongAlarmsEnabled = false
            persistStrongAlarmPreference()
            await alarmScheduler.cancelAll()
            if remindersEnabled {
                await rescheduleNotifications(showConfirmation: true)
            }
        }
    }

    func refreshNotificationsIfNeeded() async {
        guard remindersEnabled else { return }
        guard await notificationScheduler.isAuthorized() else {
            remindersEnabled = false
            strongAlarmsEnabled = false
            reminderScheduleText = nil
            persistReminderPreference()
            persistStrongAlarmPreference()
            await alarmScheduler.cancelAll()
            presentedMessage = "系统通知权限已关闭，用药提醒已停止。请先在 iPhone 设置中允许药序发送通知。"
            return
        }

        if strongAlarmsEnabled, !(await alarmScheduler.isAuthorized()) {
            strongAlarmsEnabled = false
            persistStrongAlarmPreference()
            presentedMessage = "闹钟权限已关闭，已自动改用普通用药通知。"
        }
        await rescheduleNotifications()
    }

    func sendTestReminder() async {
        do {
            let granted = try await notificationScheduler.requestAuthorization()
            guard granted else {
                remindersEnabled = false
                strongAlarmsEnabled = false
                reminderScheduleText = nil
                persistReminderPreference()
                persistStrongAlarmPreference()
                await alarmScheduler.cancelAll()
                presentedMessage = "系统通知权限未开启，无法发送测试提醒。"
                return
            }
            try await notificationScheduler.scheduleTestReminder()
            presentedMessage = "测试提醒已安排，将在 5 秒后发送。关闭此弹窗后请保持 App 在前台，也应能看到通知横幅。"
        } catch {
            presentedMessage = "测试提醒设置失败：\(error.localizedDescription)"
        }
    }

    func sendTestStrongAlarm() async {
        guard strongAlarmsEnabled else {
            presentedMessage = "请先开启强提醒闹钟。"
            return
        }
        do {
            let scheduled = try await alarmScheduler.scheduleTestAlarm()
            presentedMessage = scheduled
                ? "测试闹钟已安排，将在 10 秒后响起。"
                : "当前系统不支持强提醒闹钟。"
        } catch {
            presentedMessage = "测试闹钟设置失败：\(error.localizedDescription)"
        }
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

    private func rescheduleNotifications(
        allowCurrentMinute: Bool = false,
        showConfirmation: Bool = false
    ) async {
        do {
            let resolvedOccurrenceIDs = Set(logs.map(\.occurrenceID))
                .union(deferrals.map(\.occurrenceID))
            let summary: NotificationScheduleSummary
            if strongAlarmsEnabled {
                await notificationScheduler.cancelScheduledDoseNotifications()
                summary = try await alarmScheduler.scheduleNext30Days(
                    regimen: regimen,
                    engine: engine,
                    from: Date(),
                    excluding: resolvedOccurrenceIDs,
                    allowCurrentMinute: allowCurrentMinute
                )
            } else {
                await alarmScheduler.cancelAll()
                summary = try await notificationScheduler.scheduleNext30Days(
                    regimen: regimen,
                    engine: engine,
                    from: Date(),
                    excluding: resolvedOccurrenceIDs,
                    allowCurrentMinute: allowCurrentMinute
                )
            }
            reminderScheduleText = (strongAlarmsEnabled ? "强提醒 · " : "") + scheduleText(for: summary)
            if showConfirmation {
                presentedMessage = summary.scheduledCount > 0
                    ? "\(strongAlarmsEnabled ? "强提醒闹钟" : "普通提醒")已开启。\(reminderScheduleText ?? "")"
                    : "提醒已开启，但未来 30 天内没有可安排的服药项目。"
            }
        } catch {
            reminderScheduleText = nil
            presentedMessage = "提醒更新失败：\(error.localizedDescription)"
        }
    }

    private func scheduleText(for summary: NotificationScheduleSummary) -> String {
        guard let nextDeliveryDate = summary.nextDeliveryDate else {
            return "未来 30 天暂无提醒"
        }
        let nextText = nextDeliveryDate.formatted(date: .abbreviated, time: .shortened)
        return "下一次：\(nextText)（已安排 \(summary.scheduledCount) 条）"
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

    private func persistStrongAlarmPreference() {
        userDefaults?.set(strongAlarmsEnabled, forKey: StorageKey.strongAlarmsEnabled)
    }
}
