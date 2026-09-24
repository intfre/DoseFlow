import Foundation
import Testing
@testable import DoseFlowCore

struct ScheduleEngineTests {
    private let engine = ScheduleEngine()

    @Test("Daily occurrence cycle advances and wraps")
    func dailyCycleAdvancesAndWraps() throws {
        let start = try date(2026, 9, 23)
        let regimen = DemoRegimen.make(startDate: start)
        let first = try #require(engine.schedule(on: start, regimen: regimen))
        let second = try #require(engine.schedule(on: date(2026, 9, 24), regimen: regimen))
        let third = try #require(engine.schedule(on: date(2026, 9, 25), regimen: regimen))

        #expect(first.doses.first?.cycleStepNumber == 1)
        #expect(second.doses.first?.cycleStepNumber == 2)
        #expect(third.doses.first?.cycleStepNumber == 1)
        #expect(first.doses.first { $0.medication.name == "药 A" }?.amount.displayText == "1")
        #expect(second.doses.first { $0.medication.name == "药 A" }?.amount.displayText == "0.5")
    }

    @Test("每3天一次与0.5/1循环互相独立")
    func everyThreeDaysWithAlternatingAmounts() throws {
        let start = try date(2026, 9, 23)
        let medication = Medication(name: "药 A")
        let regimen = Regimen(
            name: "每3天交替",
            startDate: start,
            medications: [medication],
            scheduleGroups: [
                DoseScheduleGroup(
                    name: "每3天用药",
                    anchorDate: start,
                    intervalDays: 3,
                    occurrences: [
                        occurrence(1, medication: medication, quarterUnits: 2),
                        occurrence(2, medication: medication, quarterUnits: 4)
                    ]
                )
            ]
        )

        let dayOne = try #require(engine.schedule(on: start, regimen: regimen))
        let dayTwo = try #require(engine.schedule(on: date(2026, 9, 24), regimen: regimen))
        let dayThree = try #require(engine.schedule(on: date(2026, 9, 25), regimen: regimen))
        let dayFour = try #require(engine.schedule(on: date(2026, 9, 26), regimen: regimen))
        let daySeven = try #require(engine.schedule(on: date(2026, 9, 29), regimen: regimen))

        #expect(dayOne.doses.first?.amount.displayText == "0.5")
        #expect(dayOne.doses.first?.occurrenceNumber == 1)
        #expect(dayTwo.doses.isEmpty)
        #expect(dayThree.doses.isEmpty)
        #expect(dayFour.doses.first?.amount.displayText == "1")
        #expect(dayFour.doses.first?.occurrenceNumber == 2)
        #expect(daySeven.doses.first?.amount.displayText == "0.5")
        #expect(daySeven.doses.first?.occurrenceNumber == 3)
    }

    @Test("多个独立周期在同一天合并")
    func independentGroupsMerge() throws {
        let start = try date(2026, 9, 23)
        let medicationA = Medication(name: "药 A")
        let medicationB = Medication(name: "药 B")
        let regimen = Regimen(
            name: "多周期",
            startDate: start,
            medications: [medicationA, medicationB],
            scheduleGroups: [
                DoseScheduleGroup(
                    name: "A 每天",
                    anchorDate: start,
                    intervalDays: 1,
                    occurrences: [occurrence(1, medication: medicationA, quarterUnits: 4)]
                ),
                DoseScheduleGroup(
                    name: "B 每3天",
                    anchorDate: start,
                    intervalDays: 3,
                    occurrences: [occurrence(1, medication: medicationB, quarterUnits: 2)]
                )
            ]
        )

        let first = try #require(engine.schedule(on: start, regimen: regimen))
        let second = try #require(engine.schedule(on: date(2026, 9, 24), regimen: regimen))
        let fourth = try #require(engine.schedule(on: date(2026, 9, 26), regimen: regimen))

        #expect(Set(first.doses.map(\.medication.name)) == Set(["药 A", "药 B"]))
        #expect(second.doses.map(\.medication.name) == ["药 A"])
        #expect(Set(fourth.doses.map(\.medication.name)) == Set(["药 A", "药 B"]))
    }

    @Test("A date before regimen start has no schedule")
    func beforeStartHasNoSchedule() throws {
        let regimen = DemoRegimen.make(startDate: try date(2026, 9, 23))
        let result = engine.schedule(on: try date(2026, 9, 22), regimen: regimen)
        #expect(result == nil)
    }

    @Test("Dose changes compare the current plan with the previous calendar day")
    func comparesWithPreviousDay() throws {
        let regimen = DemoRegimen.make(startDate: try date(2026, 9, 23))
        let changes = engine.changes(on: try date(2026, 9, 24), regimen: regimen)
        let medicationA = try #require(changes.first { $0.medication.name == "药 A" })
        let medicationB = try #require(changes.first { $0.medication.name == "药 B" })

        #expect(medicationA.direction == .decreased)
        #expect(medicationA.previousAmount?.displayText == "1")
        #expect(medicationA.currentAmount?.displayText == "0.5")
        #expect(medicationB.direction == .increased)
        #expect(medicationB.previousAmount?.displayText == "0.5")
        #expect(medicationB.currentAmount?.displayText == "1")
    }

    @Test("Cycle progression is stable across daylight saving time")
    func daylightSavingTimeDoesNotShiftCycle() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try date(2026, 3, 7, timeZone: timeZone)
        var regimen = DemoRegimen.make(startDate: start)
        regimen.timeZoneIdentifier = timeZone.identifier
        let beforeChange = try #require(engine.schedule(on: start, regimen: regimen))
        let changeDay = try #require(engine.schedule(on: date(2026, 3, 8, timeZone: timeZone), regimen: regimen))
        let afterChange = try #require(engine.schedule(on: date(2026, 3, 9, timeZone: timeZone), regimen: regimen))

        #expect(beforeChange.doses.first?.cycleStepNumber == 1)
        #expect(changeDay.doses.first?.cycleStepNumber == 2)
        #expect(afterChange.doses.first?.cycleStepNumber == 1)
    }

    @Test("Dose amount uses exact rational values")
    func exactDoseAmount() {
        let half = DoseAmount(numerator: 1, denominator: 2)
        let twoQuarters = DoseAmount(quarterUnits: 2)
        #expect(half == twoQuarters)
        #expect(half.displayText == "0.5")
        #expect((half + half).displayText == "1")
    }

    @Test("A deferred dose can be persisted without losing its reminder time")
    func deferredDoseRoundTrip() throws {
        let scheduledAt = try date(2026, 9, 24)
        let remindAt = scheduledAt.addingTimeInterval(60 * 60)
        let deferral = DoseDeferral(
            occurrenceID: "dose-1",
            medicationID: UUID(),
            medicationName: "药 A",
            medicationUnit: .tablet,
            amount: DoseAmount(numerator: 1, denominator: 2),
            originalScheduledAt: scheduledAt,
            remindAt: remindAt,
            createdAt: scheduledAt
        )
        let data = try JSONEncoder().encode(deferral)
        let restored = try JSONDecoder().decode(DoseDeferral.self, from: data)

        #expect(restored == deferral)
        #expect(restored.remindAt == remindAt)
        #expect(restored.amount.displayText == "0.5")
    }

    private func occurrence(
        _ sequenceNumber: Int,
        medication: Medication,
        quarterUnits: Int
    ) -> DoseOccurrenceTemplate {
        DoseOccurrenceTemplate(
            sequenceNumber: sequenceNumber,
            doses: [
                PlannedDose(
                    medicationID: medication.id,
                    amount: DoseAmount(quarterUnits: quarterUnits),
                    time: DoseTime(hour: 8, minute: 0)
                )
            ]
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }
}
