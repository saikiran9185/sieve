import SwiftUI
import AppKit

// MARK: - Appearance

/// Light, dark, or whatever the system is set to. Stored per user, applied to the whole app.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match system"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static var current: Appearance {
        get { Appearance(rawValue: UserDefaults.standard.string(forKey: "sieve.appearance") ?? "") ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "sieve.appearance")
            apply(newValue)
        }
    }

    static func apply(_ a: Appearance) {
        NSApplication.shared.appearance = a.nsAppearance
    }
}

extension Color {
    /// A colour that resolves differently in light and dark mode.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// A tag colour that stays legible on both grounds.
    ///
    /// The palette is tuned for a dark background: amber and teal at full brightness fall
    /// well below 4.5:1 against white. Rather than maintain two palettes in sync, the light
    /// variant is derived — darkened and saturated until it can carry text.
    static func readable(_ hex: String) -> Color {
        let base = NSColor(Color(hex: hex)).usingColorSpace(.sRGB) ?? .gray
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        // Measured against white and against the app's dark ground: the palette as authored
        // reaches only 1.7:1 for amber on white, and purple and red stop just short of 4.5:1
        // on dark. Both ends are corrected here so one set of hexes serves both modes.
        let light = NSColor(hue: h, saturation: min(sat * 1.15, 1), brightness: b * 0.60, alpha: 1)
        let dark = NSColor(hue: h, saturation: sat * 0.94, brightness: min(b * 1.10, 1), alpha: 1)
        return .adaptive(light: light, dark: dark)
    }
}
