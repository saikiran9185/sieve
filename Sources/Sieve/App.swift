import SwiftUI
import AppKit

@main
struct SieveApp: App {
    @StateObject private var store = Store()
    @StateObject private var engine = SearchEngine()
    @StateObject private var assistant = Assistant()
    @StateObject private var downloader = Downloader()
    @StateObject private var nav = Navigator()
    @StateObject private var enricher = Enricher()
    // Held here purely so the View menu's titles follow the setting instead of going stale.
    @AppStorage(UISettings.compactKey) private var compactUI = false
    @AppStorage(UISettings.autoHideSidebarKey) private var autoHideSidebar = false

    init() {
        UISettings.registerDefaults()
        // The window is built before any view appears, so the saved appearance is applied here
        // rather than in onAppear, which would flash the wrong theme first.
        Appearance.apply(Appearance.current)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(assistant)
                .environmentObject(downloader)
                .environmentObject(nav)
                .environmentObject(enricher)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .commands {
            // ⌘Z belongs to whatever you are typing in first; only when nothing is being
            // typed does it mean "undo the last change to the library".
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button(nav.focusMode ? "Leave Reading Mode" : "Reading Mode") {
                    if !nav.focusMode { nav.section = .reader }
                    nav.focusMode.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
                Button(nav.hideHighlights ? "Show My Highlights" : "Hide My Highlights") {
                    nav.hideHighlights.toggle()
                }
                .keyboardShortcut("h", modifiers: [.command, .control])
                Divider()
                Button(compactUI ? "Comfortable Layout" : "Compact Layout") { compactUI.toggle() }
                    .keyboardShortcut("k", modifiers: [.command, .control])
                Button(autoHideSidebar ? "Keep the Sidebar Open" : "Auto-hide the Sidebar") {
                    autoHideSidebar.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            CommandGroup(replacing: .newItem) {
                Button("New Review…") { nav.section = .dashboard; nav.showNewProject = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Import PDFs…") { nav.requestImportPDF = true }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Import .bib / .ris…") { nav.requestImportBib = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { nav.showShortcuts = true }
                    .keyboardShortcut("/", modifiers: .command)
                Button("Sieve on GitHub") { SafeLink.open("https://github.com/saikiran9185/sieve") }
            }
            CommandMenu("Go") {
                ForEach(Section.allCases) { s in
                    Button(s.title) { nav.section = s }
                        .keyboardShortcut(KeyEquivalent(Character(s.shortcut)), modifiers: .command)
                }
            }
            CommandGroup(after: .toolbar) {
                Picker("Appearance", selection: Binding(
                    get: { Appearance.current },
                    set: { Appearance.current = $0 })) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                Divider()
                Button("Open Library Folder in Finder") {
                    NSWorkspace.shared.open(Library.root)
                }
            }
        }
    }

    /// A note field has its own history, word by word. Handing ⌘Z to the library while the
    /// insertion point is in a note is how an app throws away a paragraph you were fixing.
    private func undo() {
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
           tv.undoManager?.canUndo == true {
            tv.undoManager?.undo()
            return
        }
        if let name = store.history.undo() { store.flash("Undid \(name)") }
        else { NSSound.beep() }
    }

    private func redo() {
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
           tv.undoManager?.canRedo == true {
            tv.undoManager?.redo()
            return
        }
        if let name = store.history.redo() { store.flash("Redid \(name)") }
        else { NSSound.beep() }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case dashboard, search, library, screening, reader, evidence, map, matrix, frames, prisma, aiTrail, method, tags, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Overview"
        case .search: return "Find papers"
        case .library: return "Library"
        case .screening: return "Screening"
        case .reader: return "Reader"
        case .evidence: return "Evidence"
        case .map: return "Map"
        case .matrix: return "Matrix"
        case .frames: return "Frameworks"
        case .prisma: return "PRISMA"
        case .aiTrail: return "AI trail"
        case .method: return "Method"
        case .tags: return "Tags"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical"
        case .screening: return "checklist"
        case .reader: return "doc.text"
        case .evidence: return "highlighter"
        case .map: return "point.3.connected.trianglepath.dotted"
        case .matrix: return "tablecells"
        case .frames: return "square.grid.3x3"
        case .prisma: return "flowchart"
        case .aiTrail: return "shield.lefthalf.filled"
        case .method: return "slider.horizontal.3"
        case .tags: return "tag"
        case .settings: return "gearshape"
        }
    }

    var shortcut: String {
        switch self {
        case .dashboard: return "1"
        case .search: return "2"
        case .library: return "3"
        case .screening: return "4"
        case .reader: return "5"
        case .evidence: return "6"
        case .map: return "7"
        case .matrix: return "8"
        case .prisma: return "9"
        case .frames: return "f"
        case .aiTrail: return "t"
        case .method: return "m"
        case .tags: return "0"
        case .settings: return "-"
        }
    }
}

@MainActor
final class Navigator: ObservableObject {
    @Published var section: Section = .dashboard
    @Published var readingPaperId: Int? = nil
    @Published var showNewProject = false
    @Published var showShortcuts = false
    @Published var requestImportPDF = false
    @Published var requestImportBib = false
    @Published var evidenceFocusId: Int? = nil
    @Published var librarySelection: LibrarySelection = .all

    /// Reading mode. On a laptop screen the panels either side of the document take more
    /// room than the document does. Focus gives all of it back — no sidebar, no paper list,
    /// no inspector, no method bar — and the tools come back as an overlay only when there
    /// is a selection to act on, so turning them on never moves the page you are reading.
    @Published var focusMode: Bool = UserDefaults.standard.bool(forKey: "sieve.focusMode") {
        didSet { UserDefaults.standard.set(focusMode, forKey: "sieve.focusMode") }
    }

    /// Reading mode only takes the chrome away on the screen that has a document on it.
    /// Elsewhere there would be nothing left to click to get the app back.
    var readingModeActive: Bool { focusMode && section == .reader }

    /// Your marks, hidden. Re-reading a passage without your own colour on top of it is a
    /// different reading, and it is worth being able to ask for it.
    @Published var hideHighlights: Bool = UserDefaults.standard.bool(forKey: "sieve.hideHighlights") {
        didSet { UserDefaults.standard.set(hideHighlights, forKey: "sieve.hideHighlights") }
    }

    init() {
        // Come back to the screen you left, not to a dashboard you then navigate out of.
        if let raw = ReadingMemory.lastSection, let s = Section(rawValue: raw) {
            section = s
        }
    }

    func read(_ paperId: Int) {
        readingPaperId = paperId
        section = .reader
    }

    /// Remembers the screen and the paper so the next launch resumes rather than restarts.
    func rememberPlace(project: Int) {
        ReadingMemory.lastSection = section.rawValue
        ReadingMemory.setLastPaper(readingPaperId, project: project)
    }
}
