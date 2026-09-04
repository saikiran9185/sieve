import Foundation
import AppKit
import CoreText

// MARK: - Minimal ZIP writer (stored, no compression)

/// An .xlsx file is a ZIP of XML parts. Rather than take a dependency, this writes the
/// archive directly using the "stored" method — valid ZIP, opened fine by Excel and Numbers.
struct ZipWriter {
    private struct Entry {
        let name: String, data: Data, crc: UInt32, offset: UInt32
    }
    private var entries: [Entry] = []
    private var body = Data()

    mutating func add(_ name: String, _ contents: Data) {
        let offset = UInt32(body.count)
        let crc = ZipWriter.crc32(contents)
        let nameBytes = Array(name.utf8)

        var local = Data()
        local.append(le32(0x04034b50))          // local file header
        local.append(le16(20))                  // version needed
        local.append(le16(0))                   // flags
        local.append(le16(0))                   // method: stored
        local.append(le16(0)); local.append(le16(0))   // mod time/date
        local.append(le32(crc))
        local.append(le32(UInt32(contents.count)))
        local.append(le32(UInt32(contents.count)))
        local.append(le16(UInt16(nameBytes.count)))
        local.append(le16(0))
        local.append(contentsOf: nameBytes)
        local.append(contents)
        body.append(local)
        entries.append(Entry(name: name, data: contents, crc: crc, offset: offset))
    }

    mutating func add(_ name: String, _ text: String) { add(name, Data(text.utf8)) }

    func finish() -> Data {
        var out = body
        let dirStart = UInt32(out.count)
        for e in entries {
            let nameBytes = Array(e.name.utf8)
            out.append(le32(0x02014b50))        // central directory header
            out.append(le16(20)); out.append(le16(20))
            out.append(le16(0)); out.append(le16(0))
            out.append(le16(0)); out.append(le16(0))
            out.append(le32(e.crc))
            out.append(le32(UInt32(e.data.count)))
            out.append(le32(UInt32(e.data.count)))
            out.append(le16(UInt16(nameBytes.count)))
            out.append(le16(0)); out.append(le16(0)); out.append(le16(0))
            out.append(le16(0)); out.append(le32(0))
            out.append(le32(e.offset))
            out.append(contentsOf: nameBytes)
        }
        let dirSize = UInt32(out.count) - dirStart
        out.append(le32(0x06054b50))            // end of central directory
        out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(dirSize)); out.append(le32(dirStart))
        out.append(le16(0))
        return out
    }

    private func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - XLSX

enum XLSX {
    /// Builds a single-sheet workbook from a grid of strings. Row 1 is styled as a header
    /// and frozen, and columns are given sensible widths, so the matrix opens ready to read.
    static func build(grid: [[String]], sheetName: String = "Matrix") -> Data {
        var zip = ZipWriter()

        zip.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """)

        zip.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """)

        zip.add("xl/workbook.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="\(esc(String(sheetName.prefix(28))))" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """)

        zip.add("xl/_rels/workbook.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """)

        // Two cell formats: 0 = wrapped body text, 1 = bold header.
        zip.add("xl/styles.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>
        <font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
        <fills count="3"><fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFEFF3F8"/><bgColor indexed="64"/></patternFill></fill></fills>
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="2">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
        </cellXfs>
        </styleSheet>
        """)

        let colCount = grid.map(\.count).max() ?? 1
        var cols = "<cols>"
        for i in 1...max(colCount, 1) {
            cols += "<col min=\"\(i)\" max=\"\(i)\" width=\"\(i <= 2 ? 34 : 42)\" customWidth=\"1\"/>"
        }
        cols += "</cols>"

        var rows = ""
        for (r, row) in grid.enumerated() {
            rows += "<row r=\"\(r + 1)\" ht=\"\(r == 0 ? 22 : 60)\" customHeight=\"1\">"
            for (c, value) in row.enumerated() {
                let ref = "\(columnName(c + 1))\(r + 1)"
                rows += "<c r=\"\(ref)\" t=\"inlineStr\" s=\"\(r == 0 ? 1 : 0)\">"
                rows += "<is><t xml:space=\"preserve\">\(esc(value))</t></is></c>"
            }
            rows += "</row>"
        }

        zip.add("xl/worksheets/sheet1.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetViews><sheetView workbookViewId="0" tabSelected="1">
        <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>
        </sheetView></sheetViews>
        \(cols)<sheetData>\(rows)</sheetData></worksheet>
        """)

        return zip.finish()
    }

    static func columnName(_ n: Int) -> String {
        var n = n, out = ""
        while n > 0 {
            let r = (n - 1) % 26
            out = String(UnicodeScalar(UInt8(65 + r))) + out
            n = (n - 1) / 26
        }
        return out
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         // Control characters are illegal in XML and Excel refuses the whole file over one.
         .filter { $0 == "\n" || $0 == "\t" || $0.unicodeScalars.allSatisfy { $0.value >= 32 } }
    }
}

// MARK: - PDF report

/// A paginated PDF built with Core Text. Used for the matrix and the full review report,
/// so what leaves Sieve can go straight into a thesis appendix.
enum PDFReport {
    struct Block {
        enum Kind { case title, heading, subheading, body, quote, caption, rule, pageBreak }
        var kind: Kind
        var text: String = ""
    }

    static let pageSize = CGSize(width: 595, height: 842)   // A4 portrait, points
    static let margin: CGFloat = 54

    static func build(_ blocks: [Block], landscape: Bool = false) -> Data {
        let size = landscape ? CGSize(width: pageSize.height, height: pageSize.width) : pageSize
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return Data() }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let contentWidth = size.width - margin * 2
        var y = size.height - margin
        var page = 0
        var open = false

        func newPage() {
            if open { ctx.endPDFPage() }
            ctx.beginPDFPage(nil)
            open = true
            page += 1
            y = size.height - margin
        }
        newPage()

        for block in blocks {
            if case .pageBreak = block.kind { newPage(); continue }

            if case .rule = block.kind {
                if y < margin + 20 { newPage() }
                ctx.setStrokeColor(NSColor(white: 0.82, alpha: 1).cgColor)
                ctx.setLineWidth(0.5)
                ctx.move(to: CGPoint(x: margin, y: y - 6))
                ctx.addLine(to: CGPoint(x: size.width - margin, y: y - 6))
                ctx.strokePath()
                y -= 18
                continue
            }

            let attr = attributed(block)
            let framesetter = CTFramesetterCreateWithAttributedString(attr)
            var start = 0
            let length = attr.length

            while start < length {
                let available = y - margin
                if available < 40 { newPage(); continue }
                let path = CGPath(rect: CGRect(x: margin, y: margin, width: contentWidth, height: available), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                if visible.length == 0 { newPage(); continue }

                // Core Text lays the frame out from its own origin, so it is drawn into the
                // remaining space and the cursor moved down by the height actually used.
                let used = heightUsed(frame)
                ctx.saveGState()
                ctx.translateBy(x: 0, y: y - margin - available)
                CTFrameDraw(frame, ctx)
                ctx.restoreGState()

                y -= used + spacingAfter(block.kind)
                start += visible.length
                if start < length { newPage() }
            }
        }
        if open { ctx.endPDFPage() }
        ctx.closePDF()
        return data as Data
    }

    private static func heightUsed(_ frame: CTFrame) -> CGFloat {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard !lines.isEmpty else { return 0 }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(lines[0], &ascent, &descent, &leading)
        let top = origins[0].y + ascent
        CTLineGetTypographicBounds(lines[lines.count - 1], &ascent, &descent, &leading)
        let bottom = origins[lines.count - 1].y - descent
        return top - bottom
    }

    private static func spacingAfter(_ k: Block.Kind) -> CGFloat {
        switch k {
        case .title: return 18
        case .heading: return 10
        case .subheading: return 6
        case .body: return 10
        case .quote: return 12
        case .caption: return 8
        default: return 6
        }
    }

    private static func attributed(_ b: Block) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        var font = NSFont.systemFont(ofSize: 10.5)
        var color = NSColor.black

        switch b.kind {
        case .title:
            font = NSFont.systemFont(ofSize: 21, weight: .semibold)
        case .heading:
            font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        case .subheading:
            font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            color = NSColor(white: 0.28, alpha: 1)
        case .quote:
            font = NSFont(name: "Georgia", size: 10.5) ?? NSFont.systemFont(ofSize: 10.5)
            para.firstLineHeadIndent = 16; para.headIndent = 16
            color = NSColor(white: 0.15, alpha: 1)
        case .caption:
            font = NSFont.systemFont(ofSize: 8.8)
            color = NSColor(white: 0.42, alpha: 1)
        default: break
        }
        return NSAttributedString(string: b.text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: para
        ])
    }

    /// Renders a grid as a real table, sized to fit the page, wrapping inside every cell.
    static func table(_ grid: [[String]], title: String, subtitle: String) -> Data {
        let size = CGSize(width: pageSize.height, height: pageSize.width)   // landscape
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return Data() }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil),
              let header = grid.first else { return Data() }

        let contentWidth = size.width - margin * 2
        let colCount = header.count
        // The first column (the paper) gets more room; the rest share what's left.
        let firstWidth = min(contentWidth * 0.26, 200)
        let otherWidth = (contentWidth - firstWidth) / CGFloat(max(colCount - 1, 1))
        let widths = (0..<colCount).map { $0 == 0 ? firstWidth : otherWidth }

        var y = size.height - margin
        var open = false
        var isFirstPage = true

        func drawHeaderRow() {
            let h = rowHeight(header, widths: widths, bold: true)
            ctx.setFillColor(NSColor(white: 0.94, alpha: 1).cgColor)
            ctx.fill(CGRect(x: margin, y: y - h, width: contentWidth, height: h))
            drawRow(ctx, header, widths: widths, top: y, bold: true)
            y -= h
        }

        func newPage() {
            if open { ctx.endPDFPage() }
            ctx.beginPDFPage(nil)
            open = true
            y = size.height - margin
            if isFirstPage {
                draw(ctx, title, at: CGPoint(x: margin, y: y - 22), font: .systemFont(ofSize: 18, weight: .semibold))
                y -= 30
                draw(ctx, subtitle, at: CGPoint(x: margin, y: y - 12),
                     font: .systemFont(ofSize: 9.5), color: NSColor(white: 0.4, alpha: 1))
                y -= 24
                isFirstPage = false
            }
            drawHeaderRow()
        }
        newPage()

        for row in grid.dropFirst() {
            let h = rowHeight(row, widths: widths, bold: false)
            if y - h < margin { newPage() }
            drawRow(ctx, row, widths: widths, top: y, bold: false)
            ctx.setStrokeColor(NSColor(white: 0.85, alpha: 1).cgColor)
            ctx.setLineWidth(0.4)
            ctx.move(to: CGPoint(x: margin, y: y - h))
            ctx.addLine(to: CGPoint(x: size.width - margin, y: y - h))
            ctx.strokePath()
            y -= h
        }
        if open { ctx.endPDFPage() }
        ctx.closePDF()
        return data as Data
    }

    private static func cellAttributed(_ text: String, bold: Bool) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 1
        para.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: bold ? NSFont.systemFont(ofSize: 8, weight: .semibold) : NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor.black,
            .paragraphStyle: para
        ])
    }

    private static func rowHeight(_ row: [String], widths: [CGFloat], bold: Bool) -> CGFloat {
        var tallest: CGFloat = 18
        for (i, cell) in row.enumerated() where i < widths.count {
            let attr = cellAttributed(cell, bold: bold)
            let fs = CTFramesetterCreateWithAttributedString(attr)
            let fit = CTFramesetterSuggestFrameSizeWithConstraints(
                fs, CFRange(location: 0, length: 0), nil,
                CGSize(width: widths[i] - 10, height: 400), nil)
            tallest = max(tallest, ceil(fit.height) + 10)
        }
        return min(tallest, 220)
    }

    private static func drawRow(_ ctx: CGContext, _ row: [String], widths: [CGFloat],
                                top: CGFloat, bold: Bool) {
        let h = rowHeight(row, widths: widths, bold: bold)
        var x = margin
        for (i, cell) in row.enumerated() where i < widths.count {
            let attr = cellAttributed(cell, bold: bold)
            let fs = CTFramesetterCreateWithAttributedString(attr)
            let rect = CGRect(x: x + 5, y: top - h + 5, width: widths[i] - 10, height: h - 10)
            let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0),
                                                 CGPath(rect: rect, transform: nil), nil)
            CTFrameDraw(frame, ctx)
            x += widths[i]
        }
    }

    private static func draw(_ ctx: CGContext, _ text: String, at p: CGPoint,
                             font: NSFont, color: NSColor = .black) {
        let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = p
        CTLineDraw(line, ctx)
    }
}
