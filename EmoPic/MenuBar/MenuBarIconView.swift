import SwiftUI

/// Menu bar status item icon.
///
/// A template SF Symbol (not a colour emoji like the previous 🎨) so the
/// system tints it for light/dark menu bars and selection: "Consider a
/// symbol (custom icon or SF Symbol), in black and clear so the system can
/// tint it for light and dark menu bars and selection" — apple-hig
/// `the-menu-bar.md`. `chevron.up.2` reads as "reveal upward", matching
/// a menu that drops down from the status item.
struct MenuBarIconView: View {
    var body: some View {
        Image(systemName: "chevron.up.2")
    }
}
