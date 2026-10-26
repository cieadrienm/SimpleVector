import Foundation

/// Zero-dependency SVG 1.1 / 2.0 parser and serializer for `SimpleVectorCore`.
public enum SVGCodec {

    // MARK: - Import SVG

    public static func importSVG(data: Data, title: String = "Document SVG", fileURL: URL? = nil) throws -> VectorDocument {
        guard let xmlString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "SVGCodec", code: 1, userInfo: [
                NSLocalizedDescriptionKey: L("Encodage SVG non reconnu.", "Unrecognized SVG encoding.")
            ])
        }
        return try importSVG(string: xmlString, title: title, fileURL: fileURL)
    }

    public static func importSVG(string: String, title: String = "Document SVG", fileURL: URL? = nil) throws -> VectorDocument {
        let parserDelegate = SVGXMLParserDelegate(defaultTitle: title)
        let parser = XMLParser(data: Data(string.utf8))
        parser.delegate = parserDelegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        _ = parser.parse()

        let pages = parserDelegate.buildPages()
        return VectorDocument(
            title: title,
            sourceFormat: .svg,
            fileURL: fileURL,
            pages: pages.isEmpty ? [VectorPage(title: "Page 1")] : pages
        )
    }

    // MARK: - Export SVG

    public static func exportSVG(document: VectorDocument, pageIndex: Int? = nil) -> String {
        if let idx = pageIndex, document.pages.indices.contains(idx) {
            return serializeSinglePageSVG(document.pages[idx], documentTitle: document.title)
        }
        if document.pages.count == 1, let first = document.pages.first {
            return serializeSinglePageSVG(first, documentTitle: document.title)
        }
        return serializeMultiPageSVG(document)
    }

    private static func serializeSinglePageSVG(_ page: VectorPage, documentTitle: String) -> String {
        let w = formatNum(page.width)
        let h = formatNum(page.height)
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"\(w)\" height=\"\(h)\" viewBox=\"0 0 \(w) \(h)\">")
        lines.append("  <title>\(escapeXML(documentTitle)) — \(escapeXML(page.title))</title>")
        lines.append("  <rect width=\"\(w)\" height=\"\(h)\" fill=\"\(escapeXML(page.backgroundColorHex))\" data-role=\"page-background\"/>")
        for element in page.elements where element.visible {
            if case .text(let t) = element.kind, t.isPDFExtracted && !element.hasModifiedPDFText && page.pdfPageData != nil {
                // Still export extracted PDF text into SVG so SVG output is complete and standalone
            }
            lines.append(contentsOf: serializeElement(element, indent: "  "))
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func serializeMultiPageSVG(_ document: VectorDocument) -> String {
        let maxW = document.pages.map(\.width).max() ?? 595.28
        let gap = 32.0
        let totalH = document.pages.reduce(0.0) { $0 + $1.height } + Double(max(0, document.pages.count - 1)) * gap
        let wStr = formatNum(maxW)
        let hStr = formatNum(totalH)

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"\(wStr)\" height=\"\(hStr)\" viewBox=\"0 0 \(wStr) \(hStr)\" data-multipage=\"true\">")
        lines.append("  <title>\(escapeXML(document.title))</title>")

        var yOffset = 0.0
        for (idx, page) in document.pages.enumerated() {
            let pw = formatNum(page.width)
            let ph = formatNum(page.height)
            let yOffStr = formatNum(yOffset)
            lines.append("  <g id=\"page-\(idx + 1)\" data-page-index=\"\(idx + 1)\" data-page-title=\"\(escapeXML(page.title))\" data-page-width=\"\(pw)\" data-page-height=\"\(ph)\" transform=\"translate(0, \(yOffStr))\">")
            lines.append("    <rect width=\"\(pw)\" height=\"\(ph)\" fill=\"\(escapeXML(page.backgroundColorHex))\" data-role=\"page-background\"/>")
            for element in page.elements where element.visible {
                lines.append(contentsOf: serializeElement(element, indent: "    "))
            }
            lines.append("  </g>")
            yOffset += page.height + gap
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func serializeElement(_ el: VectorElement, indent: String) -> [String] {
        let f = el.frame
        let rotAttr: String
        if abs(el.rotationDegrees) > 0.01 {
            let cx = formatNum(f.midX)
            let cy = formatNum(f.midY)
            rotAttr = " transform=\"rotate(\(formatNum(el.rotationDegrees)) \(cx) \(cy))\""
        } else {
            rotAttr = ""
        }
        let opacityAttr = el.style.opacity < 0.999 ? " opacity=\"\(formatNum(el.style.opacity))\"" : ""
        let dashAttr = el.style.dashed ? " stroke-dasharray=\"6,4\"" : ""
        let strokeAttr = el.style.strokeColorHex ?? "none"
        let fillAttr = el.style.fillColorHex ?? "none"
        let swAttr = formatNum(el.style.strokeWidth)

        switch el.kind {
        case .shape(let s):
            switch s.shapeType {
            case .rectangle:
                return ["\(indent)<rect x=\"\(formatNum(f.x))\" y=\"\(formatNum(f.y))\" width=\"\(formatNum(f.width))\" height=\"\(formatNum(f.height))\" fill=\"\(fillAttr)\" stroke=\"\(strokeAttr)\" stroke-width=\"\(swAttr)\"\(dashAttr)\(opacityAttr)\(rotAttr)/>"]
            case .roundedRectangle:
                let r = formatNum(s.cornerRadius)
                return ["\(indent)<rect x=\"\(formatNum(f.x))\" y=\"\(formatNum(f.y))\" width=\"\(formatNum(f.width))\" height=\"\(formatNum(f.height))\" rx=\"\(r)\" ry=\"\(r)\" fill=\"\(fillAttr)\" stroke=\"\(strokeAttr)\" stroke-width=\"\(swAttr)\"\(dashAttr)\(opacityAttr)\(rotAttr)/>"]
            case .ellipse:
                return ["\(indent)<ellipse cx=\"\(formatNum(f.midX))\" cy=\"\(formatNum(f.midY))\" rx=\"\(formatNum(f.width * 0.5))\" ry=\"\(formatNum(f.height * 0.5))\" fill=\"\(fillAttr)\" stroke=\"\(strokeAttr)\" stroke-width=\"\(swAttr)\"\(dashAttr)\(opacityAttr)\(rotAttr)/>"]
            case .line, .arrow:
                var out: [String] = []
                out.append("\(indent)<line x1=\"\(formatNum(f.minX))\" y1=\"\(formatNum(f.maxY))\" x2=\"\(formatNum(f.maxX))\" y2=\"\(formatNum(f.minY))\" stroke=\"\(strokeAttr)\" stroke-width=\"\(swAttr)\" stroke-linecap=\"round\"\(dashAttr)\(opacityAttr)\(rotAttr)/>")
                if s.endArrow || s.shapeType == .arrow {
                    let head = arrowHeadSVGPoints(from: VectorPoint(x: f.minX, y: f.maxY), to: VectorPoint(x: f.maxX, y: f.minY), length: max(8, el.style.strokeWidth * 4.2))
                    out.append("\(indent)<polygon points=\"\(head)\" fill=\"\(strokeAttr)\"\(opacityAttr)\(rotAttr)/>")
                }
                return out
            case .diamond:
                let pts = "\(formatNum(f.midX)),\(formatNum(f.minY)) \(formatNum(f.maxX)),\(formatNum(f.midY)) \(formatNum(f.midX)),\(formatNum(f.maxY)) \(formatNum(f.minX)),\(formatNum(f.midY))"
                return ["\(indent)<polygon points=\"\(pts)\" fill=\"\(fillAttr)\" stroke=\"\(strokeAttr)\" stroke-width=\"\(swAttr)\"\(dashAttr)\(opacityAttr)\(rotAttr)/>"]
            }

        case .path(let p):
            var dParts: [String] = []
            for sub in p.subpaths where !sub.points.isEmpty {
                let first = el.denormalize(sub.points[0])
                dParts.append("M \(formatNum(first.x)) \(formatNum(first.y))")
                for pt in sub.points.dropFirst() {
                    let dp = el.denormalize(pt)
                    dParts.append("L \(formatNum(dp.x)) \(formatNum(dp.y))")
                }
                if sub.isClosed { dParts.append("Z") }
            }
            let d = dParts.joined(separator: " ")
            return ["\(indent)<path d=\"\(d)\" fill=\"\(fillAttr)\" stroke=\"\(strokeAttr)\" stroke-width=\"\(swAttr)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"\(dashAttr)\(opacityAttr)\(rotAttr)/>"]

        case .signature(let sig):
            var out: [String] = []
            out.append("\(indent)<g data-role=\"signature\" data-signer=\"\(escapeXML(sig.signerName))\"\(opacityAttr)\(rotAttr)>")
            for stroke in sig.strokes where !stroke.isEmpty {
                var dParts: [String] = []
                let first = el.denormalize(stroke[0])
                dParts.append("M \(formatNum(first.x)) \(formatNum(first.y))")
                for pt in stroke.dropFirst() {
                    let dp = el.denormalize(pt)
                    dParts.append("L \(formatNum(dp.x)) \(formatNum(dp.y))")
                }
                out.append("\(indent)  <path d=\"\(dParts.joined(separator: " "))\" fill=\"none\" stroke=\"\(strokeAttr)\" stroke-width=\"\(swAttr)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>")
            }
            let meta = [sig.signerName, sig.caption, sig.dateLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !meta.isEmpty {
                out.append("\(indent)  <text x=\"\(formatNum(f.x + 4))\" y=\"\(formatNum(f.maxY - 2))\" font-family=\"Helvetica Neue\" font-size=\"9\" fill=\"\(strokeAttr)\">\(escapeXML(meta))</text>")
            }
            out.append("\(indent)</g>")
            return out

        case .text(let t):
            let textColor = el.style.fillColorHex ?? el.style.strokeColorHex ?? "#111317"
            let weightAttr = t.isBold ? " font-weight=\"bold\"" : ""
            let styleAttr = t.isItalic ? " font-style=\"italic\"" : ""
            let anchorAttr: String
            let baseX: Double
            switch t.alignment {
            case .left:
                anchorAttr = "start"
                baseX = f.minX
            case .center:
                anchorAttr = "middle"
                baseX = f.midX
            case .right:
                anchorAttr = "end"
                baseX = f.maxX
            }
            let lines = t.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var out: [String] = []
            let firstY = f.minY + t.fontSize
            if lines.count <= 1 {
                out.append("\(indent)<text x=\"\(formatNum(baseX))\" y=\"\(formatNum(firstY))\" font-family=\"\(escapeXML(t.fontFamily))\" font-size=\"\(formatNum(t.fontSize))\"\(weightAttr)\(styleAttr) text-anchor=\"\(anchorAttr)\" fill=\"\(textColor)\"\(opacityAttr)\(rotAttr)>\(escapeXML(t.text))</text>")
            } else {
                out.append("\(indent)<text x=\"\(formatNum(baseX))\" y=\"\(formatNum(firstY))\" font-family=\"\(escapeXML(t.fontFamily))\" font-size=\"\(formatNum(t.fontSize))\"\(weightAttr)\(styleAttr) text-anchor=\"\(anchorAttr)\" fill=\"\(textColor)\"\(opacityAttr)\(rotAttr)>")
                for (i, line) in lines.enumerated() {
                    let dy = i == 0 ? "0" : formatNum(t.fontSize * 1.28)
                    out.append("\(indent)  <tspan x=\"\(formatNum(baseX))\" dy=\"\(dy)\">\(escapeXML(line))</tspan>")
                }
                out.append("\(indent)</text>")
            }
            return out

        case .stamp(let st):
            let color = el.style.strokeColorHex ?? st.stampKind.defaultColorHex
            var out: [String] = []
            out.append("\(indent)<g data-role=\"stamp\" data-kind=\"\(st.stampKind.rawValue)\"\(opacityAttr)\(rotAttr)>")
            out.append("\(indent)  <rect x=\"\(formatNum(f.x))\" y=\"\(formatNum(f.y))\" width=\"\(formatNum(f.width))\" height=\"\(formatNum(f.height))\" rx=\"6\" ry=\"6\" fill=\"\(color)\" fill-opacity=\"0.10\" stroke=\"\(color)\" stroke-width=\"2.2\"/>")
            out.append("\(indent)  <rect x=\"\(formatNum(f.x + 3))\" y=\"\(formatNum(f.y + 3))\" width=\"\(formatNum(max(2, f.width - 6)))\" height=\"\(formatNum(max(2, f.height - 6)))\" rx=\"4\" ry=\"4\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"0.9\"/>")
            out.append("\(indent)  <text x=\"\(formatNum(f.midX))\" y=\"\(formatNum(f.y + f.height * 0.48))\" font-family=\"Helvetica Neue\" font-size=\"13\" font-weight=\"bold\" text-anchor=\"middle\" fill=\"\(color)\">\(escapeXML(st.title))</text>")
            if !st.subtitle.isEmpty {
                out.append("\(indent)  <text x=\"\(formatNum(f.midX))\" y=\"\(formatNum(f.y + f.height * 0.78))\" font-family=\"Helvetica Neue\" font-size=\"8.5\" text-anchor=\"middle\" fill=\"\(color)\">\(escapeXML(st.subtitle))</text>")
            }
            out.append("\(indent)</g>")
            return out
        }
    }

    private static func arrowHeadSVGPoints(from p0: VectorPoint, to p1: VectorPoint, length: Double) -> String {
        let angle = atan2(p1.y - p0.y, p1.x - p0.x)
        let wing = Double.pi / 6.5
        let left = VectorPoint(
            x: p1.x - length * cos(angle - wing),
            y: p1.y - length * sin(angle - wing)
        )
        let right = VectorPoint(
            x: p1.x - length * cos(angle + wing),
            y: p1.y - length * sin(angle + wing)
        )
        return "\(formatNum(p1.x)),\(formatNum(p1.y)) \(formatNum(left.x)),\(formatNum(left.y)) \(formatNum(right.x)),\(formatNum(right.y))"
    }

    public static func formatNum(_ v: Double) -> String {
        if abs(v.rounded() - v) < 0.005 {
            return "\(Int(v.rounded()))"
        }
        return String(format: "%.2f", v)
    }

    public static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - SVG Path `d` Tokenizer & Evaluator

    public static func parsePathData(_ d: String, offset: VectorPoint = .zero, scale: VectorPoint = VectorPoint(x: 1, y: 1)) -> [VectorSubpath] {
        let tokens = tokenizePathD(d)
        var subpaths: [VectorSubpath] = []
        var currentPoints: [VectorPoint] = []
        var cur = VectorPoint.zero
        var startPt = VectorPoint.zero
        var lastControl: VectorPoint? = nil
        var idx = 0
        var currentCmd: Character = "M"

        func tx(_ p: VectorPoint) -> VectorPoint {
            VectorPoint(x: p.x * scale.x + offset.x, y: p.y * scale.y + offset.y)
        }

        func nextDouble() -> Double? {
            guard idx < tokens.count, let v = Double(tokens[idx]) else { return nil }
            idx += 1
            return v
        }

        while idx < tokens.count {
            let token = tokens[idx]
            if token.count == 1, let ch = token.first, ch.isLetter {
                currentCmd = ch
                idx += 1
                if currentCmd == "Z" || currentCmd == "z" {
                    if !currentPoints.isEmpty {
                        subpaths.append(VectorSubpath(points: currentPoints, isClosed: true))
                        currentPoints.removeAll()
                    }
                    cur = startPt
                    lastControl = nil
                    continue
                }
            }

            switch currentCmd {
            case "M":
                guard let x = nextDouble(), let y = nextDouble() else { idx += 1; break }
                if !currentPoints.isEmpty {
                    subpaths.append(VectorSubpath(points: currentPoints, isClosed: false))
                    currentPoints.removeAll()
                }
                cur = VectorPoint(x: x, y: y)
                startPt = cur
                currentPoints.append(tx(cur))
                currentCmd = "L"
                lastControl = nil
            case "m":
                guard let dx = nextDouble(), let dy = nextDouble() else { idx += 1; break }
                if !currentPoints.isEmpty {
                    subpaths.append(VectorSubpath(points: currentPoints, isClosed: false))
                    currentPoints.removeAll()
                }
                cur = VectorPoint(x: cur.x + dx, y: cur.y + dy)
                startPt = cur
                currentPoints.append(tx(cur))
                currentCmd = "l"
                lastControl = nil
            case "L":
                guard let x = nextDouble(), let y = nextDouble() else { idx += 1; break }
                cur = VectorPoint(x: x, y: y)
                currentPoints.append(tx(cur))
                lastControl = nil
            case "l":
                guard let dx = nextDouble(), let dy = nextDouble() else { idx += 1; break }
                cur = VectorPoint(x: cur.x + dx, y: cur.y + dy)
                currentPoints.append(tx(cur))
                lastControl = nil
            case "H":
                guard let x = nextDouble() else { idx += 1; break }
                cur = VectorPoint(x: x, y: cur.y)
                currentPoints.append(tx(cur))
                lastControl = nil
            case "h":
                guard let dx = nextDouble() else { idx += 1; break }
                cur = VectorPoint(x: cur.x + dx, y: cur.y)
                currentPoints.append(tx(cur))
                lastControl = nil
            case "V":
                guard let y = nextDouble() else { idx += 1; break }
                cur = VectorPoint(x: cur.x, y: y)
                currentPoints.append(tx(cur))
                lastControl = nil
            case "v":
                guard let dy = nextDouble() else { idx += 1; break }
                cur = VectorPoint(x: cur.x, y: cur.y + dy)
                currentPoints.append(tx(cur))
                lastControl = nil
            case "C", "c":
                let rel = (currentCmd == "c")
                guard let x1 = nextDouble(), let y1 = nextDouble(),
                      let x2 = nextDouble(), let y2 = nextDouble(),
                      let x = nextDouble(), let y = nextDouble() else { idx += 1; break }
                let c1 = rel ? VectorPoint(x: cur.x + x1, y: cur.y + y1) : VectorPoint(x: x1, y: y1)
                let c2 = rel ? VectorPoint(x: cur.x + x2, y: cur.y + y2) : VectorPoint(x: x2, y: y2)
                let end = rel ? VectorPoint(x: cur.x + x, y: cur.y + y) : VectorPoint(x: x, y: y)
                sampleCubic(from: cur, c1: c1, c2: c2, to: end, steps: 10).forEach { currentPoints.append(tx($0)) }
                cur = end
                lastControl = c2
            case "S", "s":
                let rel = (currentCmd == "s")
                guard let x2 = nextDouble(), let y2 = nextDouble(),
                      let x = nextDouble(), let y = nextDouble() else { idx += 1; break }
                let c1: VectorPoint
                if let lc = lastControl {
                    c1 = VectorPoint(x: 2 * cur.x - lc.x, y: 2 * cur.y - lc.y)
                } else {
                    c1 = cur
                }
                let c2 = rel ? VectorPoint(x: cur.x + x2, y: cur.y + y2) : VectorPoint(x: x2, y: y2)
                let end = rel ? VectorPoint(x: cur.x + x, y: cur.y + y) : VectorPoint(x: x, y: y)
                sampleCubic(from: cur, c1: c1, c2: c2, to: end, steps: 10).forEach { currentPoints.append(tx($0)) }
                cur = end
                lastControl = c2
            case "Q", "q":
                let rel = (currentCmd == "q")
                guard let x1 = nextDouble(), let y1 = nextDouble(),
                      let x = nextDouble(), let y = nextDouble() else { idx += 1; break }
                let c1 = rel ? VectorPoint(x: cur.x + x1, y: cur.y + y1) : VectorPoint(x: x1, y: y1)
                let end = rel ? VectorPoint(x: cur.x + x, y: cur.y + y) : VectorPoint(x: x, y: y)
                for step in 1...8 {
                    let t = Double(step) / 8.0
                    let mt = 1.0 - t
                    let px = mt * mt * cur.x + 2 * mt * t * c1.x + t * t * end.x
                    let py = mt * mt * cur.y + 2 * mt * t * c1.y + t * t * end.y
                    currentPoints.append(tx(VectorPoint(x: px, y: py)))
                }
                cur = end
                lastControl = c1
            default:
                idx += 1
            }
        }
        if !currentPoints.isEmpty {
            subpaths.append(VectorSubpath(points: currentPoints, isClosed: false))
        }
        return subpaths
    }

    private static func sampleCubic(from p0: VectorPoint, c1: VectorPoint, c2: VectorPoint, to p3: VectorPoint, steps: Int) -> [VectorPoint] {
        var out: [VectorPoint] = []
        for s in 1...max(2, steps) {
            let t = Double(s) / Double(steps)
            let mt = 1.0 - t
            let x = mt * mt * mt * p0.x
                + 3 * mt * mt * t * c1.x
                + 3 * mt * t * t * c2.x
                + t * t * t * p3.x
            let y = mt * mt * mt * p0.y
                + 3 * mt * mt * t * c1.y
                + 3 * mt * t * t * c2.y
                + t * t * t * p3.y
            out.append(VectorPoint(x: x, y: y))
        }
        return out
    }

    private static func tokenizePathD(_ d: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(ch))
            } else if ch == "," || ch.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else if ch == "-" && !current.isEmpty && !current.hasSuffix("e") && !current.hasSuffix("E") {
                tokens.append(current)
                current = "-"
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

// MARK: - XMLParser Delegate

private final class SVGXMLParserDelegate: NSObject, XMLParserDelegate {
    struct GroupContext {
        var translateX: Double = 0
        var translateY: Double = 0
        var scaleX: Double = 1
        var scaleY: Double = 1
        var strokeHex: String? = nil
        var fillHex: String? = nil
        var strokeWidth: Double? = nil
        var opacity: Double = 1.0
        var isPageGroup: Bool = false
        var isSignatureGroup: Bool = false
        var signerName: String? = nil
        var isStampGroup: Bool = false
        var stampKind: VectorStampKind? = nil
    }

    let defaultTitle: String
    var svgWidth: Double = 595.28
    var svgHeight: Double = 841.89
    var pages: [VectorPage] = []
    var currentPage: VectorPage
    var groupStack: [GroupContext] = [GroupContext()]
    var signatureStrokesAccumulator: [[VectorPoint]] = []
    var activeTextAttributes: [String: String]? = nil
    var activeTextAccumulator: String = ""

    init(defaultTitle: String) {
        self.defaultTitle = defaultTitle
        self.currentPage = VectorPage(title: "Page 1", width: 595.28, height: 841.89)
    }

    func buildPages() -> [VectorPage] {
        if pages.isEmpty {
            var p = currentPage
            p.width = svgWidth
            p.height = svgHeight
            return [p]
        }
        return pages
    }

    private var currentTransform: (offset: VectorPoint, scale: VectorPoint) {
        var ox = 0.0
        var oy = 0.0
        var sx = 1.0
        var sy = 1.0
        for g in groupStack where !g.isPageGroup {
            ox += g.translateX * sx
            oy += g.translateY * sy
            sx *= g.scaleX
            sy *= g.scaleY
        }
        return (VectorPoint(x: ox, y: oy), VectorPoint(x: sx, y: sy))
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        let attrs = mergedAttributes(attributeDict)

        switch name {
        case "svg":
            if let vb = attrs["viewBox"] ?? attrs["viewbox"] {
                let nums = vb.split { $0 == " " || $0 == "," }.compactMap { Double($0) }
                if nums.count == 4 {
                    svgWidth = max(64, nums[2])
                    svgHeight = max(64, nums[3])
                }
            }
            if let w = parseDimension(attrs["width"]) { svgWidth = max(64, w) }
            if let h = parseDimension(attrs["height"]) { svgHeight = max(64, h) }
            currentPage.width = svgWidth
            currentPage.height = svgHeight

        case "g":
            var ctx = groupStack.last ?? GroupContext()
            ctx.isPageGroup = false
            if let transform = attrs["transform"] {
                let (tx, ty, sx, sy) = parseTransform(transform)
                ctx.translateX = tx
                ctx.translateY = ty
                ctx.scaleX = sx
                ctx.scaleY = sy
            } else {
                ctx.translateX = 0
                ctx.translateY = 0
                ctx.scaleX = 1
                ctx.scaleY = 1
            }
            if let s = attrs["stroke"] { ctx.strokeHex = normalizeColor(s) }
            if let f = attrs["fill"] { ctx.fillHex = normalizeColor(f) }
            if let sw = parseDimension(attrs["stroke-width"]) { ctx.strokeWidth = sw }

            if let pageTitle = attrs["data-page-title"] {
                ctx.isPageGroup = true
                let pw = parseDimension(attrs["data-page-width"]) ?? svgWidth
                let ph = parseDimension(attrs["data-page-height"]) ?? svgHeight
                currentPage = VectorPage(title: pageTitle, width: pw, height: ph)
            } else if attrs["data-role"] == "signature" {
                ctx.isSignatureGroup = true
                ctx.signerName = attrs["data-signer"] ?? "Adrien Mondot"
                signatureStrokesAccumulator.removeAll()
            } else if attrs["data-role"] == "stamp" {
                ctx.isStampGroup = true
                ctx.stampKind = attrs["data-kind"].flatMap(VectorStampKind.init(rawValue:)) ?? .approved
            }
            groupStack.append(ctx)

        case "rect":
            if attrs["data-role"] == "page-background" {
                if let fill = normalizeColor(attrs["fill"]) {
                    currentPage.backgroundColorHex = fill
                }
                return
            }
            if groupStack.last?.isStampGroup == true { return }
            let (off, sc) = currentTransform
            let x = (parseDimension(attrs["x"]) ?? 0) * sc.x + off.x
            let y = (parseDimension(attrs["y"]) ?? 0) * sc.y + off.y
            let w = (parseDimension(attrs["width"]) ?? 60) * sc.x
            let h = (parseDimension(attrs["height"]) ?? 40) * sc.y
            let rx = parseDimension(attrs["rx"]) ?? parseDimension(attrs["ry"]) ?? 0
            if x <= 0.5 && y <= 0.5 && abs(w - currentPage.width) < 2 && abs(h - currentPage.height) < 2,
               currentPage.elements.isEmpty, let fill = normalizeColor(attrs["fill"]) {
                currentPage.backgroundColorHex = fill
                return
            }
            let style = buildStyle(from: attrs, defaultFill: "#111317")
            let shapeType: VectorShapeType = rx > 0.5 ? .roundedRectangle : .rectangle
            let el = VectorElement(
                name: rx > 0.5 ? L("Cadre arrondi", "Rounded Box") : L("Rectangle", "Rectangle"),
                kind: .shape(ShapePayload(shapeType: shapeType, cornerRadius: rx)),
                frame: VectorRect(x: x, y: y, width: w, height: h),
                style: style
            )
            currentPage.elements.append(el)

        case "circle", "ellipse":
            let (off, sc) = currentTransform
            let cx = (parseDimension(attrs["cx"]) ?? 50) * sc.x + off.x
            let cy = (parseDimension(attrs["cy"]) ?? 50) * sc.y + off.y
            let rx: Double
            let ry: Double
            if name == "circle" {
                let r = parseDimension(attrs["r"]) ?? 25
                rx = r * sc.x
                ry = r * sc.y
            } else {
                rx = (parseDimension(attrs["rx"]) ?? 30) * sc.x
                ry = (parseDimension(attrs["ry"]) ?? 20) * sc.y
            }
            let style = buildStyle(from: attrs, defaultFill: nil)
            let el = VectorElement(
                name: L("Ellipse", "Ellipse"),
                kind: .shape(ShapePayload(shapeType: .ellipse)),
                frame: VectorRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2),
                style: style
            )
            currentPage.elements.append(el)

        case "line":
            let (off, sc) = currentTransform
            let x1 = (parseDimension(attrs["x1"]) ?? 0) * sc.x + off.x
            let y1 = (parseDimension(attrs["y1"]) ?? 0) * sc.y + off.y
            let x2 = (parseDimension(attrs["x2"]) ?? 80) * sc.x + off.x
            let y2 = (parseDimension(attrs["y2"]) ?? 80) * sc.y + off.y
            let pts = [VectorPoint(x: x1, y: y1), VectorPoint(x: x2, y: y2)]
            let (bounds, norm) = StrokeSmoother.normalizeStrokes([pts])
            var style = buildStyle(from: attrs, defaultFill: nil)
            if style.strokeColorHex == nil { style.strokeColorHex = "#111317" }
            let el = VectorElement(
                name: L("Ligne", "Line"),
                kind: .path(PathPayload(subpaths: [VectorSubpath(points: norm[0], isClosed: false)])),
                frame: bounds,
                style: style
            )
            currentPage.elements.append(el)

        case "polyline", "polygon":
            guard let rawPts = attrs["points"] else { return }
            let (off, sc) = currentTransform
            let coords = rawPts.split { $0 == " " || $0 == "," || $0.isNewline }.compactMap { Double($0) }
            var pts: [VectorPoint] = []
            var i = 0
            while i + 1 < coords.count {
                pts.append(VectorPoint(x: coords[i] * sc.x + off.x, y: coords[i + 1] * sc.y + off.y))
                i += 2
            }
            guard pts.count >= 2 else { return }
            let (bounds, norm) = StrokeSmoother.normalizeStrokes([pts])
            let style = buildStyle(from: attrs, defaultFill: name == "polygon" ? "#111317" : nil)
            let el = VectorElement(
                name: name == "polygon" ? L("Polygone", "Polygon") : L("Polyligne", "Polyline"),
                kind: .path(PathPayload(subpaths: [VectorSubpath(points: norm[0], isClosed: name == "polygon")])),
                frame: bounds,
                style: style
            )
            currentPage.elements.append(el)

        case "path":
            guard let d = attrs["d"], !d.isEmpty else { return }
            let (off, sc) = currentTransform
            let rawSubpaths = SVGCodec.parsePathData(d, offset: off, scale: sc)
            let allPoints = rawSubpaths.flatMap(\.points)
            guard !allPoints.isEmpty else { return }
            if groupStack.last?.isSignatureGroup == true {
                for sub in rawSubpaths {
                    signatureStrokesAccumulator.append(sub.points)
                }
                return
            }
            let bounds = VectorRect.bounding(allPoints, minSize: 4.0)
            let normSubpaths = rawSubpaths.map { sub in
                VectorSubpath(
                    points: sub.points.map { pt in
                        VectorPoint(
                            x: (pt.x - bounds.x) / max(1.0, bounds.width),
                            y: (pt.y - bounds.y) / max(1.0, bounds.height)
                        )
                    },
                    isClosed: sub.isClosed
                )
            }
            var style = buildStyle(from: attrs, defaultFill: nil)
            if style.strokeColorHex == nil && style.fillColorHex == nil {
                style.strokeColorHex = "#111317"
            }
            let el = VectorElement(
                name: attrs["id"] ?? L("Tracé vectoriel", "Vector Path"),
                kind: .path(PathPayload(subpaths: normSubpaths)),
                frame: bounds,
                style: style
            )
            currentPage.elements.append(el)

        case "text":
            if groupStack.last?.isSignatureGroup == true || groupStack.last?.isStampGroup == true {
                return
            }
            activeTextAttributes = attrs
            activeTextAccumulator = ""

        case "tspan":
            if activeTextAttributes != nil && !activeTextAccumulator.isEmpty {
                activeTextAccumulator += "\n"
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if activeTextAttributes != nil {
            activeTextAccumulator += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if name == "text", let attrs = activeTextAttributes {
            let trimmed = activeTextAccumulator.trimmingCharacters(in: .whitespacesAndNewlines)
            activeTextAttributes = nil
            activeTextAccumulator = ""
            guard !trimmed.isEmpty else { return }
            let (off, sc) = currentTransform
            let fontSize = (parseDimension(attrs["font-size"]) ?? 14.0) * sc.y
            let rawX = (parseDimension(attrs["x"]) ?? 24.0) * sc.x + off.x
            let rawY = (parseDimension(attrs["y"]) ?? (24.0 + fontSize)) * sc.y + off.y
            let isBold = (attrs["font-weight"]?.lowercased().contains("bold") == true) || (attrs["font-weight"] == "700")
            let isItalic = (attrs["font-style"]?.lowercased().contains("italic") == true)
            let fontFamily = attrs["font-family"]?.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\"", with: "") ?? "Helvetica Neue"
            let fillHex = normalizeColor(attrs["fill"]) ?? groupStack.last?.fillHex ?? "#111317"
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            let maxChars = max(4, lines.map(\.count).max() ?? 8)
            let estWidth = max(48.0, Double(maxChars) * fontSize * 0.56)
            let estHeight = max(fontSize * 1.25, Double(lines.count) * fontSize * 1.32)

            let alignment: TextAlignmentMode
            let boxX: Double
            switch attrs["text-anchor"]?.lowercased() {
            case "middle":
                alignment = .center
                boxX = rawX - estWidth * 0.5
            case "end":
                alignment = .right
                boxX = rawX - estWidth
            default:
                alignment = .left
                boxX = rawX
            }

            let el = VectorElement(
                name: String(trimmed.prefix(28)),
                kind: .text(TextPayload(
                    text: trimmed,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    isBold: isBold,
                    isItalic: isItalic,
                    alignment: alignment
                )),
                frame: VectorRect(x: boxX, y: max(0, rawY - fontSize), width: estWidth, height: estHeight),
                style: VectorStyle(strokeColorHex: nil, fillColorHex: fillHex, strokeWidth: 0, opacity: 1.0)
            )
            currentPage.elements.append(el)
        } else if name == "g" {
            guard let popped = groupStack.popLast() else { return }
            if popped.isPageGroup {
                pages.append(currentPage)
            } else if popped.isSignatureGroup, !signatureStrokesAccumulator.isEmpty {
                let signer = popped.signerName ?? "Adrien Mondot"
                let sigEl = VectorOperations.makeFreehandSignatureElement(
                    pageStrokes: signatureStrokesAccumulator,
                    signerName: signer,
                    colorHex: popped.strokeHex ?? "#1E3A8A"
                )
                currentPage.elements.append(sigEl)
                signatureStrokesAccumulator.removeAll()
            } else if popped.isStampGroup, let kind = popped.stampKind {
                let stampEl = VectorOperations.makeStampElement(
                    kind: kind,
                    at: VectorPoint(x: currentPage.width * 0.72, y: currentPage.height * 0.82)
                )
                currentPage.elements.append(stampEl)
            }
        }
    }

    // MARK: - Attribute Helpers

    private func mergedAttributes(_ dict: [String: String]) -> [String: String] {
        var out = dict
        if let styleStr = dict["style"] {
            for pair in styleStr.split(separator: ";") {
                let kv = pair.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 {
                    out[kv[0].lowercased()] = kv[1]
                }
            }
        }
        return out
    }

    private func buildStyle(from attrs: [String: String], defaultFill: String?) -> VectorStyle {
        let g = groupStack.last ?? GroupContext()
        let rawFill = attrs["fill"]
        let fillHex: String?
        if let rf = rawFill {
            fillHex = normalizeColor(rf)
        } else {
            fillHex = g.fillHex ?? defaultFill
        }
        let rawStroke = attrs["stroke"]
        let strokeHex: String?
        if let rs = rawStroke {
            strokeHex = normalizeColor(rs)
        } else {
            strokeHex = g.strokeHex
        }
        let sw = parseDimension(attrs["stroke-width"]) ?? g.strokeWidth ?? (strokeHex != nil ? 1.6 : 0.0)
        let op = Double(attrs["opacity"] ?? "") ?? g.opacity
        let dashed = attrs["stroke-dasharray"] != nil && attrs["stroke-dasharray"] != "none"
        return VectorStyle(strokeColorHex: strokeHex, fillColorHex: fillHex, strokeWidth: sw, opacity: op, dashed: dashed)
    }

    private func normalizeColor(_ raw: String?) -> String? {
        guard let c = RGBAColor(hex: raw) else { return nil }
        return c.hexString
    }

    private func parseDimension(_ raw: String?) -> Double? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "px", with: "")
            .replacingOccurrences(of: "pt", with: "")
        if cleaned.hasSuffix("mm"), let v = Double(cleaned.dropLast(2)) {
            return v * 72.0 / 25.4
        }
        return Double(cleaned)
    }

    private func parseTransform(_ raw: String) -> (Double, Double, Double, Double) {
        var tx = 0.0
        var ty = 0.0
        var sx = 1.0
        var sy = 1.0
        if let range = raw.range(of: "translate("),
           let end = raw[range.upperBound...].firstIndex(of: ")") {
            let inner = raw[range.upperBound..<end]
            let nums = inner.split { $0 == "," || $0 == " " }.compactMap { Double($0) }
            if let first = nums.first {
                tx = first
                ty = nums.count > 1 ? nums[1] : 0
            }
        }
        if let range = raw.range(of: "scale("),
           let end = raw[range.upperBound...].firstIndex(of: ")") {
            let inner = raw[range.upperBound..<end]
            let nums = inner.split { $0 == "," || $0 == " " }.compactMap { Double($0) }
            if let first = nums.first {
                sx = first
                sy = nums.count > 1 ? nums[1] : first
            }
        }
        return (tx, ty, sx, sy)
    }
}
