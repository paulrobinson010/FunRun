import SwiftUI

/// The Gaitway look, lifted straight from the logo: a near-black world
/// with electric cyan and hot magenta, soft neon glows, and one
/// signature gradient. Single source of truth for both apps — the
/// phone and the watch draw from the same palette the website uses.
enum Gaitway {
    /// #020208 — the page/app background.
    static let background = Color(red: 2 / 255, green: 2 / 255, blue: 8 / 255)
    /// #0b0b14 — cards and panels.
    static let panel = Color(red: 11 / 255, green: 11 / 255, blue: 20 / 255)
    /// #10101c — raised panels.
    static let panelHigh = Color(red: 16 / 255, green: 16 / 255, blue: 28 / 255)
    /// #2bd9ff — electric cyan: navigation, route things.
    static let cyan = Color(red: 43 / 255, green: 217 / 255, blue: 255 / 255)
    /// #ff2e9e — hot magenta: intensity, effort things.
    static let magenta = Color(red: 255 / 255, green: 46 / 255, blue: 158 / 255)
    /// #8b8da3 — secondary text.
    static let muted = Color(red: 139 / 255, green: 141 / 255, blue: 163 / 255)
    /// Hairline borders on panels.
    static let line = Color.white.opacity(0.08)

    /// The signature cyan→magenta sweep — headline moments only:
    /// titles, the big elapsed number, the one hero button per screen.
    static let gradient = LinearGradient(
        colors: [cyan, magenta],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    /// The app's basic surface: near-black rounded panel, hairline edge.
    func gaitwayCard(cornerRadius: CGFloat = 14) -> some View {
        background(Gaitway.panel, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Gaitway.line))
    }

    /// Soft neon halo under a key element. Accents and artwork only —
    /// never body text, and never mid-run numbers.
    func gaitwayGlow(_ color: Color = Gaitway.cyan, radius: CGFloat = 10) -> some View {
        shadow(color: color.opacity(0.45), radius: radius)
    }
}

#if os(iOS)
extension View {
    /// Brand treatment for a List: hide the system background and sit
    /// the list on the Gaitway backdrop. Pair with
    /// `.listRowBackground(Gaitway.panel)` on rows.
    func gaitwayList() -> some View {
        scrollContentBackground(.hidden)
            .background(GaitwayBackdrop())
    }
}
#endif
