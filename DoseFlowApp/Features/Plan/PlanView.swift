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
                if store.remindersEnabled {
                    Label(
                        store.reminderScheduleText ?? "提醒已开启，正在更新安排",
                        systemImage: "bell.badge.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(DoseFlowTheme.accent)

                    Button {
                        Task { await store.sendTestReminder() }
                    } label: {
                        Label("发送测试提醒（5秒后）", systemImage: "bell.and.waves.left.and.right")
                    }
                } else {
                    Text("当前不会发送系统通知。仅在计划中设置服药时间是不够的，还需开启此开关。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if store.supportsStrongAlarms {
                    Toggle(
                        "强提醒闹钟",
                        isOn: Binding(
                            get: { store.strongAlarmsEnabled },
                            set: { newValue in
                                Task { await store.setStrongAlarmsEnabled(newValue) }
                            }
                        )
                    )
                    .disabled(!store.remindersEnabled)

                    Label(
                        store.strongAlarmsEnabled
                            ? "已使用系统闹钟强提醒；同一时间的多种药会合并提醒。"
                            : "适合容易错过通知的情况，开启时需要单独授权。",
                        systemImage: store.strongAlarmsEnabled ? "alarm.waves.left.and.right.fill" : "alarm"
                    )
                    .font(.footnote)
                    .foregroundStyle(store.strongAlarmsEnabled ? DoseFlowTheme.accent : .secondary)

                    if store.strongAlarmsEnabled {
                        Button {
                            Task { await store.sendTestStrongAlarm() }
                        } label: {
                            Label("测试强提醒（10秒后）", systemImage: "alarm.waves.left.and.right")
                        }
                    }
                } else {
                    Label("强提醒闹钟需要 iOS 26 或更高版本", systemImage: "alarm")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
