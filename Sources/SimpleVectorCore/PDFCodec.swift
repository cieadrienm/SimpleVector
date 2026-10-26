import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Native PDF importer, PDF text extractor, vector page renderer, and multi-page vector PDF writer.
/// Uses strictly `CoreGraphics`, `CoreText`, `PDFKit`, and `ImageIO` (no `AppKit` or `SwiftUI`, G30).
public enum PDFCodec {

    // MARK: - Import PDF & Extract Editable Text Blocks

    public static func importPDF(data: Data, title: String = "Document PDF", fileURL: URL? = nil) throws -> VectorDocument {
        guard let pdfDoc = PDFDocument(data: data), pdfDoc.pageCount > 0 else {
            throw NSError(domain: "PDFCodec", code: 1, userInfo: [
                NSLocalizedDescriptionKey: L("Fichier PDF invalide ou vide.", "Invalid or empty PDF file.")
            ])
        }

        var pages: [VectorPage] = []
        for i in 0..<pdfDoc.pageCount {
            guard let pdfPage = pdfDoc.page(at: i) else { continue }
            let box = pdfPage.bounds(for: .mediaBox)
            let w = max(64.0, Double(box.width))
            let h = max(64.0, Double(box.height))

            let singleDoc = PDFDocument()
            if let pageCopy = pdfPage.copy() as? PDFPage {
                singleDoc.insert(pageCopy, at: 0)
            }
            let singlePageData = singleDoc.dataRepresentation()
            let extractedElements = extractEditableTextElements(from: pdfPage, pageWidth: w, pageHeight: h)

            let page = VectorPage(
                title: "Page \(i + 1)",
                width: w,
                height: h,
                backgroundColorHex: "#FFFFFF",
                pdfPageData: singlePageData,
                pdfPageIndex: 0,
                redactedPDFRects: [],
                elements: extractedElements
            )
            pages.append(page)
        }

        return VectorDocument(
            title: title,
            sourceFormat: .pdf,
            fileURL: fileURL,
            pages: pages.isEmpty ? [VectorPage(title: "Page 1")] : pages
        )
    }

    /// Extracts editable text lines from a `PDFPage`, converting PDF bottom-left bounds into top-left `VectorRect`.
    public static func extractEditableTextElements(
        from pdfPage: PDFPage,
        pageWidth: Double,
        pageHeight: Double
    ) -> [VectorElement] {
        guard let fullString = pdfPage.string, !fullString.isEmpty else { return [] }
        let nsString = fullString as NSString
        let mediaBox = pdfPage.bounds(for: .mediaBox)
        var elements: [VectorElement] = []

        var index = 0
        while index < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            defer { index = NSMaxRange(lineRange) }

            let rawLine = nsString.substring(with: lineRange)
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Compute exact character range of the trimmed text inside lineRange
            let subRange = (rawLine as NSString).range(of: trimmed)
            let exactRange = subRange.location != NSNotFound
                ? NSRange(location: lineRange.location + subRange.location, length: subRange.length)
                : lineRange

            guard let sel = pdfPage.selection(for: exactRange) else { continue }
            let lineSelections = sel.selectionsByLine()
            let targets = lineSelections.isEmpty ? [sel] : lineSelections

            for lineSel in targets {
                let text = (lineSel.string ?? trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let pdfBounds = lineSel.bounds(for: pdfPage)
                guard pdfBounds.width > 1.5, pdfBounds.height > 2.0,
                      pdfBounds.width.isFinite, pdfBounds.height.isFinite else { continue }

                let relX = Double(pdfBounds.minX - mediaBox.minX)
                let relYFromBottom = Double(pdfBounds.maxY - mediaBox.minY)
                let topDownY = max(0.0, pageHeight - relYFromBottom)
                let rectW = max(24.0, Double(pdfBounds.width) + 4.0)
                let rectH = max(10.0, Double(pdfBounds.height) + 2.0)

                let estimatedFontSize = max(8.0, min(36.0, round(Double(pdfBounds.height) * 0.78)))
                let isLikelyHeader = estimatedFontSize >= 15.0

                let frameRect = VectorRect(
                    x: max(0, relX),
                    y: max(0, topDownY),
                    width: rectW,
                    height: rectH
                )

                let element = VectorElement(
                    name: String(text.prefix(32)),
                    kind: .text(TextPayload(
                        text: text,
                        fontFamily: "Helvetica Neue",
                        fontSize: estimatedFontSize,
                        isBold: isLikelyHeader,
                        isItalic: false,
                        alignment: .left,
                        isPDFExtracted: true,
                        originalPDFText: text,
                        originalPDFRect: frameRect,
                        maskColorHex: "#FFFFFF"
                    )),
                    frame: frameRect,
                    style: VectorStyle(strokeColorHex: nil, fillColorHex: "#111317", strokeWidth: 0, opacity: 1.0)
                )
                elements.append(element)
            }
        }
        return elements
    }

    // MARK: - Export Multi-Page Vector PDF

    public static func exportPDF(document: VectorDocument) throws -> Data {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw NSError(domain: "PDFCodec", code: 2, userInfo: [
                NSLocalizedDescriptionKey: L("Impossible d'initialiser le flux PDF.", "Failed to initialize PDF consumer.")
            ])
        }
        var defaultBox = CGRect(
            x: 0,
            y: 0,
            width: document.pages.first?.width ?? 595.28,
            height: document.pages.first?.height ?? 841.89
        )
        let pdfInfo: [CFString: Any] = [
            kCGPDFContextTitle: document.title,
            kCGPDFContextCreator: "SimpleVector — cie Adrien M"
        ]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &defaultBox, pdfInfo as CFDictionary) else {
            throw NSError(domain: "PDFCodec", code: 3, userInfo: [
                NSLocalizedDescriptionKey: L("Impossible de créer le contexte graphique PDF.", "Failed to create PDF graphics context.")
            ])
        }

        for page in document.pages {
            var pageBox = CGRect(x: 0, y: 0, width: page.width, height: page.height)
            let boxData = Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size) as CFData
            let pageDict: [CFString: Any] = [kCGPDFContextMediaBox: boxData]
            ctx.beginPDFPage(pageDict as CFDictionary)
            ctx.saveGState()
            // Flip from PDF bottom-left to SimpleVector top-left coordinate system
            ctx.translateBy(x: 0, y: CGFloat(page.height))
            ctx.scaleBy(x: 1, y: -1)
            renderPage(page, in: ctx)
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return pdfData as Data
    }

    // MARK: - Render Page to PNG (High-DPI Export & Thumbnailing)

    public static func renderPagePNG(page: VectorPage, scale: Double = 2.0) -> Data? {
        let pixelW = max(16, Int(round(page.width * scale)))
        let pixelH = max(16, Int(round(page.height * scale)))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip bitmap context so (0, 0) is top-left
        ctx.translateBy(x: 0, y: CGFloat(pixelH))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        renderPage(page, in: ctx)

        guard let cgImage = ctx.makeImage() else { return nil }
        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(outData as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return outData as Data
    }

    // MARK: - CoreGraphics Vector Page Renderer (Top-Left Origin)

    public static func renderPage(_ page: VectorPage, in ctx: CGContext) {
        let pageRect = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        ctx.saveGState()
        let bg = RGBAColor(hex: page.backgroundColorHex) ?? RGBAColor(r: 1, g: 1, b: 1)
        ctx.setFillColor(bg.cgColor)
        ctx.fill(pageRect)

        // 1. Original PDF vector backdrop if present
        if let pdfData = page.pdfPageData,
           let provider = CGDataProvider(data: pdfData as CFData),
           let cgPDF = CGPDFDocument(provider),
           let cgPage = cgPDF.page(at: max(1, page.pdfPageIndex + 1)) {
            ctx.saveGState()
            let mediaBox = cgPage.getBoxRect(.mediaBox)
            ctx.translateBy(x: 0, y: CGFloat(page.height))
            ctx.scaleBy(
                x: CGFloat(page.width) / max(1, mediaBox.width),
                y: -CGFloat(page.height) / max(1, mediaBox.height)
            )
            ctx.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
            ctx.drawPDFPage(cgPage)
            ctx.restoreGState()
        }

        // 2. Mask out edited, moved, or deleted PDF text blocks
        for mask in page.activeMaskRects {
            let maskColor = RGBAColor(hex: mask.colorHex) ?? bg
            ctx.setFillColor(maskColor.cgColor)
            ctx.fill(mask.rect.cgRect)
        }

        // 3. Draw vector elements in stacking order
        for element in page.elements where element.visible {
            if case .text(let t) = element.kind,
               t.isPDFExtracted,
               !element.hasModifiedPDFText,
               page.pdfPageData != nil {
                // Unmodified PDF text is already rendered by the native PDF page stream above
                continue
            }
            renderElement(element, in: ctx)
        }
        ctx.restoreGState()
    }

    public static func renderElement(_ el: VectorElement, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.setAlpha(CGFloat(el.style.opacity))
        let f = el.frame
        if abs(el.rotationDegrees) > 0.01 {
            ctx.translateBy(x: CGFloat(f.midX), y: CGFloat(f.midY))
            ctx.rotate(by: CGFloat(el.rotationDegrees * .pi / 180.0))
            ctx.translateBy(x: -CGFloat(f.midX), y: -CGFloat(f.midY))
        }

        if el.style.dashed {
            ctx.setLineDash(phase: 0, lengths: [6, 4])
        }

        let fillColor = RGBAColor(hex: el.style.fillColorHex)
        let strokeColor = RGBAColor(hex: el.style.strokeColorHex)
        let lineWidth = CGFloat(max(0.5, el.style.strokeWidth))

        switch el.kind {
        case .shape(let s):
            switch s.shapeType {
            case .rectangle:
                let rect = f.cgRect
                if let fillColor {
                    ctx.setFillColor(fillColor.cgColor)
                    ctx.fill(rect)
                }
                if let strokeColor, el.style.strokeWidth > 0 {
                    ctx.setStrokeColor(strokeColor.cgColor)
                    ctx.setLineWidth(lineWidth)
                    ctx.stroke(rect)
                }
            case .roundedRectangle:
                let r = CGFloat(min(s.cornerRadius, min(f.width, f.height) * 0.5))
                let path = CGPath(roundedRect: f.cgRect, cornerWidth: r, cornerHeight: r, transform: nil)
                if let fillColor {
                    ctx.setFillColor(fillColor.cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()
                }
                if let strokeColor, el.style.strokeWidth > 0 {
                    ctx.setStrokeColor(strokeColor.cgColor)
                    ctx.setLineWidth(lineWidth)
                    ctx.addPath(path)
                    ctx.strokePath()
                }
            case .ellipse:
                let rect = f.cgRect
                if let fillColor {
                    ctx.setFillColor(fillColor.cgColor)
                    ctx.fillEllipse(in: rect)
                }
                if let strokeColor, el.style.strokeWidth > 0 {
                    ctx.setStrokeColor(strokeColor.cgColor)
                    ctx.setLineWidth(lineWidth)
                    ctx.strokeEllipse(in: rect)
                }
            case .line, .arrow:
                let p0 = CGPoint(x: f.minX, y: f.maxY)
                let p1 = CGPoint(x: f.maxX, y: f.minY)
                let sc = strokeColor ?? fillColor ?? RGBAColor(r: 0.07, g: 0.07, b: 0.09)
                ctx.setStrokeColor(sc.cgColor)
                ctx.setLineWidth(lineWidth)
                ctx.setLineCap(.round)
                ctx.move(to: p0)
                ctx.addLine(to: p1)
                ctx.strokePath()
                if s.endArrow || s.shapeType == .arrow {
                    drawArrowHead(in: ctx, from: p0, to: p1, color: sc.cgColor, size: max(8, lineWidth * 4.0))
                }
                if s.startArrow {
                    drawArrowHead(in: ctx, from: p1, to: p0, color: sc.cgColor, size: max(8, lineWidth * 4.0))
                }
            case .diamond:
                let path = CGMutablePath()
                path.move(to: CGPoint(x: f.midX, y: f.minY))
                path.addLine(to: CGPoint(x: f.maxX, y: f.midY))
                path.addLine(to: CGPoint(x: f.midX, y: f.maxY))
                path.addLine(to: CGPoint(x: f.minX, y: f.midY))
                path.closeSubpath()
                if let fillColor {
                    ctx.setFillColor(fillColor.cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()
                }
                if let strokeColor, el.style.strokeWidth > 0 {
                    ctx.setStrokeColor(strokeColor.cgColor)
                    ctx.setLineWidth(lineWidth)
                    ctx.addPath(path)
                    ctx.strokePath()
                }
            }

        case .path(let p):
            let path = CGMutablePath()
            for sub in p.subpaths where !sub.points.isEmpty {
                let first = el.denormalize(sub.points[0]).cgPoint
                path.move(to: first)
                for pt in sub.points.dropFirst() {
                    path.addLine(to: el.denormalize(pt).cgPoint)
                }
                if sub.isClosed {
                    path.closeSubpath()
                }
            }
            if let fillColor {
                ctx.setFillColor(fillColor.cgColor)
                ctx.addPath(path)
                ctx.fillPath()
            }
            if let strokeColor, el.style.strokeWidth > 0 {
                ctx.setStrokeColor(strokeColor.cgColor)
                ctx.setLineWidth(lineWidth)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                ctx.addPath(path)
                ctx.strokePath()
            }

        case .signature(let sig):
            let ink = strokeColor ?? RGBAColor(hex: "#1E3A8A")!
            ctx.setStrokeColor(ink.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for stroke in sig.strokes where !stroke.isEmpty {
                ctx.move(to: el.denormalize(stroke[0]).cgPoint)
                for pt in stroke.dropFirst() {
                    ctx.addLine(to: el.denormalize(pt).cgPoint)
                }
                ctx.strokePath()
            }
            let meta = [sig.signerName, sig.caption, sig.dateLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !meta.isEmpty {
                drawCoreTextLine(
                    meta,
                    at: CGPoint(x: f.minX + 2, y: f.maxY - 2),
                    fontName: "HelveticaNeue",
                    fontSize: 8.5,
                    color: ink.cgColor,
                    alignment: .left,
                    boxWidth: f.width - 4,
                    in: ctx
                )
            }

        case .text(let t):
            let color = (fillColor ?? strokeColor ?? RGBAColor(r: 0.07, g: 0.07, b: 0.09)).cgColor
            let fontName: String
            if t.isBold && t.isItalic {
                fontName = "HelveticaNeue-BoldItalic"
            } else if t.isBold {
                fontName = "HelveticaNeue-Bold"
            } else if t.isItalic {
                fontName = "HelveticaNeue-Italic"
            } else {
                fontName = "HelveticaNeue"
            }
            let lines = t.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let lineH = t.fontSize * 1.28
            for (idx, line) in lines.enumerated() {
                let baselineY = f.minY + t.fontSize * 0.88 + Double(idx) * lineH
                drawCoreTextLine(
                    line,
                    at: CGPoint(x: f.minX, y: baselineY),
                    fontName: fontName,
                    fontSize: t.fontSize,
                    color: color,
                    alignment: t.alignment,
                    boxWidth: f.width,
                    in: ctx
                )
            }

        case .stamp(let st):
            let color = strokeColor ?? RGBAColor(hex: st.stampKind.defaultColorHex) ?? RGBAColor(r: 0.1, g: 0.6, b: 0.3)
            let outerPath = CGPath(roundedRect: f.cgRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.setFillColor(RGBAColor(r: color.r, g: color.g, b: color.b, a: 0.10).cgColor)
            ctx.addPath(outerPath)
            ctx.fillPath()
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(2.2)
            ctx.addPath(outerPath)
            ctx.strokePath()

            let innerRect = f.cgRect.insetBy(dx: 3.5, dy: 3.5)
            if innerRect.width > 4 && innerRect.height > 4 {
                let innerPath = CGPath(roundedRect: innerRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
                ctx.setLineWidth(0.9)
                ctx.addPath(innerPath)
                ctx.strokePath()
            }

            drawCoreTextLine(
                st.title,
                at: CGPoint(x: f.minX, y: f.minY + f.height * 0.52),
                fontName: "HelveticaNeue-Bold",
                fontSize: min(14.0, f.height * 0.30),
                color: color.cgColor,
                alignment: .center,
                boxWidth: f.width,
                in: ctx
            )
            if !st.subtitle.isEmpty {
                drawCoreTextLine(
                    st.subtitle,
                    at: CGPoint(x: f.minX, y: f.minY + f.height * 0.80),
                    fontName: "HelveticaNeue",
                    fontSize: min(9.0, f.height * 0.18),
                    color: color.cgColor,
                    alignment: .center,
                    boxWidth: f.width,
                    in: ctx
                )
            }
        }
    }

    private static func drawArrowHead(in ctx: CGContext, from p0: CGPoint, to p1: CGPoint, color: CGColor, size: CGFloat) {
        let angle = atan2(p1.y - p0.y, p1.x - p0.x)
        let wing: CGFloat = .pi / 6.5
        let left = CGPoint(x: p1.x - size * cos(angle - wing), y: p1.y - size * sin(angle - wing))
        let right = CGPoint(x: p1.x - size * cos(angle + wing), y: p1.y - size * sin(angle + wing))
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.move(to: p1)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawCoreTextLine(
        _ string: String,
        at origin: CGPoint,
        fontName: String,
        fontSize: Double,
        color: CGColor,
        alignment: TextAlignmentMode,
        boxWidth: Double,
        in ctx: CGContext
    ) {
        guard !string.isEmpty else { return }
        let ctFont = CTFontCreateWithName(fontName as CFString, CGFloat(fontSize), nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: ctFont,
            kCTForegroundColorAttributeName: color,
        ]
        guard let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, string as CFString, attrs as CFDictionary) else { return }
        let ctLine = CTLineCreateWithAttributedString(attrStr)
        let lineWidth = CTLineGetTypographicBounds(ctLine, nil, nil, nil)

        let drawX: CGFloat
        switch alignment {
        case .left:
            drawX = origin.x
        case .center:
            drawX = origin.x + CGFloat(max(0, (boxWidth - lineWidth) * 0.5))
        case .right:
            drawX = origin.x + CGFloat(max(0, boxWidth - lineWidth))
        }

        ctx.saveGState()
        // CoreText draws upright in bottom-up space; flip locally around the baseline point
        ctx.translateBy(x: drawX, y: origin.y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        CTLineDraw(ctLine, ctx)
        ctx.restoreGState()
    }
}
