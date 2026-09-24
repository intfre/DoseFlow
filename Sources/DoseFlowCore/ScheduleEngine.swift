import Foundation

public struct ScheduledDose: Identifiable, Hashable, Sendable {
    public var id: String { occurrenceID }
    public let occurrenceID: String
    public let plannedDoseID: UUID
    public let medication: Medication
    public let amount: DoseAmount
    public let time: DoseTime
    public let mealRelation: MealRelation
    public let scheduledAt: Date
    public let scheduleGroupID: UUID
    public let scheduleGroupName: String
    public let occurrenceNumber: Int
    public let cycleStepNumber: Int
    public let cycleStepCount: Int
}

public struct DailySchedule: Hashable, Sendable {
    public let date: Date
    public let doses: [ScheduledDose]
}

public enum DoseChangeDirection: String, Hashable, Sendable {
    case increased
    case decreased
    case unchanged
    case added
    case removed
}

public struct DoseChange: Identifiable, Hashable, Sendable {
    public var id: String {
        "\(medication.id.uuidString)-\(time.hour)-\(time.minute)"
    }

    public let medication: Medication
    public let time: DoseTime
    public let currentAmount: DoseAmount?
    public let previousAmount: DoseAmount?
    public let direction: DoseChangeDirection
}

public struct ScheduleEngine: Sendable {
    public init() {}

    public func schedule(on date: Date, regimen: Regimen) -> DailySchedule? {
        let calendar = calendar(for: regimen)
        let requestedDay = calendar.startOfDay(for: date)
        let startDay = calendar.startOfDay(for: regimen.startDate)

        guard requestedDay >= startDay else { return nil }
        if let endDate = regimen.endDate,
           requestedDay > calendar.startOfDay(for: endDate) {
            return nil
        }

        let medications = Dictionary(uniqueKeysWithValues: regimen.medications.map { ($0.id, $0) })
        let doses = regimen.scheduleGroups.flatMap { group -> [ScheduledDose] in
            let anchorDay = calendar.startOfDay(for: group.anchorDate)
            guard requestedDay >= anchorDay,
                  let groupElapsedDays = calendar.dateComponents(
                    [.day],
                    from: anchorDay,
                    to: requestedDay
                  ).day,
                  groupElapsedDays % group.intervalDays == 0 else {
                return []
            }

            let occurrenceIndex = groupElapsedDays / group.intervalDays
            let template = group.occurrences[occurrenceIndex % group.occurrences.count]

            return template.doses.compactMap { plannedDose -> ScheduledDose? in
                guard let medication = medications[plannedDose.medicationID],
                      let scheduledAt = calendar.date(
                        bySettingHour: plannedDose.time.hour,
                        minute: plannedDose.time.minute,
                        second: 0,
                        of: requestedDay
                      ) else {
                    return nil
                }

                return ScheduledDose(
                    occurrenceID: occurrenceID(
                        for: plannedDose,
                        groupID: group.id,
                        date: requestedDay,
                        calendar: calendar,
                        regimenRevisionID: regimen.revisionID
                    ),
                    plannedDoseID: plannedDose.id,
                    medication: medication,
                    amount: plannedDose.amount,
                    time: plannedDose.time,
                    mealRelation: plannedDose.mealRelation,
                    scheduledAt: scheduledAt,
                    scheduleGroupID: group.id,
                    scheduleGroupName: group.name,
                    occurrenceNumber: occurrenceIndex + 1,
                    cycleStepNumber: template.sequenceNumber,
                    cycleStepCount: group.occurrences.count
                )
            }
        }
        .sorted { ($0.time, $0.medication.name) < ($1.time, $1.medication.name) }

        return DailySchedule(
            date: requestedDay,
            doses: doses
        )
    }

    public func changes(on date: Date, regimen: Regimen) -> [DoseChange] {
        guard let current = schedule(on: date, regimen: regimen) else { return [] }
        let calendar = calendar(for: regimen)
        guard let previousDate = calendar.date(byAdding: .day, value: -1, to: date),
              let previous = schedule(on: previousDate, regimen: regimen) else {
            return current.doses.map {
                DoseChange(
                    medication: $0.medication,
                    time: $0.time,
                    currentAmount: $0.amount,
                    previousAmount: nil,
                    direction: .added
                )
            }
        }

        struct Key: Hashable {
            let medicationID: UUID
            let time: DoseTime
        }

        struct AggregatedDose {
            let medication: Medication
            var amount: DoseAmount
        }

        func aggregate(_ doses: [ScheduledDose]) -> [Key: AggregatedDose] {
            doses.reduce(into: [:]) { result, dose in
                let key = Key(medicationID: dose.medication.id, time: dose.time)
                if let existing = result[key] {
                    result[key] = AggregatedDose(
                        medication: existing.medication,
                        amount: existing.amount + dose.amount
                    )
                } else {
                    result[key] = AggregatedDose(
                        medication: dose.medication,
                        amount: dose.amount
                    )
                }
            }
        }

        let currentByKey = aggregate(current.doses)
        let previousByKey = aggregate(previous.doses)
        let allKeys = Set(currentByKey.keys).union(previousByKey.keys)

        return allKeys.compactMap { key in
            let currentDose = currentByKey[key]
            let previousDose = previousByKey[key]
            guard let medication = currentDose?.medication ?? previousDose?.medication else {
                return nil
            }

            let direction: DoseChangeDirection
            switch (currentDose?.amount, previousDose?.amount) {
            case let (currentAmount?, previousAmount?):
                if currentAmount > previousAmount {
                    direction = .increased
                } else if currentAmount < previousAmount {
                    direction = .decreased
                } else {
                    direction = .unchanged
                }
            case (_?, nil):
                direction = .added
            case (nil, _?):
                direction = .removed
            case (nil, nil):
                return nil
            }

            return DoseChange(
                medication: medication,
                time: key.time,
                currentAmount: currentDose?.amount,
                previousAmount: previousDose?.amount,
                direction: direction
            )
        }
        .sorted { ($0.time, $0.medication.name) < ($1.time, $1.medication.name) }
    }

    public func calendar(for regimen: Regimen) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: regimen.timeZoneIdentifier) ?? .current
        return calendar
    }

    private func occurrenceID(
        for dose: PlannedDose,
        groupID: UUID,
        date: Date,
        calendar: Calendar,
        regimenRevisionID: UUID
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dateKey = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return "\(regimenRevisionID.uuidString):\(dateKey):\(groupID.uuidString):\(dose.id.uuidString)"
    }
}
