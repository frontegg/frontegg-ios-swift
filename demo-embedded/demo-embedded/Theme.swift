import SwiftUI

// MARK: - Colors
extension Color {
    static let textColor = Color(hex: "373739")
    static let primaryColor = Color(hex: "4D7DFA")
    static let backgroundColor = Color(hex: "F9FAFC")
    static let grayColor = Color(hex: "E6E8EC")
    static let gray700 = Color(hex: "7A7C81")
    static let gray600 = Color(hex: "616161")
    static let gray400 = Color(hex: "C3C5CA")
    static let gray200 = Color(hex: "E6E8EC")
    static let greenBackground = Color(hex: "E8FEE0")
    static let greenForeground = Color(hex: "4DA82D")
    static let redBackground = Color(hex: "FF8A80")
    static let redForeground = Color(hex: "F44336")
}

// MARK: - Font Styles
extension Font {
    static let headlineMedium = Font.custom("Manrope", size: 32).weight(.bold)
    static let headlineSmall = Font.custom("Manrope", size: 26).weight(.semibold)
    static let bodyLarge = Font.custom("Manrope", size: 16).weight(.regular)
    static let bodyMedium = Font.custom("Manrope", size: 14).weight(.regular)
    static let bodySmall = Font.custom("Manrope", size: 12).weight(.semibold)
}

// MARK: - Button Style
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.primaryColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.vertical, 9)
            .font(.bodyLarge.weight(.semibold))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Card Style
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.26), radius: 15, x: 0, y: 0)
    }
}

// MARK: - View Extensions
extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
} 
