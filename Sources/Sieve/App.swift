import SwiftUI
import AppKit
import SieveCore

@main
struct SieveApp: App {
    @StateObject private var store = Store()
    @StateObject private var engine = SearchEngine()
    @StateObject private var assistant = Assistant()
    @StateObject private var downloader = Downloader()
    @StateObject private var nav = Navigator()
    @StateObject private var enricher = Enricher()

    init() {
        // The engine keeps no credential API of its own, so the platform store has to be in
        // place before any provider can read a key.
        Secrets.store = KeychainStore.shared

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

    func read(_ paperId: Int) {
        readingPaperId = paperId
        section = .reader
    }
}
