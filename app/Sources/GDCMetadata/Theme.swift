import SwiftUI

enum Theme {
    /// Discreet accent, shared GDC "Shift" amber/copper family.
    static let accent = Color(red: 0.86, green: 0.55, blue: 0.24)
    static let ok = Color(nsColor: .systemGreen)
    static let warn = Color(nsColor: .systemOrange)
    static let muted = Color.secondary
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)
    static let labelWidth: CGFloat = 168
    static let pad: CGFloat = 12
}

extension View {
    func mono() -> some View { self.font(.system(.body, design: .default).monospacedDigit()) }
}
