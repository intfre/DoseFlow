import SwiftUI

struct RegimenEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DoseFlowStore

    let existingRegimen: Regimen
    let onSave: (Regimen) async -> Void

    @State private var planName: String
    @State private var startDate: Date
    @State private var medications: [Medication]
    @State private var scheduleGroups: [DoseScheduleGroup]
    @State private var pendingExample: RegimenExample?
    @State private var isSaving = false

    private let engine = ScheduleEngine()

    init(regimen: Regimen, onSave: @escaping (Regimen) async -> Void) {
        existingRegimen = regimen
        self.onSave = onSave
        _planName = State(initialValue: regimen.name)
        _startDate = State(initialValue: regimen.startDate)
        _medications = State(initialValue: regimen.medications)
        _scheduleGroups = State(initialValue: regimen.scheduleGroups)
    }

    var body: some View {
        NavigationStack {
            Form {
                howItWorksSection
                examplesSection
                basicsSection
                remindersSection
                medicationsSection

                ForEach(Array(scheduleGroups.indices), id: \.self) { groupIndex in
                    scheduleGroupSection(groupIndex)
                }

                Section {
                    Button {
                        addScheduleGroup()
                    } label: {
                        Label("添加一组独立周期", systemImage: "calendar.badge.plus")
                    }
                }

                previewSection
                safetySection
            }
            .navigationTitle("编辑疗程计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .confirmationDialog(
            pendingExample.map { "套用“\($0.title)”？" } ?? "套用案例？",
            isPresented: Binding(
                get: { pendingExample != nil },
                set: { if !$0 { pendingExample = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("套用并替换当前编辑内容", role: .destructive) {
                if let pendingExample {
                    apply(pendingExample)
                }
                pendingExample = nil
            }
            Button("取消", role: .cancel) {
                pendingExample = nil
            }
        } message: {
            if let pendingExample {
                Text(pendingExample.effect)
            }
        }
    }

    private var howItWorksSection: some View {
        Section("怎么设置") {
            Label("先添加药品，再为不同周期建立独立安排", systemImage: "1.circle")
            Label("“每 N 天一次”决定什么时候吃", systemImage: "2.circle")
            Label("“第 1 次、第 2 次…”决定每次的药和剂量，然后循环", systemImage: "3.circle")
        }
        .font(.subheadline)
    }

    private var examplesSection: some View {
        Section {
            ForEach(RegimenExample.allCases) { example in
                Button {
                    pendingExample = example
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: example.symbol)
                            .font(.title3)
                            .foregroundStyle(DoseFlowTheme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(example.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(example.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("套用")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("快速案例")
        } footer: {
            Text("案例会替换当前草稿，套用后仍可修改药名、时间、剂量和周期。")
        }
    }

    private var basicsSection: some View {
        Section("疗程") {
            TextField("计划名称", text: $planName)
            DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle(
                "保存后按计划时间提醒",
                isOn: Binding(
                    get: { store.remindersEnabled },
                    set: { enabled in
                        Task { await store.setRemindersEnabled(enabled) }
                    }
                )
            )

            if store.remindersEnabled {
                Label(
                    store.reminderScheduleText ?? "提醒已开启，保存后会按新计划重新安排",
                    systemImage: "bell.badge.fill"
                )
                .font(.footnote)
                .foregroundStyle(DoseFlowTheme.accent)
            } else {
                Label(
                    "仅设置服药时间不会自动发送通知，需要同时开启此开关。",
                    systemImage: "bell.slash.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            if store.supportsStrongAlarms {
                Toggle(
                    "使用强提醒闹钟",
                    isOn: Binding(
                        get: { store.strongAlarmsEnabled },
                        set: { enabled in
                            Task { await store.setStrongAlarmsEnabled(enabled) }
                        }
                    )
                )
                .disabled(!store.remindersEnabled)

                Text("强提醒使用系统闹钟界面和声音；同一时间的多种药只会响一次。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("用药提醒")
        }
    }

    private var medicationsSection: some View {
        Section {
            ForEach($medications) { $medication in
                VStack(alignment: .leading, spacing: 10) {
                    TextField("药品名称", text: $medication.name)
                    TextField("规格，例如 10 mg/片", text: $medication.strength)
                    Picker("计量单位", selection: $medication.unit) {
                        ForEach(DoseUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: deleteMedications)

            Button {
                medications.append(Medication(name: "新药品"))
            } label: {
                Label("添加药品", systemImage: "plus")
            }
        } header: {
            Text("药品")
        } footer: {
            Text("左滑可删除药品；至少保留一种。")
        }
    }

    private func scheduleGroupSection(_ groupIndex: Int) -> some View {
        Section {
            TextField("安排名称，例如早间用药", text: $scheduleGroups[groupIndex].name)

            Stepper(value: $scheduleGroups[groupIndex].intervalDays, in: 1...30) {
                HStack {
                    Text("服用间隔")
                    Spacer()
                    Text(intervalDescription(scheduleGroups[groupIndex].intervalDays))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(scheduleGroups[groupIndex].occurrences.indices), id: \.self) { occurrenceIndex in
                occurrenceEditor(groupIndex: groupIndex, occurrenceIndex: occurrenceIndex)
            }

            Button {
                addOccurrence(to: groupIndex)
            } label: {
                Label("添加下一次剂量", systemImage: "arrow.triangle.2.circlepath")
            }

            if scheduleGroups.count > 1 {
                Button("删除这组安排", role: .destructive) {
                    scheduleGroups.remove(at: groupIndex)
                    normalizeSequenceNumbers()
                }
            }
        } header: {
            Text("周期安排 \(groupIndex + 1)")
        } footer: {
            let group = scheduleGroups[groupIndex]
            Text(groupEffectDescription(group))
        }
    }

    private func occurrenceEditor(groupIndex: Int, occurrenceIndex: Int) -> some View {
        DisclosureGroup {
            ForEach(Array(scheduleGroups[groupIndex].occurrences[occurrenceIndex].doses.indices), id: \.self) { doseIndex in
                doseEditor(
                    groupIndex: groupIndex,
                    occurrenceIndex: occurrenceIndex,
                    doseIndex: doseIndex
                )
            }

            Button {
                addDose(groupIndex: groupIndex, occurrenceIndex: occurrenceIndex)
            } label: {
                Label("添加一项药物或时间", systemImage: "plus.circle")
            }

            if scheduleGroups[groupIndex].occurrences.count > 1 {
                Button("删除这次剂量", role: .destructive) {
                    scheduleGroups[groupIndex].occurrences.remove(at: occurrenceIndex)
                    normalizeSequenceNumbers(in: groupIndex)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("第 \(occurrenceIndex + 1) 次服用")
                    .font(.headline)
                Text(occurrenceSummary(groupIndex: groupIndex, occurrenceIndex: occurrenceIndex))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func doseEditor(
        groupIndex: Int,
        occurrenceIndex: Int,
        doseIndex: Int
    ) -> some View {
        let dose = $scheduleGroups[groupIndex].occurrences[occurrenceIndex].doses[doseIndex]

        return VStack(alignment: .leading, spacing: 8) {
            Picker("药品", selection: dose.medicationID) {
                ForEach(medications) { medication in
                    Text(medication.name.isEmpty ? "未命名药品" : medication.name)
                        .tag(medication.id)
                }
            }

            DatePicker(
                "时间",
                selection: timeBinding(for: dose),
                displayedComponents: .hourAndMinute
            )

            Stepper(value: amountBinding(for: dose), in: 1...80) {
                HStack {
                    Text("剂量")
                    Spacer()
                    Text(doseAmountText(dose.wrappedValue))
                        .foregroundStyle(.secondary)
                }
            }

            Picker("与进餐关系", selection: dose.mealRelation) {
                ForEach(MealRelation.allCases, id: \.self) { relation in
                    Text(relation.displayName.isEmpty ? "不指定" : relation.displayName)
                        .tag(relation)
                }
            }

            if scheduleGroups[groupIndex].occurrences[occurrenceIndex].doses.count > 1 {
                Button("删除这项用药", role: .destructive) {
                    scheduleGroups[groupIndex].occurrences[occurrenceIndex].doses.remove(at: doseIndex)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var previewSection: some View {
        Section {
            if !isValid {
                Label("完善药品和周期安排后，这里会显示实际效果。", systemImage: "eye.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(previewDays) { preview in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(preview.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                            .font(.subheadline.weight(.semibold))
                        if preview.doses.isEmpty {
                            Text("无需服药")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(preview.doses) { dose in
                                Text("\(dose.time.displayText)  \(dose.medication.name)  \(dose.amount.displayText)\(dose.medication.unit.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        } header: {
            Text("未来 10 天效果预览")
        } footer: {
            Text("预览从疗程开始日期起计算，可在保存前核对“哪天、几点、吃什么、吃多少”。")
        }
    }

    private var safetySection: some View {
        Section {
            Label(
                "请以医生或药师确认的医嘱为准；应用只记录和提醒，不自动建议补服剂量。",
                systemImage: "exclamationmark.shield"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var isValid: Bool {
        let medicationIDs = Set(medications.map(\.id))
        return !planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !medications.isEmpty
            && medications.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && !scheduleGroups.isEmpty
            && scheduleGroups.allSatisfy { group in
                !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && group.intervalDays > 0
                    && !group.occurrences.isEmpty
                    && group.occurrences.allSatisfy { occurrence in
                        !occurrence.doses.isEmpty
                            && occurrence.doses.allSatisfy { medicationIDs.contains($0.medicationID) }
                    }
            }
    }

    private var draftRegimen: Regimen? {
        guard isValid else { return nil }
        return makeRegimen(newRevision: false)
    }

    private var previewDays: [PreviewDay] {
        guard let regimen = draftRegimen else { return [] }
        let calendar = engine.calendar(for: regimen)
        let start = calendar.startOfDay(for: regimen.startDate)
        return (0..<10).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start),
                  let schedule = engine.schedule(on: date, regimen: regimen) else {
                return nil
            }
            return PreviewDay(date: date, doses: schedule.doses)
        }
    }

    private func save() async {
        guard isValid else { return }
        isSaving = true
        await onSave(makeRegimen(newRevision: true))
        dismiss()
    }

    private func makeRegimen(newRevision: Bool) -> Regimen {
        let normalizedMedications = medications.map {
            Medication(
                id: $0.id,
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                strength: $0.strength.trimmingCharacters(in: .whitespacesAndNewlines),
                unit: $0.unit
            )
        }
        let anchor = Calendar.current.startOfDay(for: startDate)
        let normalizedGroups = scheduleGroups.enumerated().map { _, group in
            DoseScheduleGroup(
                id: group.id,
                name: group.name.trimmingCharacters(in: .whitespacesAndNewlines),
                anchorDate: anchor,
                intervalDays: group.intervalDays,
                occurrences: group.occurrences.enumerated().map { index, occurrence in
                    DoseOccurrenceTemplate(
                        id: occurrence.id,
                        sequenceNumber: index + 1,
                        doses: occurrence.doses
                    )
                }
            )
        }

        return Regimen(
            id: existingRegimen.id,
            revisionID: newRevision ? UUID() : existingRegimen.revisionID,
            name: planName.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: anchor,
            endDate: existingRegimen.endDate,
            timeZoneIdentifier: TimeZone.current.identifier,
            medications: normalizedMedications,
            scheduleGroups: normalizedGroups,
            createdAt: existingRegimen.createdAt
        )
    }

    private func apply(_ example: RegimenExample) {
        let regimen = example.makeRegimen(startDate: startDate)
        planName = regimen.name
        medications = regimen.medications
        scheduleGroups = regimen.scheduleGroups
    }

    private func addScheduleGroup() {
        guard let medication = medications.first else { return }
        let number = scheduleGroups.count + 1
        scheduleGroups.append(
            DoseScheduleGroup(
                name: "周期安排 \(number)",
                anchorDate: startDate,
                intervalDays: 1,
                occurrences: [
                    DoseOccurrenceTemplate(
                        sequenceNumber: 1,
                        doses: [defaultDose(for: medication.id)]
                    )
                ]
            )
        )
    }

    private func addOccurrence(to groupIndex: Int) {
        let previousDoses = scheduleGroups[groupIndex].occurrences.last?.doses ?? []
        let doses = previousDoses.map {
            PlannedDose(
                medicationID: $0.medicationID,
                amount: $0.amount,
                time: $0.time,
                mealRelation: $0.mealRelation
            )
        }
        let fallbackDoses = medications.first.map { [defaultDose(for: $0.id)] } ?? []
        scheduleGroups[groupIndex].occurrences.append(
            DoseOccurrenceTemplate(
                sequenceNumber: scheduleGroups[groupIndex].occurrences.count + 1,
                doses: doses.isEmpty ? fallbackDoses : doses
            )
        )
    }

    private func addDose(groupIndex: Int, occurrenceIndex: Int) {
        guard let medication = medications.first else { return }
        scheduleGroups[groupIndex].occurrences[occurrenceIndex].doses.append(
            defaultDose(for: medication.id)
        )
    }

    private func defaultDose(for medicationID: UUID) -> PlannedDose {
        PlannedDose(
            medicationID: medicationID,
            amount: DoseAmount(numerator: 1),
            time: DoseTime(hour: 8, minute: 0),
            mealRelation: .none
        )
    }

    private func deleteMedications(at offsets: IndexSet) {
        guard medications.count - offsets.count >= 1 else { return }
        let deletedIDs = Set(offsets.map { medications[$0].id })
        medications.remove(atOffsets: offsets)
        guard let replacementID = medications.first?.id else { return }

        for groupIndex in scheduleGroups.indices {
            for occurrenceIndex in scheduleGroups[groupIndex].occurrences.indices {
                for doseIndex in scheduleGroups[groupIndex].occurrences[occurrenceIndex].doses.indices
                where deletedIDs.contains(scheduleGroups[groupIndex].occurrences[occurrenceIndex].doses[doseIndex].medicationID) {
                    let oldDose = scheduleGroups[groupIndex].occurrences[occurrenceIndex].doses[doseIndex]
                    scheduleGroups[groupIndex].occurrences[occurrenceIndex].doses[doseIndex] = PlannedDose(
                        id: oldDose.id,
                        medicationID: replacementID,
                        amount: oldDose.amount,
                        time: oldDose.time,
                        mealRelation: oldDose.mealRelation
                    )
                }
            }
        }
    }

    private func normalizeSequenceNumbers() {
        for groupIndex in scheduleGroups.indices {
            normalizeSequenceNumbers(in: groupIndex)
        }
    }

    private func normalizeSequenceNumbers(in groupIndex: Int) {
        for occurrenceIndex in scheduleGroups[groupIndex].occurrences.indices {
            scheduleGroups[groupIndex].occurrences[occurrenceIndex].sequenceNumber = occurrenceIndex + 1
        }
    }

    private func timeBinding(for dose: Binding<PlannedDose>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: dose.wrappedValue.time.hour,
                    minute: dose.wrappedValue.time.minute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                dose.wrappedValue.time = DoseTime(
                    hour: components.hour ?? 8,
                    minute: components.minute ?? 0
                )
            }
        )
    }

    private func amountBinding(for dose: Binding<PlannedDose>) -> Binding<Int> {
        Binding(
            get: { max(1, Int((dose.wrappedValue.amount.doubleValue * 4).rounded())) },
            set: { dose.wrappedValue.amount = DoseAmount(quarterUnits: max(1, $0)) }
        )
    }

    private func doseAmountText(_ dose: PlannedDose) -> String {
        let unit = medications.first(where: { $0.id == dose.medicationID })?.unit.displayName ?? ""
        return "\(dose.amount.displayText) \(unit)"
    }

    private func intervalDescription(_ days: Int) -> String {
        days == 1 ? "每天" : "每 \(days) 天一次"
    }

    private func occurrenceSummary(groupIndex: Int, occurrenceIndex: Int) -> String {
        scheduleGroups[groupIndex].occurrences[occurrenceIndex].doses.map { dose in
            let medication = medications.first(where: { $0.id == dose.medicationID })
            return "\(dose.time.displayText) \(medication?.name ?? "未知药品") \(dose.amount.displayText)\(medication?.unit.displayName ?? "")"
        }
        .joined(separator: "、")
    }

    private func groupEffectDescription(_ group: DoseScheduleGroup) -> String {
        let interval = intervalDescription(group.intervalDays)
        let cycle = group.occurrences.count == 1
            ? "固定使用同一组剂量"
            : "按 \(group.occurrences.count) 种剂量依次循环"
        return "效果：\(interval)，\(cycle)。"
    }
}

private struct PreviewDay: Identifiable {
    var id: Date { date }
    let date: Date
    let doses: [ScheduledDose]
}

private enum RegimenExample: String, CaseIterable, Identifiable {
    case fixedMorningEvening
    case dailyAlternating
    case everyThreeDaysAlternating
    case independentMedicationCycles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixedMorningEvening: "每天早晚固定"
        case .dailyAlternating: "每天 0.5 / 1 片交替"
        case .everyThreeDaysAlternating: "每 3 天一次，0.5 / 1 片交替"
        case .independentMedicationCycles: "多种药不同周期"
        }
    }

    var summary: String {
        switch self {
        case .fixedMorningEvening:
            "一天两个时间，每天重复相同剂量"
        case .dailyAlternating:
            "今天 0.5 片，明天 1 片，后天回到 0.5 片"
        case .everyThreeDaysAlternating:
            "服药日之间间隔 2 个空白日，每次剂量交替"
        case .independentMedicationCycles:
            "药 A 每天吃，药 B 每 3 天吃，到期自动合并"
        }
    }

    var effect: String {
        switch self {
        case .fixedMorningEvening:
            "将创建 1 种药、1 组“每天”安排，每次包含 08:00 和 20:00 两项用药。"
        case .dailyAlternating:
            "将创建 1 组“每天”安排，第 1 次 0.5 片、第 2 次 1 片，之后循环。"
        case .everyThreeDaysAlternating:
            "将创建 1 组“每 3 天一次”安排，第 1 次 0.5 片、第 2 次 1 片，之后循环。"
        case .independentMedicationCycles:
            "将创建两组独立安排：药 A 每天 1 片，药 B 每 3 天 0.5 片。"
        }
    }

    var symbol: String {
        switch self {
        case .fixedMorningEvening: "sun.and.horizon"
        case .dailyAlternating: "arrow.left.arrow.right"
        case .everyThreeDaysAlternating: "calendar.badge.clock"
        case .independentMedicationCycles: "square.stack.3d.up"
        }
    }

    func makeRegimen(startDate: Date) -> Regimen {
        let anchor = Calendar.current.startOfDay(for: startDate)
        let time0800 = DoseTime(hour: 8, minute: 0)
        let time2000 = DoseTime(hour: 20, minute: 0)

        switch self {
        case .fixedMorningEvening:
            let medication = Medication(name: "药 A", strength: "10 mg/片")
            return Regimen(
                name: title,
                startDate: anchor,
                medications: [medication],
                scheduleGroups: [
                    DoseScheduleGroup(
                        name: "每日早晚",
                        anchorDate: anchor,
                        intervalDays: 1,
                        occurrences: [
                            DoseOccurrenceTemplate(
                                sequenceNumber: 1,
                                doses: [
                                    PlannedDose(medicationID: medication.id, amount: DoseAmount(numerator: 1), time: time0800, mealRelation: .afterMeal),
                                    PlannedDose(medicationID: medication.id, amount: DoseAmount(numerator: 1), time: time2000, mealRelation: .afterMeal)
                                ]
                            )
                        ]
                    )
                ]
            )

        case .dailyAlternating, .everyThreeDaysAlternating:
            let medication = Medication(name: "药 A", strength: "10 mg/片")
            let interval = self == .dailyAlternating ? 1 : 3
            return Regimen(
                name: title,
                startDate: anchor,
                medications: [medication],
                scheduleGroups: [
                    DoseScheduleGroup(
                        name: self == .dailyAlternating ? "每日交替" : "每3天交替",
                        anchorDate: anchor,
                        intervalDays: interval,
                        occurrences: [
                            DoseOccurrenceTemplate(
                                sequenceNumber: 1,
                                doses: [PlannedDose(medicationID: medication.id, amount: DoseAmount(numerator: 1, denominator: 2), time: time0800, mealRelation: .afterMeal)]
                            ),
                            DoseOccurrenceTemplate(
                                sequenceNumber: 2,
                                doses: [PlannedDose(medicationID: medication.id, amount: DoseAmount(numerator: 1), time: time0800, mealRelation: .afterMeal)]
                            )
                        ]
                    )
                ]
            )

        case .independentMedicationCycles:
            let medicationA = Medication(name: "药 A", strength: "10 mg/片")
            let medicationB = Medication(name: "药 B", strength: "5 mg/片")
            return Regimen(
                name: title,
                startDate: anchor,
                medications: [medicationA, medicationB],
                scheduleGroups: [
                    DoseScheduleGroup(
                        name: "药 A 每天",
                        anchorDate: anchor,
                        intervalDays: 1,
                        occurrences: [
                            DoseOccurrenceTemplate(
                                sequenceNumber: 1,
                                doses: [PlannedDose(medicationID: medicationA.id, amount: DoseAmount(numerator: 1), time: time0800, mealRelation: .afterMeal)]
                            )
                        ]
                    ),
                    DoseScheduleGroup(
                        name: "药 B 每3天",
                        anchorDate: anchor,
                        intervalDays: 3,
                        occurrences: [
                            DoseOccurrenceTemplate(
                                sequenceNumber: 1,
                                doses: [PlannedDose(medicationID: medicationB.id, amount: DoseAmount(numerator: 1, denominator: 2), time: time2000, mealRelation: .afterMeal)]
                            )
                        ]
                    )
                ]
            )
        }
    }
}
