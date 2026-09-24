import SwiftUI

enum DoseFlowTheme {
    static let accent = Color(red: 0.14, green: 0.48, blue: 0.29)
    static let softAccent = Color(red: 0.91, green: 0.96, blue: 0.93)
    static let warning = Color(red: 1.0, green: 0.95, blue: 0.84)
}

struct DoseFlowCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
    }
}
