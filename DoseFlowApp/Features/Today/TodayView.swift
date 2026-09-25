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

            reminderBanner
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: 72)
                .allowsHitTesting(false)
        }
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

    private var reminderBanner: some View {
        Group {
            if store.remindersEnabled {
                Label(
                    store.reminderScheduleText ?? "用药提醒已开启",
                    systemImage: store.strongAlarmsEnabled
                        ? "alarm.waves.left.and.right.fill"
                        : "bell.badge.fill"
                )
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DoseFlowTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DoseFlowTheme.softAccent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Button {
                    Task { await store.setRemindersEnabled(true) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.slash.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("用药提醒未开启")
                                .font(DoseFlowTheme.cardTitle)
                            Text("点击开启，否则到点不会发送通知")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                        }
                        Spacer()
                        Text("开启")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
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
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? DoseFlowTheme.accent : Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
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
                        .font(DoseFlowTheme.cardTitle)
                    ForEach(changed) { change in
                        Text(changeDescription(change))
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                    }
                }
            }
            .foregroundStyle(Color.brown)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DoseFlowTheme.warning)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }

    private func scheduleHeader(_ schedule: DailySchedule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.selectedDate.formatted(date: .complete, time: .omitted))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(store.regimen.name)
                    .font(DoseFlowTheme.sectionTitle)
            }
            Spacer()
            HStack(spacing: 8) {
                Text(completionText(schedule))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DoseFlowTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DoseFlowTheme.softAccent)
                    .clipShape(Capsule())

                Menu {
                    Button("跳过未完成药物", role: .destructive) {
                        showingSkipConfirmation = true
                    }
                    .disabled(schedule.doses.allSatisfy { store.log(for: $0.occurrenceID) != nil })

                    Button("撤销当天记录", systemImage: "arrow.uturn.backward") {
                        store.clearLogs(for: schedule)
                    }
                    .disabled(!hasAnyLog(schedule))
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(Circle())
                }
                .accessibilityLabel("更多当天操作")
            }
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
                        .font(DoseFlowTheme.cardTitle)
                    doseStatusLine(dose, log: log, deferral: deferral)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(dose.amount.displayText) \(dose.medication.unit.displayName)")
                        .font(DoseFlowTheme.amount)
                        .monospacedDigit()

                    if log?.status == .taken {
                        Label("已服用", systemImage: "checkmark")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DoseFlowTheme.accent)
                    } else {
                        Button(log?.status == .skipped ? "改为已服用" : "完成") {
                            store.markTaken(dose)
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DoseFlowTheme.accent)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(DoseFlowTheme.softAccent)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
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
        .font(.system(size: 13, weight: .regular, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private func primaryActions(_ schedule: DailySchedule) -> some View {
        let remainingCount = remainingDoses(in: schedule).count

        return VStack(spacing: 12) {
            Button {
                store.markRemainingTaken(schedule)
            } label: {
                ZStack {
                    Text(primaryActionTitle(schedule, remainingCount: remainingCount))
                        .font(DoseFlowTheme.actionTitle)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(DoseFlowTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(remainingCount == 0)
            .opacity(remainingCount == 0 ? 0.45 : 1)
        }
    }

    private var safetyNote: some View {
        Label(
            "药序只记录和提醒已确认的计划，不提供诊断或漏服后的剂量建议。",
            systemImage: "shield.checkered"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
        .padding(.bottom, 8)
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
