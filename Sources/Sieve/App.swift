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
            CommandMenu("Go") {
                ForEach(Section.allCases) { s in
                    Button(s.title) { nav.section = s }
                        .keyboardShortcut(KeyEquivalent(Character(s.shortcut)), modifiers: .command)
                }
            }
            CommandGroup(after: .toolbar) {
                Button("Open Library Folder in Finder") {
                    NSWorkspace.shared.open(Library.root)
                }
            }
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case dashboard, search, library, screening, reader, evidence, map, matrix, prisma, method, tags, settings
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
        case .prisma: return "PRISMA"
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
        case .prisma: return "flowchart"
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
    @Published var requestImportPDF = false
    @Published var requestImportBib = false
    @Published var evidenceFocusId: Int? = nil
    @Published var librarySelection: LibrarySelection = .all

    func read(_ paperId: Int) {
        readingPaperId = paperId
        section = .reader
    }
}
