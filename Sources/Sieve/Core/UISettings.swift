import Foundation
import SwiftUI

/// How the workspace is laid out, as opposed to what is in it.
///
/// These are deliberately preferences rather than decisions the app makes for you. A
/// 13-inch laptop and a 27-inch display are not the same room, and neither is screening a
/// hundred abstracts and reading one paper closely. Each of these is a checkbox in Settings.
enum UISettings {
    static let compactKey = "sieve.compactUI"
    static let autoHideSidebarKey = "sieve.autoHideSidebar"
    static let noteOnHighlightKey = "sieve.noteOnHighlight"
    static let paletteAlwaysKey = "sieve.paletteAlways"
    static let dimHighlightsReadingKey = "sieve.dimHighlightsInReading"

    /// Defaults are registered rather than assumed, so a key that has never been written
    /// still answers correctly — `bool(forKey:)` returning false is not the same as "off".
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            compactKey: false,
            autoHideSidebarKey: false,
            // Marking a passage should mark it. Opening a note box every time turned one
            // keystroke into two steps, most of them dismissals.
            noteOnHighlightKey: false,
            // The colours are a reminder of what you are reading for, so they stay on screen
            // rather than appearing only once you have already found something.
            paletteAlwaysKey: true,
            dimHighlightsReadingKey: false
        ])
    }

    static var compact: Bool { UserDefaults.standard.bool(forKey: compactKey) }
    static var autoHideSidebar: Bool { UserDefaults.standard.bool(forKey: autoHideSidebarKey) }
    static var noteOnHighlight: Bool { UserDefaults.standard.bool(forKey: noteOnHighlightKey) }
    static var paletteAlways: Bool { UserDefaults.standard.bool(forKey: paletteAlwaysKey) }
    static var dimHighlightsInReading: Bool { UserDefaults.standard.bool(forKey: dimHighlightsReadingKey) }
}
