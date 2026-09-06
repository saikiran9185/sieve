import SwiftUI
import AppKit

/// Visual language: a quiet, paper-like workspace. Nothing competes with the text
/// you're reading — colour is reserved almost entirely for your own tags.
enum D {
    // Spacing
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12
    static let s4: CGFloat = 16, s5: CGFloat = 24, s6: CGFloat = 32

    static let radius: CGFloat = 8
    static let radiusL: CGFloat = 12

    // Surfaces
    static var canvas: Color { Color(nsColor: .underPageBackgroundColor) }
    static var surface: Color { Color(nsColor: .controlBackgroundColor) }
    static var raised: Color { Color(nsColor: .textBackgroundColor) }
    static var hairline: Color { Color(nsColor: .separatorColor) }

    // Type
    static let title = Font.system(size: 20, weight: .semibold)
    static let heading = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13)
    static let small = Font.system(size: 11.5)
    static let mono = Font.system(size: 11.5, design: .monospaced)
    static let label = Font.system(size: 10.5, weight: .semibold)

    static let serif = Font.system(size: 13.5, design: .serif)
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    var padding: CGFloat = D.s4
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(D.raised)
            .clipShape(RoundedRectangle(cornerRadius: D.radiusL, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: D.radiusL, style: .continuous)
                .stroke(D.hairline, lineWidth: 0.5))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(D.label)
            .tracking(0.7)
            .foregroundStyle(.secondary)
    }
}

/// The tag/stage chip used everywhere — coloured dot plus label, sized for dense lists.
struct Chip: View {
    let text: String
    var color: Color = D.hairline
    var filled = false
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            else if !filled { Circle().fill(color).frame(width: 6, height: 6) }
            Text(text).font(D.small.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(filled ? color.opacity(0.92) : color.opacity(0.16))
        .foregroundStyle(filled ? Color.white : color)
        .clipShape(Capsule())
        .accessibilityLabel(text)
    }
}

struct StageBadge: View {
    let stage: Stage
    var body: some View { Chip(text: stage.short, color: stage.color) }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: (label: String, run: () -> Void)? = nil

    var body: some View {
        VStack(spacing: D.s3) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(D.heading)
            Text(message)
                .font(D.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, D.s1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(D.s6)
    }
}

/// A count sitting above its label — the vocabulary of the PRISMA boxes and the dashboard.
struct Stat: View {
    let value: Int
    let label: String
    var tint: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label).font(D.small).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Toolbar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: D.s2) { content }
            .padding(.horizontal, D.s4)
            .padding(.vertical, D.s2 + 2)
            .background(.bar)
            .overlay(alignment: .bottom) { Rectangle().fill(D.hairline).frame(height: 0.5) }
    }
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(D.body)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(D.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(D.hairline, lineWidth: 0.5))
    }
}

/// Marks anything Claude produced. Non-negotiable: an AI sentence must never be
/// mistakable for something you read and wrote yourself.
struct AIBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle").font(.system(size: 8, weight: .bold))
            Text("AI").font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Palette.violet.opacity(0.16))
        .foregroundStyle(Palette.violet)
        .clipShape(Capsule())
        .help("Drafted by Claude from your highlights — check it before you rely on it.")
    }
}

extension View {
    func hairlineBorder(_ radius: CGFloat = D.radius) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(D.hairline, lineWidth: 0.5))
    }
}

/// Wrapping horizontal stack. Fourteen database chips don't fit on one line at every
/// window width, and an HStack would just squash them.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}

/// The sites Sieve can't query directly. Each one opens a pre-filled search in the browser
/// and tells you how to get its citations back out as a file you can drop into the app.
struct ExternalSitesSheet: View {
    let query: String
    var done: () -> Void
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Navigator

    var body: some View {
        VStack(alignment: .leading, spacing: D.s3) {
            Text("Search sites that have no API").font(D.title)
            Text("Google Scholar and BASE block automated querying, and the big publishers keep search behind institutional agreements. Sieve opens your search there in the browser; export the citations as .bib or .ris and drop the file into this window.")
                .font(D.small).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Label("Type a search in Find papers first — it gets carried across.",
                      systemImage: "exclamationmark.circle")
                    .font(D.small).foregroundStyle(Palette.amber)
            }

            ScrollView {
                VStack(spacing: D.s2) {
                    ForEach(ExternalSite.all) { site in
                        Card(padding: D.s3) {
                            HStack(alignment: .top, spacing: D.s3) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(site.name).font(D.body.weight(.medium))
                                    Text(site.blurb).font(D.small).foregroundStyle(.secondary)
                                    Text(site.howTo).font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Button("Open") {
                                    guard let u = site.url(for: query) else { return }
                                    SafeLink.open(u)
                                }
                                .buttonStyle(.bordered)
                                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                }
            }
            .frame(height: 400)

            HStack {
                Button { nav.requestImportBib = true; done() } label: {
                    Label("Import a .bib / .ris file", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("Close", action: done).keyboardShortcut(.cancelAction)
            }
        }
        .padding(D.s5).frame(width: 660)
    }
}

/// A draggable divider between two panes.
///
/// `HSplitView` cannot be used inside a `NavigationSplitView` detail column — it lays its
/// children out in window coordinates rather than the column's, so the first pane slides
/// underneath the app sidebar and its content is clipped. A plain `HStack` with this
/// divider gives the same resizing behaviour and lays out where it is actually placed.
struct PaneDivider: View {
    @Binding var width: Double
    var range: ClosedRange<Double>
    /// True when the pane being sized is to the *right* of this divider, so dragging left
    /// makes it wider.
    var sizesTrailingPane = false

    @State private var startWidth: CGFloat? = nil
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? Palette.accent.opacity(0.5) : D.hairline)
            .frame(width: 1)
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 10)
                    .contentShape(Rectangle())
            }
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = startWidth ?? width
                        if startWidth == nil { startWidth = width }
                        let delta = Double(sizesTrailingPane ? -value.translation.width : value.translation.width)
                        width = min(max(base + delta, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}
