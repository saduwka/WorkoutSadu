import SwiftUI

enum WatchTheme {
    static let bg = Color.black
    static let surface = Color(hex: "#16161d")
    static let textPrimary = Color(hex: "#f0f0f5")
    static let textMuted = Color(hex: "#6b6b80")
    static let accent = Color(hex: "#ff5c3a")
    static let success = Color(hex: "#3aff9e")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Display Font

struct WatchDisplayText: View {
    let text: String
    let size: CGFloat
    var color: Color = WatchTheme.textPrimary
    var uppercased: Bool = false

    var body: some View {
        Text(uppercased ? text.uppercased() : text)
            .font(.custom("BebasNeue-Regular", size: size))
            .foregroundStyle(color)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Primary Button

struct WatchPrimaryButton: View {
    let title: String
    let action: () -> Void
    var darkText: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(darkText ? Color.black : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(WatchTheme.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

