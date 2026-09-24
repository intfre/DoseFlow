import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var store: DoseFlowStore
    @State private var showingEditor = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.regimen.name)
                        .font(.title3.weight(.semibold))
                    Text("从 \(store.regimen.startDate.formatted(date: .long, time: .omitted)) 开始")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("周期安排") {
                ForEach(store.regimen.scheduleGroups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(group.name)
                                .font(.headline)
                            Spacer()
                            Text(group.intervalDays == 1 ? "每天" : "每 \(group.intervalDays) 天")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DoseFlowTheme.accent)
                        }

                        ForEach(group.occurrences) { occurrence in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.occurrences.count == 1 ? "固定剂量" : "第 \(occurrence.sequenceNumber) 次服用")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(occurrence.doses) { dose in
                                    if let medication = store.regimen.medications.first(where: { $0.id == dose.medicationID }) {
                                        HStack {
                                            Text("\(dose.time.displayText)  \(medication.name)")
                                            Spacer()
                                            Text("\(dose.amount.displayText) \(medication.unit.displayName)")
                                                .fontWeight(.medium)
                                        }
                                        .font(.subheadline)
                                    }
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }

            Section("提醒") {
                Toggle(
                    "本地用药提醒",
                    isOn: Binding(
                        get: { store.remindersEnabled },
                        set: { newValue in
                            Task { await store.setRemindersEnabled(newValue) }
                        }
                    )
                )
                Text("开启后会按当前计划安排未来30天内最近60条提醒；多药情况下会在每次打开 App 或修改计划时向后滚动刷新。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("编辑疗程计划") {
                    showingEditor = true
                }
            } footer: {
                Text("修改计划会创建新版本，只影响新计划开始日期之后的安排，已有服药记录仍会保留。")
            }
        }
        .navigationTitle("疗程计划")
        .sheet(isPresented: $showingEditor) {
            RegimenEditorView(regimen: store.regimen) { updatedRegimen in
                await store.saveRegimen(updatedRegimen)
            }
        }
    }
}
