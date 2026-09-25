import SwiftUI

enum DoseFlowTheme {
    static let accent = Color(red: 0.14, green: 0.48, blue: 0.29)
    static let accentPressed = Color(red: 0.11, green: 0.39, blue: 0.23)
    static let softAccent = Color(red: 0.91, green: 0.96, blue: 0.93)
    static let warning = Color(red: 1.0, green: 0.95, blue: 0.84)

    static let sectionTitle = Font.system(size: 22, weight: .bold, design: .rounded)
    static let cardTitle = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let actionTitle = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let amount = Font.system(size: 21, weight: .bold, design: .rounded)
}

struct DoseFlowCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 8, x: 0, y: 3)
    }
}
