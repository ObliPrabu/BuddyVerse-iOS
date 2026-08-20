import SwiftUI

// Small shared helper so game screens can carry over the Android layouts'
// exact hex background/accent colors (e.g. "#1A237E") instead of guessing
// the closest system color. Defined once here rather than per-file since
// Swift extensions on the same type can't be redeclared across files in one
// module.
extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, opacity: opacity)
    }
}
