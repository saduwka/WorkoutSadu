import SwiftUI

// MARK: - Global Design Tokens

enum AppTheme {
    // Colors
    static let bg          = Color("AppBg")
    static let surface     = Color("AppSurface")
    static let surface2    = Color("AppSurface2")
    static let accent      = Color("AppAccent")       // orange-red
    static let accentWarm  = Color("AppAccentWarm")   // amber
    static let accentGreen = Color("AppAccentGreen")  // mint green
    static let accentBlue  = Color("AppAccentBlue")   // blue
    static let textPrimary = Color("AppTextPrimary")
    static let textMuted   = Color("AppTextMuted")

    // Inline fallbacks (for previews / when assets not set up)
    static let bgFallback          = Color(hex: "#0e0e12")
    static let surfaceFallback     = Color(hex: "#16161d")
    static let surface2Fallback    = Color(hex: "#1e1e28")
    static let accentFallback      = Color(hex: "#ff5c3a")
    static let accentWarmFallback  = Color(hex: "#ffb830")
    static let accentGreenFallback = Color(hex: "#3aff9e")
    static let accentBlueFallback  = Color(hex: "#5b8cff")

    // Typography
    static func displayFont(_ size: CGFloat) -> Font {
        .custom("BebasNeue-Regular", size: size)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Reusable Card Modifier

struct DarkCardModifier: ViewModifier {
    var accentBorder: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(Color(hex: "#16161d"))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(accentBorder ?? Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

extension View {
    func darkCard(accentBorder: Color? = nil) -> some View {
        modifier(DarkCardModifier(accentBorder: accentBorder))
    }
}

// MARK: - Bebas Neue Font helper (falls back gracefully)

struct BebasText: View {
    let text: String
    let size: CGFloat
    var color: Color = Color(hex: "#f0f0f5")

    var body: some View {
        Text(text)
            .font(.custom("BebasNeue-Regular", size: size).leading(.tight))
            .foregroundStyle(color)
    }
}
