import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: DoseFlowStore
    @State private var showingSkipConfirmation = false

    private var schedule: DailySchedule? {
        store.schedule(on: store.selectedDate)
    }

    var body: some View {
        List {
            datePicker
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .doseFlowListRow()

            if let schedule {
                comparisonBanner
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .doseFlowListRow()

                scheduleHeader(schedule)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                    .doseFlowListRow()

                if schedule.doses.isEmpty {
                    ContentUnavailableView(
                        "今天无需服药",
                        systemImage: "calendar.badge.checkmark",
                        description: Text("当前周期安排在这一天没有用药项目。")
                    )
                    .padding(.vertical, 24)
                    .doseFlowListRow()
                } else {
                    ForEach(schedule.doses) { dose in
                        doseRow(dose)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if canPostpone(dose) {
                                    Button {
                                        Task { await store.postpone(dose) }
                                    } label: {
                                        Label(
                                            store.deferral(for: dose.occurrenceID) == nil ? "1小时后" : "再延1小时",
                                            systemImage: "clock.arrow.circlepath"
                                        )
                                    }
                                    .tint(.orange)
                                }
                            }
                            .accessibilityAction(named: "1小时后提醒") {
                                if canPostpone(dose) {
                                    Task { await store.postpone(dose) }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .doseFlowListRow()
                    }

                    if schedule.doses.contains(where: canPostpone) {
                        Label("左滑某项，可设置 1 小时后单独提醒", systemImage: "hand.draw")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 16))
                            .doseFlowListRow()
                    }

                    primaryActions(schedule)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .doseFlowListRow()

                    safetyNote
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 24, trailing: 20))
                        .doseFlowListRow()
                }
            } else {
                ContentUnavailableView(
                    "当天没有用药计划",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("该日期早于疗程开始时间，或疗程已经结束。")
                )
                .padding(.top, 48)
                .doseFlowListRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(navigationTitle)
        .confirmationDialog(
            "确定将今天所有药物记为跳过吗？",
            isPresented: $showingSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("记为跳过", role: .destructive) {
                if let schedule { store.markAllSkipped(schedule) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("药序不会自动调整后续剂量；漏服后的处理请遵照医嘱。")
        }
    }

    private var navigationTitle: String {
        "用药安排"
    }

    private var datePicker: some View {
        HStack(spacing: 8) {
            dateButton(offset: -1, title: "昨天")
            dateButton(offset: 0, title: "今天")
            dateButton(offset: 1, title: "明天")
        }
    }

    private func dateButton(offset: Int, title: String) -> some View {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let isSelected = calendar.isDate(date, inSameDayAs: store.selectedDate)

        return Button {
            store.selectedDate = date
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                Text(date.formatted(.dateTime.day()))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? DoseFlowTheme.accent : Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(date.formatted(date: .abbreviated, time: .omitted))")
    }

    @ViewBuilder
    private var comparisonBanner: some View {
        let changed = store.changes(on: store.selectedDate).filter { $0.direction != .unchanged }
        if !changed.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text("与前一天的剂量不同")
                        .font(.headline)
                    ForEach(changed) { change in
                        Text(changeDescription(change))
                            .font(.subheadline)
                    }
                }
            }
            .foregroundStyle(Color.brown)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DoseFlowTheme.warning)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func scheduleHeader(_ schedule: DailySchedule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.selectedDate.formatted(date: .complete, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.regimen.name)
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            Text(completionText(schedule))
                .font(.caption.weight(.medium))
                .foregroundStyle(DoseFlowTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DoseFlowTheme.softAccent)
                .clipShape(Capsule())
        }
    }

    private func doseRow(_ dose: ScheduledDose) -> some View {
        let log = store.log(for: dose.occurrenceID)
        let deferral = store.deferral(for: dose.occurrenceID)

        return DoseFlowCard {
            HStack(spacing: 14) {
                Image(systemName: doseIcon(log: log, deferral: deferral))
                    .font(.title3)
                    .foregroundStyle(doseIconColor(log: log, deferral: deferral))
                    .frame(width: 42, height: 42)
                    .background(doseIconBackground(log: log, deferral: deferral))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(dose.medication.name)
                        .font(.headline)
                    doseStatusLine(dose, log: log, deferral: deferral)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(dose.amount.displayText) \(dose.medication.unit.displayName)")
                        .font(.title3.weight(.semibold))

                    if log?.status == .taken {
                        Label("已服用", systemImage: "checkmark")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DoseFlowTheme.accent)
                    } else {
                        Button(log?.status == .skipped ? "改为已服用" : "完成") {
                            store.markTaken(dose)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(DoseFlowTheme.accent)
                    }
                }
            }
        }
    }

    private func doseStatusLine(
        _ dose: ScheduledDose,
        log: DoseLog?,
        deferral: DoseDeferral?
    ) -> some View {
        HStack(spacing: 6) {
            Text(dose.scheduleGroupName)
            Text("·")
            Text(dose.time.displayText)
            if !dose.mealRelation.displayName.isEmpty {
                Text("· \(dose.mealRelation.displayName)")
            }
            if let deferral {
                Text("· 延后至 \(deferral.remindAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.orange)
            } else if let log {
                Text(log.status == .taken ? "· 已服用" : "· 已跳过")
                    .foregroundStyle(log.status == .taken ? DoseFlowTheme.accent : .secondary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func primaryActions(_ schedule: DailySchedule) -> some View {
        let remainingCount = remainingDoses(in: schedule).count

        return VStack(spacing: 10) {
            Button {
                store.markRemainingTaken(schedule)
            } label: {
                Label(
                    primaryActionTitle(schedule, remainingCount: remainingCount),
                    systemImage: "checkmark.circle.fill"
                )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(DoseFlowTheme.accent)
            .disabled(remainingCount == 0)

            HStack {
                Button("跳过未完成药物", role: .destructive) {
                    showingSkipConfirmation = true
                }
                .disabled(schedule.doses.allSatisfy { store.log(for: $0.occurrenceID) != nil })
                Spacer()
                Button("撤销当天记录") {
                    store.clearLogs(for: schedule)
                }
                .disabled(!hasAnyLog(schedule))
            }
            .font(.subheadline)
        }
    }

    private var safetyNote: some View {
        Label(
            "药序只记录和提醒已确认的计划，不提供诊断或漏服后的剂量建议。",
            systemImage: "shield.checkered"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }

    private func changeDescription(_ change: DoseChange) -> String {
        switch change.direction {
        case .increased:
            "\(change.medication.name)：\(change.previousAmount?.displayText ?? "—") → \(change.currentAmount?.displayText ?? "—")\(change.medication.unit.displayName)"
        case .decreased:
            "\(change.medication.name)：\(change.previousAmount?.displayText ?? "—") → \(change.currentAmount?.displayText ?? "—")\(change.medication.unit.displayName)"
        case .added:
            "新增 \(change.medication.name) \(change.currentAmount?.displayText ?? "—")\(change.medication.unit.displayName)"
        case .removed:
            "当天不服用 \(change.medication.name)"
        case .unchanged:
            "\(change.medication.name) 剂量不变"
        }
    }

    private func hasAnyLog(_ schedule: DailySchedule) -> Bool {
        schedule.doses.contains { store.log(for: $0.occurrenceID) != nil }
    }

    private func canPostpone(_ dose: ScheduledDose) -> Bool {
        Calendar.current.isDateInToday(store.selectedDate)
            && store.log(for: dose.occurrenceID) == nil
    }

    private func remainingDoses(in schedule: DailySchedule) -> [ScheduledDose] {
        schedule.doses.filter {
            store.log(for: $0.occurrenceID) == nil
                && store.deferral(for: $0.occurrenceID) == nil
        }
    }

    private func allTaken(_ schedule: DailySchedule) -> Bool {
        !schedule.doses.isEmpty && schedule.doses.allSatisfy {
            store.log(for: $0.occurrenceID)?.status == .taken
        }
    }

    private func completionText(_ schedule: DailySchedule) -> String {
        if schedule.doses.isEmpty { return "无需服药" }
        if allTaken(schedule) { return "已完成" }
        let deferredCount = schedule.doses.filter {
            store.deferral(for: $0.occurrenceID) != nil
        }.count
        if deferredCount > 0 { return "\(deferredCount) 项已延后" }
        if hasAnyLog(schedule) { return "部分记录" }
        return "待服用"
    }

    private func primaryActionTitle(_ schedule: DailySchedule, remainingCount: Int) -> String {
        if allTaken(schedule) { return "全部已完成" }
        if remainingCount > 0 { return "一键完成剩余 \(remainingCount) 项" }
        return "延后药物可单独完成"
    }

    private func doseIcon(log: DoseLog?, deferral: DoseDeferral?) -> String {
        if log?.status == .taken { return "checkmark.circle.fill" }
        if log?.status == .skipped { return "minus.circle.fill" }
        if deferral != nil { return "clock.badge.fill" }
        return "pill.fill"
    }

    private func doseIconColor(log: DoseLog?, deferral: DoseDeferral?) -> Color {
        if log?.status == .skipped { return .secondary }
        if deferral != nil { return .orange }
        return DoseFlowTheme.accent
    }

    private func doseIconBackground(log: DoseLog?, deferral: DoseDeferral?) -> Color {
        if log?.status == .skipped { return Color(uiColor: .secondarySystemFill) }
        if deferral != nil { return Color.orange.opacity(0.14) }
        return DoseFlowTheme.softAccent
    }
}

private extension View {
    func doseFlowListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
