import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: DoseFlowStore

    private var sortedLogs: [DoseLog] {
        store.logs.sorted { $0.scheduledAt > $1.scheduledAt }
    }

    var body: some View {
        Group {
            if sortedLogs.isEmpty {
                ContentUnavailableView(
                    "还没有服药记录",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("在“今日”页面记录已服用或跳过后，会显示在这里。")
                )
            } else {
                List(sortedLogs) { log in
                    HStack(spacing: 12) {
                        Image(systemName: log.status == .taken ? "checkmark.circle.fill" : "minus.circle.fill")
                            .foregroundStyle(log.status == .taken ? DoseFlowTheme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(log.medicationName)
                                .font(.headline)
                            Text(log.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(log.actualAmount.displayText) \(log.medicationUnit.displayName)")
                                .fontWeight(.medium)
                            Text(log.status == .taken ? "已服用" : "已跳过")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("服药记录")
    }
}
