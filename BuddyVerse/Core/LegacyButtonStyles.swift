import SwiftUI

/// Stand-ins for the built-in `.borderedProminent`/`.bordered` button styles
/// (both iOS 15+) plus `.tint()` (also iOS 15+), needed because the app
/// supports iOS 14+. Neither style sets its own foreground color - exactly
/// like the real `.borderedProminent`/`.bordered`, callers that want
/// something other than the default can still chain their own
/// `.foregroundColor()`/`.foregroundColor()` after `.buttonStyle()` and it
/// wins, since these styles never set one themselves.
///
/// `LegacyProminentButtonStyle` mirrors `.borderedProminent`: a solid fill
/// of `tint`. Real `.borderedProminent` defaults to white text when nothing
/// else is specified - callers relying on that default need to add an
/// explicit `.foregroundColor(.white)` themselves, since this style can't
/// tell whether a caller further up the chain already set one.
struct LegacyProminentButtonStyle: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Mirrors `.bordered`: a lightly-tinted fill, `tint`-colored text by
/// default (that's what real `.bordered` does - the two are visually
/// distinct specifically in this default-foreground behavior).
struct LegacyBorderedButtonStyle: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tint.opacity(0.15))
            .foregroundColor(tint)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
