import SwiftUI

// Colors from the mood board, named by what they are used for.
// Defined once here; every screen uses these names, never raw hex.
extension Color {
    static let canvas = Color(hex: 0xEEF6FA)
    static let surface = Color(hex: 0xFFFFFF)
    static let textPrimary = Color(hex: 0x0F1A14)
    static let textSecondary = Color(hex: 0x5A6B66)
    static let action = Color(hex: 0x93D94E)
    static let textOnAction = Color(hex: 0x13260C)
    static let actionSubtle = Color(hex: 0x93D94E).opacity(0.20)
    static let caution = Color(hex: 0xC2410C)
    static let cautionSubtle = Color(hex: 0xF07A3A).opacity(0.16)
    static let border = Color(hex: 0x0F1A14).opacity(0.08)
    static let textOnPhoto = Color.white
    static let paper = Color(hex: 0xF6EFE1)

    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// Corner radius: 10 / 16 / 28 / capsule.
enum Radius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 16
    static let large: CGFloat = 28
}
