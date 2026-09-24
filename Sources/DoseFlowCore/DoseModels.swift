import Foundation

public struct DoseAmount: Codable, Hashable, Sendable, Comparable {
    public let numerator: Int
    public let denominator: Int

    public init(numerator: Int, denominator: Int = 1) {
        precondition(numerator > 0, "Dose numerator must be positive")
        precondition(denominator > 0, "Dose denominator must be positive")

        let divisor = Self.greatestCommonDivisor(numerator, denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    public init(quarterUnits: Int) {
        self.init(numerator: quarterUnits, denominator: 4)
    }

    public var decimalValue: Decimal {
        Decimal(numerator) / Decimal(denominator)
    }

    public var doubleValue: Double {
        NSDecimalNumber(decimal: decimalValue).doubleValue
    }

    public var displayText: String {
        NSDecimalNumber(decimal: decimalValue).stringValue
    }

    public static func < (lhs: DoseAmount, rhs: DoseAmount) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    public static func + (lhs: DoseAmount, rhs: DoseAmount) -> DoseAmount {
        DoseAmount(
            numerator: lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
            denominator: lhs.denominator * rhs.denominator
        )
    }

    private static func greatestCommonDivisor(_ first: Int, _ second: Int) -> Int {
        var a = first
        var b = second
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return a
    }
}

public enum DoseUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case tablet
    case capsule
    case milliliter
    case drop
    case dose

    public var displayName: String {
        switch self {
        case .tablet: "片"
        case .capsule: "粒"
        case .milliliter: "毫升"
        case .drop: "滴"
        case .dose: "剂"
        }
    }
}

public struct Medication: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var strength: String
    public var unit: DoseUnit

    public init(
        id: UUID = UUID(),
        name: String,
        strength: String = "",
        unit: DoseUnit = .tablet
    ) {
        self.id = id
        self.name = name
        self.strength = strength
        self.unit = unit
    }
}

public struct DoseTime: Codable, Hashable, Sendable, Comparable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        precondition((0...23).contains(hour), "Hour must be between 0 and 23")
        precondition((0...59).contains(minute), "Minute must be between 0 and 59")
        self.hour = hour
        self.minute = minute
    }

    public var displayText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func < (lhs: DoseTime, rhs: DoseTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

public enum MealRelation: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case beforeMeal
    case withMeal
    case afterMeal

    public var displayName: String {
        switch self {
        case .none: ""
        case .beforeMeal: "餐前"
        case .withMeal: "随餐"
        case .afterMeal: "餐后"
        }
    }
}

public struct PlannedDose: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var medicationID: UUID
    public var amount: DoseAmount
    public var time: DoseTime
    public var mealRelation: MealRelation

    public init(
        id: UUID = UUID(),
        medicationID: UUID,
        amount: DoseAmount,
        time: DoseTime,
        mealRelation: MealRelation = .none
    ) {
        self.id = id
        self.medicationID = medicationID
        self.amount = amount
        self.time = time
        self.mealRelation = mealRelation
    }
}

public struct DoseOccurrenceTemplate: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var sequenceNumber: Int
    public var doses: [PlannedDose]

    public init(
        id: UUID = UUID(),
        sequenceNumber: Int,
        doses: [PlannedDose]
    ) {
        precondition(sequenceNumber > 0, "Occurrence sequence must be positive")
        self.id = id
        self.sequenceNumber = sequenceNumber
        self.doses = doses
    }
}

public struct DoseScheduleGroup: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var anchorDate: Date
    public var intervalDays: Int
    public var occurrences: [DoseOccurrenceTemplate]

    public init(
        id: UUID = UUID(),
        name: String,
        anchorDate: Date,
        intervalDays: Int,
        occurrences: [DoseOccurrenceTemplate]
    ) {
        precondition(intervalDays > 0, "Schedule interval must be positive")
        precondition(!occurrences.isEmpty, "A schedule group needs at least one occurrence")
        self.id = id
        self.name = name
        self.anchorDate = anchorDate
        self.intervalDays = intervalDays
        self.occurrences = occurrences.sorted { $0.sequenceNumber < $1.sequenceNumber }
    }
}

public struct Regimen: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let revisionID: UUID
    public var name: String
    public var startDate: Date
    public var endDate: Date?
    public var timeZoneIdentifier: String
    public var medications: [Medication]
    public var scheduleGroups: [DoseScheduleGroup]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        revisionID: UUID = UUID(),
        name: String,
        startDate: Date,
        endDate: Date? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        medications: [Medication],
        scheduleGroups: [DoseScheduleGroup],
        createdAt: Date = Date()
    ) {
        precondition(!scheduleGroups.isEmpty, "A regimen needs at least one schedule group")
        self.id = id
        self.revisionID = revisionID
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.medications = medications
        self.scheduleGroups = scheduleGroups
        self.createdAt = createdAt
    }
}

public enum DoseLogStatus: String, Codable, Hashable, Sendable {
    case taken
    case skipped
}

public struct DoseLog: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let occurrenceID: String
    public let regimenRevisionID: UUID
    public let plannedDoseID: UUID
    public let medicationID: UUID
    public let medicationName: String
    public let medicationUnit: DoseUnit
    public let scheduledAt: Date
    public var status: DoseLogStatus
    public var actualAmount: DoseAmount
    public var recordedAt: Date

    public init(
        id: UUID = UUID(),
        occurrenceID: String,
        regimenRevisionID: UUID,
        plannedDoseID: UUID,
        medicationID: UUID,
        medicationName: String,
        medicationUnit: DoseUnit,
        scheduledAt: Date,
        status: DoseLogStatus,
        actualAmount: DoseAmount,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.occurrenceID = occurrenceID
        self.regimenRevisionID = regimenRevisionID
        self.plannedDoseID = plannedDoseID
        self.medicationID = medicationID
        self.medicationName = medicationName
        self.medicationUnit = medicationUnit
        self.scheduledAt = scheduledAt
        self.status = status
        self.actualAmount = actualAmount
        self.recordedAt = recordedAt
    }
}

public struct DoseDeferral: Identifiable, Codable, Hashable, Sendable {
    public var id: String { occurrenceID }
    public let occurrenceID: String
    public let medicationID: UUID
    public let medicationName: String
    public let medicationUnit: DoseUnit
    public let amount: DoseAmount
    public let originalScheduledAt: Date
    public let remindAt: Date
    public let createdAt: Date

    public init(
        occurrenceID: String,
        medicationID: UUID,
        medicationName: String,
        medicationUnit: DoseUnit,
        amount: DoseAmount,
        originalScheduledAt: Date,
        remindAt: Date,
        createdAt: Date = Date()
    ) {
        self.occurrenceID = occurrenceID
        self.medicationID = medicationID
        self.medicationName = medicationName
        self.medicationUnit = medicationUnit
        self.amount = amount
        self.originalScheduledAt = originalScheduledAt
        self.remindAt = remindAt
        self.createdAt = createdAt
    }
}
