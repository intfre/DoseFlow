import Foundation

public enum DemoRegimen {
    public static func make(startDate: Date = Date()) -> Regimen {
        let medicationA = Medication(name: "药 A", strength: "10 mg/片")
        let medicationB = Medication(name: "药 B", strength: "5 mg/片")
        let time = DoseTime(hour: 8, minute: 0)

        return Regimen(
            name: "每日剂量交替",
            startDate: startDate,
            medications: [medicationA, medicationB],
            scheduleGroups: [
                DoseScheduleGroup(
                    name: "早间用药",
                    anchorDate: startDate,
                    intervalDays: 1,
                    occurrences: [
                        DoseOccurrenceTemplate(
                            sequenceNumber: 1,
                            doses: [
                                PlannedDose(
                                    medicationID: medicationA.id,
                                    amount: DoseAmount(numerator: 1),
                                    time: time,
                                    mealRelation: .afterMeal
                                ),
                                PlannedDose(
                                    medicationID: medicationB.id,
                                    amount: DoseAmount(numerator: 1, denominator: 2),
                                    time: time,
                                    mealRelation: .afterMeal
                                )
                            ]
                        ),
                        DoseOccurrenceTemplate(
                            sequenceNumber: 2,
                            doses: [
                                PlannedDose(
                                    medicationID: medicationA.id,
                                    amount: DoseAmount(numerator: 1, denominator: 2),
                                    time: time,
                                    mealRelation: .afterMeal
                                ),
                                PlannedDose(
                                    medicationID: medicationB.id,
                                    amount: DoseAmount(numerator: 1),
                                    time: time,
                                    mealRelation: .afterMeal
                                )
                            ]
                        )
                    ]
                )
            ]
        )
    }
}
