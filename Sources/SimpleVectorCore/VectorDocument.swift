import CoreGraphics
import Foundation

// MARK: - Basic Geometry

public struct VectorPoint: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = VectorPoint(x: 0, y: 0)

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    public func distance(to other: VectorPoint) -> Double {
        hypot(other.x - x, other.y - y)
    }

    public func interpolated(to other: VectorPoint, t: Double) -> VectorPoint {
        VectorPoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }
}

public struct VectorRect: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = max(1.0, width)
        self.height = max(1.0, height)
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width * 0.5 }
    public var midY: Double { y + height * 0.5 }
    public var center: VectorPoint { VectorPoint(x: midX, y: midY) }
    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    public func contains(_ pt: VectorPoint, margin: Double = 0) -> Bool {
        pt.x >= minX - margin && pt.x <= maxX + margin &&
        pt.y >= minY - margin && pt.y <= maxY + margin
    }

    public func intersects(_ other: VectorRect) -> Bool {
        !(other.minX > maxX || other.maxX < minX || other.minY > maxY || other.maxY < minY)
    }

    public func insetBy(dx: Double, dy: Double) -> VectorRect {
        VectorRect(
            x: x + dx,
            y: y + dy,
            width: max(2.0, width - dx * 2),
            height: max(2.0, height - dy * 2)
        )
    }

    public func offsetBy(dx: Double, dy: Double) -> VectorRect {
        VectorRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    public static func bounding(_ points: [VectorPoint], minSize: Double = 8.0) -> VectorRect {
        guard let first = points.first else {
            return VectorRect(x: 0, y: 0, width: minSize, height: minSize)
        }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for p in points.dropFirst() {
            if p.x < minX { minX = p.x }
            if p.y < minY { minY = p.y }
            if p.x > maxX { maxX = p.x }
            if p.y > maxY { maxY = p.y }
        }
        let w = max(minSize, maxX - minX)
        let h = max(minSize, maxY - minY)
        return VectorRect(x: minX, y: minY, width: w, height: h)
    }
}

// MARK: - Style & Color Helpers

public struct RGBAColor: Equatable, Hashable, Codable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = min(1, max(0, r))
        self.g = min(1, max(0, g))
        self.b = min(1, max(0, b))
        self.a = min(1, max(0, a))
    }

    public init?(hex: String?) {
        guard let raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower == "none" || lower == "transparent" { return nil }
        switch lower {
        case "black": self.init(r: 0, g: 0, b: 0); return
        case "white": self.init(r: 1, g: 1, b: 1); return
        case "red": self.init(r: 1.0, g: 0.36, b: 0.34); return
        case "blue", "navy": self.init(r: 0.12, g: 0.25, b: 0.69); return
        case "green": self.init(r: 0.16, g: 0.62, b: 0.36); return
        case "amber", "orange", "gold": self.init(r: 1.0, g: 0.706, b: 0.329); return
        case "cyan": self.init(r: 0.36, g: 0.88, b: 0.90); return
        case "purple", "violet": self.init(r: 0.78, g: 0.57, b: 0.92); return
        case "gray", "grey": self.init(r: 0.54, g: 0.57, b: 0.62); return
        default: break
        }
        if lower.hasPrefix("rgb("), lower.hasSuffix(")") {
            let inner = lower.dropFirst(4).dropLast()
            let comps = inner.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if comps.count >= 3 {
                self.init(r: comps[0] / 255.0, g: comps[1] / 255.0, b: comps[2] / 255.0)
                return
            }
        }
        var cleaned = lower
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        if cleaned.count == 3 {
            let chars = Array(cleaned)
            cleaned = String([chars[0], chars[0], chars[1], chars[1], chars[2], chars[2]])
        }
        guard cleaned.count == 6 || cleaned.count == 8,
              let val = UInt64(cleaned, radix: 16) else { return nil }
        if cleaned.count == 6 {
            self.init(
                r: Double((val >> 16) & 0xFF) / 255.0,
                g: Double((val >> 8) & 0xFF) / 255.0,
                b: Double(val & 0xFF) / 255.0,
                a: 1.0
            )
        } else {
            self.init(
                r: Double((val >> 24) & 0xFF) / 255.0,
                g: Double((val >> 16) & 0xFF) / 255.0,
                b: Double((val >> 8) & 0xFF) / 255.0,
                a: Double(val & 0xFF) / 255.0
            )
        }
    }

    public var hexString: String {
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}

public struct VectorStyle: Equatable, Hashable, Codable, Sendable {
    public var strokeColorHex: String?
    public var fillColorHex: String?
    public var strokeWidth: Double
    public var opacity: Double
    public var dashed: Bool

    public init(
        strokeColorHex: String? = "#111317",
        fillColorHex: String? = nil,
        strokeWidth: Double = 1.8,
        opacity: Double = 1.0,
        dashed: Bool = false
    ) {
        self.strokeColorHex = strokeColorHex
        self.fillColorHex = fillColorHex
        self.strokeWidth = max(0, strokeWidth)
        self.opacity = min(1.0, max(0.05, opacity))
        self.dashed = dashed
    }

    public static let defaultInk = VectorStyle(strokeColorHex: "#1E3A8A", fillColorHex: nil, strokeWidth: 2.0)
    public static let defaultShape = VectorStyle(strokeColorHex: "#111317", fillColorHex: "#FFB454", strokeWidth: 1.8, opacity: 1.0)
    public static let defaultText = VectorStyle(strokeColorHex: nil, fillColorHex: "#111317", strokeWidth: 0, opacity: 1.0)
}

// MARK: - Element Payloads

public enum TextAlignmentMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case left
    case center
    case right

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .left: return L("Gauche", "Left")
        case .center: return L("Centré", "Center")
        case .right: return L("Droite", "Right")
        }
    }

    public var symbol: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }
}

public struct TextPayload: Equatable, Hashable, Codable, Sendable {
    public var text: String
    public var fontFamily: String
    public var fontSize: Double
    public var isBold: Bool
    public var isItalic: Bool
    public var alignment: TextAlignmentMode
    public var isPDFExtracted: Bool
    public var originalPDFText: String?
    public var originalPDFRect: VectorRect?
    public var maskColorHex: String

    public init(
        text: String,
        fontFamily: String = "Helvetica Neue",
        fontSize: Double = 14.0,
        isBold: Bool = false,
        isItalic: Bool = false,
        alignment: TextAlignmentMode = .left,
        isPDFExtracted: Bool = false,
        originalPDFText: String? = nil,
        originalPDFRect: VectorRect? = nil,
        maskColorHex: String = "#FFFFFF"
    ) {
        self.text = text
        self.fontFamily = fontFamily
        self.fontSize = max(6.0, fontSize)
        self.isBold = isBold
        self.isItalic = isItalic
        self.alignment = alignment
        self.isPDFExtracted = isPDFExtracted
        self.originalPDFText = originalPDFText
        self.originalPDFRect = originalPDFRect
        self.maskColorHex = maskColorHex
    }
}

public struct SignaturePayload: Equatable, Hashable, Codable, Sendable {
    public var signerName: String
    public var dateLabel: String?
    public var caption: String?
    /// Normalized strokes inside `0.0 ... 1.0` of the element's `frame`.
    public var strokes: [[VectorPoint]]

    public init(
        signerName: String,
        dateLabel: String? = nil,
        caption: String? = nil,
        strokes: [[VectorPoint]]
    ) {
        self.signerName = signerName
        self.dateLabel = dateLabel
        self.caption = caption
        self.strokes = strokes
    }
}

public struct VectorSubpath: Equatable, Hashable, Codable, Sendable {
    /// Normalized points `0.0 ... 1.0` inside the element's `frame`.
    public var points: [VectorPoint]
    public var isClosed: Bool

    public init(points: [VectorPoint], isClosed: Bool = false) {
        self.points = points
        self.isClosed = isClosed
    }
}

public struct PathPayload: Equatable, Hashable, Codable, Sendable {
    public var subpaths: [VectorSubpath]
    public var startArrow: Bool
    public var endArrow: Bool
    public var smoothCurves: Bool

    public init(
        subpaths: [VectorSubpath],
        startArrow: Bool = false,
        endArrow: Bool = false,
        smoothCurves: Bool = true
    ) {
        self.subpaths = subpaths
        self.startArrow = startArrow
        self.endArrow = endArrow
        self.smoothCurves = smoothCurves
    }
}

public enum VectorShapeType: String, CaseIterable, Identifiable, Codable, Sendable {
    case rectangle
    case roundedRectangle
    case ellipse
    case line
    case arrow
    case diamond

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .rectangle: return L("Rectangle", "Rectangle")
        case .roundedRectangle: return L("Cadre arrondi", "Rounded Box")
        case .ellipse: return L("Cercle / Ellipse", "Circle / Ellipse")
        case .line: return L("Ligne", "Line")
        case .arrow: return L("Flèche", "Arrow")
        case .diamond: return L("Losange", "Diamond")
        }
    }

    public var symbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .roundedRectangle: return "rectangle.roundedtop"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .diamond: return "diamond"
        }
    }
}

public struct ShapePayload: Equatable, Hashable, Codable, Sendable {
    public var shapeType: VectorShapeType
    public var cornerRadius: Double
    public var startArrow: Bool
    public var endArrow: Bool

    public init(
        shapeType: VectorShapeType = .rectangle,
        cornerRadius: Double = 8.0,
        startArrow: Bool = false,
        endArrow: Bool = false
    ) {
        self.shapeType = shapeType
        self.cornerRadius = max(0, cornerRadius)
        self.startArrow = startArrow
        self.endArrow = endArrow || shapeType == .arrow
    }
}

public enum VectorStampKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case approved
    case signed
    case stagePlot
    case confidential
    case draft
    case check
    case cross

    public var id: String { rawValue }

    public var defaultTitle: String {
        switch self {
        case .approved: return L("BON POUR ACCORD", "APPROVED")
        case .signed: return L("SIGNÉ & VALIDÉ", "SIGNED & VERIFIED")
        case .stagePlot: return L("RÉGIE PLATEAU", "STAGE CONTROL")
        case .confidential: return L("CONFIDENTIEL", "CONFIDENTIAL")
        case .draft: return L("VERSION DE TRAVAIL", "WORKING DRAFT")
        case .check: return L("✓ CONFORME", "✓ VERIFIED")
        case .cross: return L("✗ À CORRIGER", "✗ REVISE")
        }
    }

    public var defaultColorHex: String {
        switch self {
        case .approved, .check: return "#16A34A"
        case .signed: return "#1E3A8A"
        case .stagePlot: return "#D97706"
        case .confidential, .cross: return "#DC2626"
        case .draft: return "#6B7280"
        }
    }
}

public struct StampPayload: Equatable, Hashable, Codable, Sendable {
    public var stampKind: VectorStampKind
    public var title: String
    public var subtitle: String

    public init(stampKind: VectorStampKind = .approved, title: String? = nil, subtitle: String? = nil) {
        self.stampKind = stampKind
        self.title = title ?? stampKind.defaultTitle
        if let subtitle {
            self.subtitle = subtitle
        } else {
            let df = DateFormatter()
            df.dateFormat = "dd/MM/yyyy"
            self.subtitle = "cie Adrien M · \(df.string(from: Date()))"
        }
    }
}

public enum VectorElementKind: Equatable, Hashable, Codable, Sendable {
    case text(TextPayload)
    case signature(SignaturePayload)
    case path(PathPayload)
    case shape(ShapePayload)
    case stamp(StampPayload)
}

// MARK: - VectorElement

public struct VectorElement: Identifiable, Equatable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: VectorElementKind
    public var frame: VectorRect
    public var rotationDegrees: Double
    public var style: VectorStyle
    public var visible: Bool
    public var locked: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: VectorElementKind,
        frame: VectorRect,
        rotationDegrees: Double = 0,
        style: VectorStyle = .defaultShape,
        visible: Bool = true,
        locked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.frame = frame
        self.rotationDegrees = rotationDegrees
        self.style = style
        self.visible = visible
        self.locked = locked
    }

    public var typeSymbol: String {
        switch kind {
        case .text(let t): return t.isPDFExtracted ? "doc.text.magnifyingglass" : "textformat"
        case .signature: return "signature"
        case .path: return "scribble.variable"
        case .shape(let s): return s.shapeType.symbol
        case .stamp: return "seal.fill"
        }
    }

    public var typeBadge: String {
        switch kind {
        case .text(let t): return t.isPDFExtracted ? "PDF TXT" : "TEXTE"
        case .signature: return "SIGN"
        case .path: return "PATH"
        case .shape(let s): return s.shapeType.label.uppercased()
        case .stamp: return "TAMPON"
        }
    }

    public var displayTitle: String {
        switch kind {
        case .text(let t):
            let trimmed = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return String(trimmed.prefix(36))
            }
            return name
        case .signature(let sig):
            return "\(L("Signature", "Signature")) — \(sig.signerName)"
        case .stamp(let st):
            return st.title
        default:
            return name
        }
    }

    /// True if this element was extracted from a PDF text run and its text, position, or style has been modified.
    public var hasModifiedPDFText: Bool {
        guard case .text(let t) = kind, t.isPDFExtracted else { return false }
        if let origText = t.originalPDFText, origText != t.text {
            return true
        }
        if let origRect = t.originalPDFRect {
            if abs(origRect.x - frame.x) > 0.5 ||
               abs(origRect.y - frame.y) > 0.5 ||
               abs(origRect.width - frame.width) > 1.0 ||
               abs(origRect.height - frame.height) > 1.0 {
                return true
            }
        }
        if style.fillColorHex != nil && style.fillColorHex?.uppercased() != "#111317" {
            return true
        }
        return false
    }

    /// Converts a normalized point `(0...1, 0...1)` into page coordinates using `frame`.
    public func denormalize(_ pt: VectorPoint) -> VectorPoint {
        VectorPoint(
            x: frame.x + pt.x * frame.width,
            y: frame.y + pt.y * frame.height
        )
    }
}

// MARK: - Page & Document

public enum PageFormatPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case a4Portrait = "A4 Portrait"
    case a4Landscape = "A4 Paysage"
    case a3Landscape = "A3 Paysage"
    case letter = "US Letter"
    case stage16x9 = "16:9 Régie"

    public var id: String { rawValue }

    public var sizePoints: (width: Double, height: Double) {
        switch self {
        case .a4Portrait: return (595.28, 841.89)
        case .a4Landscape: return (841.89, 595.28)
        case .a3Landscape: return (1190.55, 841.89)
        case .letter: return (612.0, 792.0)
        case .stage16x9: return (960.0, 540.0)
        }
    }

    public var label: String {
        switch self {
        case .a4Portrait: return L("A4 Portrait (210 × 297 mm)", "A4 Portrait (210 × 297 mm)")
        case .a4Landscape: return L("A4 Paysage (297 × 210 mm)", "A4 Landscape (297 × 210 mm)")
        case .a3Landscape: return L("A3 Paysage (420 × 297 mm)", "A3 Landscape (420 × 297 mm)")
        case .letter: return L("US Letter (216 × 279 mm)", "US Letter (8.5 × 11 in)")
        case .stage16x9: return L("Plan 16:9 (960 × 540 pt)", "16:9 Stage Plot (960 × 540 pt)")
        }
    }
}

public struct VectorPage: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var width: Double
    public var height: Double
    public var backgroundColorHex: String
    /// Optional single-page PDF data backing this page for 100% faithful vector PDF rendering.
    public var pdfPageData: Data?
    public var pdfPageIndex: Int
    /// Rectangles of original PDF text blocks that were deleted by the user (covered with paper background).
    public var redactedPDFRects: [VectorRect]
    public var elements: [VectorElement]

    public init(
        id: UUID = UUID(),
        title: String,
        width: Double = 595.28,
        height: Double = 841.89,
        backgroundColorHex: String = "#FFFFFF",
        pdfPageData: Data? = nil,
        pdfPageIndex: Int = 0,
        redactedPDFRects: [VectorRect] = [],
        elements: [VectorElement] = []
    ) {
        self.id = id
        self.title = title
        self.width = max(64.0, width)
        self.height = max(64.0, height)
        self.backgroundColorHex = backgroundColorHex
        self.pdfPageData = pdfPageData
        self.pdfPageIndex = pdfPageIndex
        self.redactedPDFRects = redactedPDFRects
        self.elements = elements
    }

    public var sizeMM: (width: Int, height: Int) {
        let wMM = Int(round(width * 25.4 / 72.0))
        let hMM = Int(round(height * 25.4 / 72.0))
        return (wMM, hMM)
    }

    public var dimensionsLabel: String {
        let mm = sizeMM
        return "\(Int(round(width)))×\(Int(round(height))) pt (\(mm.width)×\(mm.height) mm)"
    }

    /// Returns all PDF rectangles that must be masked out because their extracted text was edited, moved, or deleted.
    public var activeMaskRects: [(rect: VectorRect, colorHex: String)] {
        var result: [(VectorRect, String)] = redactedPDFRects.map { ($0.insetBy(dx: -1.5, dy: -1.0), backgroundColorHex) }
        for el in elements {
            if case .text(let payload) = el.kind, payload.isPDFExtracted {
                if el.hasModifiedPDFText || !el.visible {
                    if let orig = payload.originalPDFRect {
                        result.append((orig.insetBy(dx: -1.5, dy: -1.0), payload.maskColorHex))
                    }
                }
            }
        }
        return result
    }
}

public enum DocumentSourceFormat: String, Codable, Sendable {
    case svg = "SVG"
    case pdf = "PDF"
    case native = "SimpleVector"
}

public struct VectorDocument: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var sourceFormat: DocumentSourceFormat
    public var fileURL: URL?
    public var pages: [VectorPage]
    public var revision: Int

    public init(
        id: UUID = UUID(),
        title: String = L("Sans titre", "Untitled"),
        sourceFormat: DocumentSourceFormat = .svg,
        fileURL: URL? = nil,
        pages: [VectorPage] = [VectorPage(title: "Page 1")],
        revision: Int = 1
    ) {
        self.id = id
        self.title = title
        self.sourceFormat = sourceFormat
        self.fileURL = fileURL
        self.pages = pages.isEmpty ? [VectorPage(title: "Page 1")] : pages
        self.revision = revision
    }

    public var totalElementsCount: Int {
        pages.reduce(0) { $0 + $1.elements.count }
    }

    public var pdfTextElementCount: Int {
        pages.reduce(0) { acc, page in
            acc + page.elements.filter {
                if case .text(let t) = $0.kind { return t.isPDFExtracted }
                return false
            }.count
        }
    }

    public var modifiedPDFTextCount: Int {
        pages.reduce(0) { acc, page in
            acc + page.elements.filter(\.hasModifiedPDFText).count + page.redactedPDFRects.count
        }
    }

    public var signatureCount: Int {
        pages.reduce(0) { acc, page in
            acc + page.elements.filter {
                if case .signature = $0.kind { return true }
                return false
            }.count
        }
    }
}

// MARK: - Freehand & Signature Smoothing

public enum StrokeSmoother {
    /// Simplifies and smooths a raw point sequence using radial distance filtering + Chaikin corner-cutting.
    public static func smooth(_ rawPoints: [VectorPoint], iterations: Int = 2) -> [VectorPoint] {
        guard rawPoints.count > 2 else { return rawPoints }
        var filtered: [VectorPoint] = [rawPoints[0]]
        for pt in rawPoints.dropFirst() {
            if let last = filtered.last, last.distance(to: pt) >= 1.2 {
                filtered.append(pt)
            }
        }
        if let lastRaw = rawPoints.last, filtered.last != lastRaw {
            filtered.append(lastRaw)
        }
        guard filtered.count > 2 else { return filtered }

        var pts = filtered
        for _ in 0..<max(1, iterations) {
            guard pts.count >= 3 else { break }
            var next: [VectorPoint] = [pts[0]]
            for i in 0..<(pts.count - 1) {
                let p0 = pts[i]
                let p1 = pts[i + 1]
                next.append(VectorPoint(x: 0.75 * p0.x + 0.25 * p1.x, y: 0.75 * p0.y + 0.25 * p1.y))
                next.append(VectorPoint(x: 0.25 * p0.x + 0.75 * p1.x, y: 0.25 * p0.y + 0.75 * p1.y))
            }
            next.append(pts[pts.count - 1])
            pts = next
        }
        return pts
    }

    /// Normalizes a list of page-space strokes into `(frame, normalizedStrokes)` in `0...1`.
    public static func normalizeStrokes(_ pageStrokes: [[VectorPoint]]) -> (frame: VectorRect, strokes: [[VectorPoint]]) {
        let allPoints = pageStrokes.flatMap { $0 }
        let bounds = VectorRect.bounding(allPoints, minSize: 16.0)
        let normalized = pageStrokes.map { stroke in
            stroke.map { pt in
                VectorPoint(
                    x: (pt.x - bounds.x) / max(1.0, bounds.width),
                    y: (pt.y - bounds.y) / max(1.0, bounds.height)
                )
            }
        }
        return (bounds, normalized)
    }
}

// MARK: - Calligraphic Signature Presets

public struct SignaturePreset: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var signerName: String
    public var caption: String
    public var colorHex: String
    public var strokes: [[VectorPoint]]

    public init(
        id: UUID = UUID(),
        title: String,
        signerName: String,
        caption: String,
        colorHex: String = "#1E3A8A",
        strokes: [[VectorPoint]]
    ) {
        self.id = id
        self.title = title
        self.signerName = signerName
        self.caption = caption
        self.colorHex = colorHex
        self.strokes = strokes
    }

    public static let defaults: [SignaturePreset] = [
        SignaturePreset(
            title: "Adrien Mondot",
            signerName: "Adrien Mondot",
            caption: "cie Adrien M",
            colorHex: "#1E3A8A",
            strokes: calligraphicStrokes(seed: 1)
        ),
        SignaturePreset(
            title: L("Paraphe AM", "Initials AM"),
            signerName: "A. M.",
            caption: "Compagnie Adrien M",
            colorHex: "#111317",
            strokes: paraphStrokes()
        ),
        SignaturePreset(
            title: L("Visa Régie Générale", "Stage Manager Visa"),
            signerName: "Régie cie Adrien M",
            caption: L("Bon pour exécution", "Approved for stage"),
            colorHex: "#0F766E",
            strokes: calligraphicStrokes(seed: 2)
        ),
    ]

    /// Generates an expressive, calligraphic normalized vector signature (`0...1` coordinates).
    public static func calligraphicStrokes(seed: Int = 1) -> [[VectorPoint]] {
        var mainStroke: [VectorPoint] = []
        let steps = 64
        let phase = Double(seed) * 0.65
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            // Sweeping initial capital + flowing cursive wave + ascending flourish
            let x = 0.04 + t * 0.88 + 0.035 * sin(t * .pi * 7.0 + phase)
            let envelope = (1.0 - t * 0.55)
            let yBase = 0.62 - t * 0.16
            let yWave = sin(t * .pi * 9.5 + phase) * 0.24 * envelope
                + cos(t * .pi * 4.0) * 0.12 * envelope
            let y = min(0.92, max(0.08, yBase + yWave))
            mainStroke.append(VectorPoint(x: x, y: y))
        }

        // Underlying flourish stroke
        var underline: [VectorPoint] = []
        for i in 0...24 {
            let t = Double(i) / 24.0
            let x = 0.10 + t * 0.84
            let y = 0.84 - sin(t * .pi) * 0.09 - t * 0.05
            underline.append(VectorPoint(x: x, y: y))
        }

        return [mainStroke, underline]
    }

    public static func paraphStrokes() -> [[VectorPoint]] {
        let aStroke: [VectorPoint] = [
            VectorPoint(x: 0.08, y: 0.85),
            VectorPoint(x: 0.24, y: 0.12),
            VectorPoint(x: 0.38, y: 0.82),
            VectorPoint(x: 0.14, y: 0.52),
            VectorPoint(x: 0.44, y: 0.48),
        ]
        let mStroke: [VectorPoint] = [
            VectorPoint(x: 0.46, y: 0.80),
            VectorPoint(x: 0.54, y: 0.18),
            VectorPoint(x: 0.66, y: 0.66),
            VectorPoint(x: 0.78, y: 0.16),
            VectorPoint(x: 0.92, y: 0.78),
        ]
        let flourish: [VectorPoint] = [
            VectorPoint(x: 0.12, y: 0.90),
            VectorPoint(x: 0.52, y: 0.83),
            VectorPoint(x: 0.94, y: 0.72),
        ]
        return [
            StrokeSmoother.smooth(aStroke, iterations: 2),
            StrokeSmoother.smooth(mStroke, iterations: 2),
            StrokeSmoother.smooth(flourish, iterations: 2),
        ]
    }
}
