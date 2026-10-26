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
        // Register all embedded PDF fonts (and auto-complete subset open fonts) BEFORE PDFDocument/PDFSelection
        // parses attributed strings so PDFKit resolves the exact original fonts instead of falling back to Helvetica.
        PDFEmbeddedFontRegistry.shared.registerFonts(fromPDFData: data)

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

            let extractedElements = extractEditableTextElements(
                from: pdfPage,
                singlePageData: data,
                pageIndex: i,
                pageWidth: w,
                pageHeight: h
            )

            let page = VectorPage(
                title: "Page \(i + 1)",
                width: w,
                height: h,
                backgroundColorHex: "#FFFFFF",
                pdfPageData: data,
                pdfPageIndex: i,
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

    /// Extracts editable text lines from a `PDFPage`, splitting multi-column lines and measuring exact font,
    /// baseline, text color, tight glyph bounds, and background mask color.
    public static func extractEditableTextElements(
        from pdfPage: PDFPage,
        singlePageData: Data? = nil,
        pageIndex: Int = 0,
        pageWidth: Double,
        pageHeight: Double
    ) -> [VectorElement] {
        guard let fullString = pdfPage.string, !fullString.isEmpty else { return [] }
        let nsString = fullString as NSString
        let mediaBox = pdfPage.bounds(for: .mediaBox)

        let bitmapAnalyzer = PDFPageBitmapAnalyzer(
            pdfPage: pdfPage,
            singlePageData: singlePageData,
            pageIndex: pageIndex,
            pageWidth: pageWidth,
            pageHeight: pageHeight
        )

        var elements: [VectorElement] = []
        var index = 0

        while index < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            defer { index = NSMaxRange(lineRange) }

            let rawLine = nsString.substring(with: lineRange)
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let subRange = (rawLine as NSString).range(of: trimmed)
            let exactRange = subRange.location != NSNotFound
                ? NSRange(location: lineRange.location + subRange.location, length: subRange.length)
                : lineRange

            let columnRanges = splitIntoColumnRanges(in: pdfPage, fullString: nsString, range: exactRange)
            for colRange in columnRanges {
                guard let sel = pdfPage.selection(for: colRange) else { continue }
                let lineSelections = sel.selectionsByLine()
                let targets: [PDFSelection]
                if lineSelections.count <= 1 {
                    targets = [sel]
                } else {
                    let firstBounds = lineSelections[0].bounds(for: pdfPage)
                    let refH = max(8.0, firstBounds.height)
                    let allSameRow = lineSelections.allSatisfy {
                        abs($0.bounds(for: pdfPage).midY - firstBounds.midY) <= refH * 0.55
                    }
                    targets = allSameRow ? [sel] : lineSelections
                }

                for lineSel in targets {
                    guard let element = buildExtractedTextElement(
                        from: lineSel,
                        in: pdfPage,
                        mediaBox: mediaBox,
                        pageWidth: pageWidth,
                        pageHeight: pageHeight,
                        bitmapAnalyzer: bitmapAnalyzer
                    ) else { continue }
                    elements.append(element)
                }
            }
        }
        return elements
    }

    /// Splits a line range into separate column ranges whenever consecutive words have a large horizontal gap
    /// (e.g., left-column reference and right-column date on the same horizontal row).
    private static func splitIntoColumnRanges(
        in pdfPage: PDFPage,
        fullString: NSString,
        range: NSRange
    ) -> [NSRange] {
        var wordRanges: [(NSRange, CGRect)] = []
        fullString.enumerateSubstrings(
            in: range,
            options: [.byWords, .substringNotRequired]
        ) { _, wordRange, _, _ in
            if let wordSel = pdfPage.selection(for: wordRange) {
                let b = wordSel.bounds(for: pdfPage)
                if b.width > 0.5 && b.height > 1.0 && b.width.isFinite && b.height.isFinite {
                    wordRanges.append((wordRange, b))
                }
            }
        }

        guard wordRanges.count >= 2 else { return [range] }

        var groups: [NSRange] = []
        var currentStart = range.location
        var prevBounds = wordRanges[0].1

        for i in 1..<wordRanges.count {
            let (wRange, wBounds) = wordRanges[i]
            let refH = max(8.0, min(prevBounds.height, wBounds.height))
            let horizGap = wBounds.minX - prevBounds.maxX
            let vertDiff = abs(wBounds.midY - prevBounds.midY)

            // Also check if the substring between the two words contains 2+ spaces or a tab
            let betweenStart = NSMaxRange(wordRanges[i - 1].0)
            let betweenLen = max(0, wRange.location - betweenStart)
            let betweenStr = betweenLen > 0 ? fullString.substring(with: NSRange(location: betweenStart, length: betweenLen)) : ""
            let hasMultiSpace = betweenStr.contains("\t") || betweenStr.contains("   ")

            if horizGap > max(18.0, refH * 1.65) || (hasMultiSpace && horizGap > max(10.0, refH * 0.9)) || vertDiff > refH * 0.65 {
                let groupEnd = NSMaxRange(wordRanges[i - 1].0)
                if groupEnd > currentStart {
                    groups.append(NSRange(location: currentStart, length: groupEnd - currentStart))
                }
                currentStart = wRange.location
            }
            prevBounds = wBounds
        }

        let finalEnd = NSMaxRange(range)
        if finalEnd > currentStart {
            groups.append(NSRange(location: currentStart, length: finalEnd - currentStart))
        }
        return groups.isEmpty ? [range] : groups
    }

    private static func buildExtractedTextElement(
        from lineSel: PDFSelection,
        in pdfPage: PDFPage,
        mediaBox: CGRect,
        pageWidth: Double,
        pageHeight: Double,
        bitmapAnalyzer: PDFPageBitmapAnalyzer?
    ) -> VectorElement? {
        let rawText = (lineSel.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return nil }

        let pdfBounds = lineSel.bounds(for: pdfPage)
        guard pdfBounds.width > 1.5, pdfBounds.height > 2.0,
              pdfBounds.width.isFinite, pdfBounds.height.isFinite else { return nil }

        // 1. Convert PDF bottom-left selection box to top-left page coordinates
        let selX = max(0.0, Double(pdfBounds.minX - mediaBox.minX))
        let selTopY = max(0.0, pageHeight - Double(pdfBounds.maxY - mediaBox.minY))
        let selW = Double(pdfBounds.width)
        let selH = Double(pdfBounds.height)
        let selectionRect = VectorRect(x: selX, y: selTopY, width: selW, height: selH)

        // 2. Extract font & color attributes from PDFSelection.attributedString
        let attrInfo = extractAttributedFontAndColor(from: lineSel, fallbackHeight: selH)

        // 3. Analyze the rendered PDF bitmap inside selectionRect for exact background color, ink color,
        //    tight glyph bounding box, and sub-point baseline position
        let bitmapMetrics = bitmapAnalyzer?.analyzeTextRegion(
            selectionRect: selectionRect,
            text: rawText,
            expectedFontSize: attrInfo.fontSize
        )

        let maskColorHex = bitmapMetrics?.maskColorHex ?? "#FFFFFF"
        let textColorHex = bitmapMetrics?.inkColorHex ?? attrInfo.colorHex ?? "#111317"
        let effectiveIsBold = attrInfo.isBold || (bitmapMetrics?.appearsBold ?? false)
        let tightInk = bitmapMetrics?.tightInkRect ?? selectionRect
        // Preserve the exact typographical X origin (`selX = pdfBounds.minX - mediaBox.minX`) so the first glyph's
        // native Left Side Bearing (LSB) is never added twice, while using `tightInk` for vertical ink bounds.
        let tightFrame = VectorRect(
            x: selX,
            y: tightInk.y,
            width: max(selW, tightInk.maxX - selX),
            height: tightInk.height
        )

        // 4. Keep exact PDF font size when attributedString provides it; otherwise calibrate from measured cap-height
        var fontSize = attrInfo.fontSize
        let tempPayload = TextPayload(
            text: rawText,
            fontFamily: attrInfo.fontFamily,
            postScriptFontName: attrInfo.postScriptName,
            fontSize: fontSize,
            isBold: effectiveIsBold,
            isItalic: attrInfo.isItalic
        )

        if !attrInfo.hadExplicitFont, let metrics = bitmapMetrics, metrics.hasReliableCapHeight {
            let unitFont = resolveCTFont(for: tempPayload, size: 100.0)
            let capRatio = Double(CTFontGetCapHeight(unitFont)) / 100.0
            if capRatio > 0.35 {
                let capMatchedSize = (metrics.measuredCapHeight - 0.35) / capRatio
                fontSize = max(5.5, min(72.0, capMatchedSize))
            }
        }

        // 5. Compute baseline offset from tightFrame.minY
        let resolvedFont = resolveCTFont(
            for: TextPayload(
                text: rawText,
                fontFamily: attrInfo.fontFamily,
                postScriptFontName: attrInfo.postScriptName,
                fontSize: fontSize,
                isBold: effectiveIsBold,
                isItalic: attrInfo.isItalic
            ),
            size: CGFloat(fontSize)
        )
        let capH = Double(CTFontGetCapHeight(resolvedFont))
        let ascent = Double(CTFontGetAscent(resolvedFont))
        let pdfTypographicalBaselineY = selTopY + ascent
        let baselineOffset: Double
        if let metrics = bitmapMetrics {
            let bitmapBaselineY = metrics.baselineY
            let chosenBaselineY: Double
            if attrInfo.hadExplicitFont && abs(pdfTypographicalBaselineY - bitmapBaselineY) <= 1.2 {
                chosenBaselineY = pdfTypographicalBaselineY
            } else {
                chosenBaselineY = bitmapBaselineY
            }
            baselineOffset = max(capH * 0.88, min(tightFrame.height + 1.5, chosenBaselineY - tightFrame.y))
        } else {
            baselineOffset = attrInfo.hadExplicitFont ? max(capH, pdfTypographicalBaselineY - tightFrame.y) : capH
        }

        // 6. Compute subtle letter-spacing only if the PDF font was substituted by a fallback font
        var letterSpacing = 0.0
        let resolvedPS = (CTFontCopyPostScriptName(resolvedFont) as String).lowercased()
        let wasSubstituted: Bool
        if let reqPS = attrInfo.postScriptName?.lowercased(), !reqPS.isEmpty {
            wasSubstituted = !resolvedPS.hasPrefix(reqPS.prefix(5))
        } else {
            wasSubstituted = !attrInfo.hadExplicitFont
        }
        let charCount = rawText.count
        if wasSubstituted, charCount >= 4, let metrics = bitmapMetrics, metrics.tightInkRect.width > 12.0 {
            let unkernedWidth = measureSingleLineWidth(rawText, ctFont: resolvedFont, kern: 0.0)
            if unkernedWidth > 4.0 {
                let targetWidth = max(4.0, metrics.tightInkRect.width - 0.4)
                let delta = targetWidth - unkernedWidth
                let perGap = delta / Double(charCount - 1)
                if abs(perGap) <= 0.40 {
                    letterSpacing = perGap
                }
            }
        }

        let payload = TextPayload(
            text: rawText,
            fontFamily: attrInfo.fontFamily,
            postScriptFontName: attrInfo.postScriptName,
            fontSize: fontSize,
            isBold: effectiveIsBold,
            isItalic: attrInfo.isItalic,
            alignment: .left,
            baselineOffset: baselineOffset,
            letterSpacing: letterSpacing,
            isPDFExtracted: true,
            originalPDFText: rawText,
            originalPDFRect: tightFrame,
            originalFontSize: fontSize,
            originalIsBold: effectiveIsBold,
            originalIsItalic: attrInfo.isItalic,
            originalTextColorHex: textColorHex,
            maskColorHex: maskColorHex
        )

        return VectorElement(
            name: String(rawText.prefix(32)),
            kind: .text(payload),
            frame: tightFrame,
            style: VectorStyle(strokeColorHex: nil, fillColorHex: textColorHex, strokeWidth: 0, opacity: 1.0)
        )
    }

    // MARK: - Font & Color Attribute Extraction from `PDFSelection`

    private struct ExtractedFontAttributes {
        var fontFamily: String
        var postScriptName: String?
        var fontSize: Double
        var isBold: Bool
        var isItalic: Bool
        var colorHex: String?
        var hadExplicitFont: Bool
    }

    private static func extractAttributedFontAndColor(
        from selection: PDFSelection,
        fallbackHeight: Double
    ) -> ExtractedFontAttributes {
        var result = ExtractedFontAttributes(
            fontFamily: "Helvetica Neue",
            postScriptName: nil,
            fontSize: max(7.0, min(42.0, fallbackHeight * 0.74)),
            isBold: false,
            isItalic: false,
            colorHex: nil,
            hadExplicitFont: false
        )

        guard let attrStr = selection.attributedString, attrStr.length > 0 else {
            return result
        }

        let str = attrStr.string as NSString
        var probeIdx = 0
        for i in 0..<str.length {
            let ch = str.character(at: i)
            if ch != 32 && ch != 9 && ch != 10 && ch != 13 {
                probeIdx = i
                break
            }
        }

        let attrs = attrStr.attributes(at: probeIdx, effectiveRange: nil)

        // Extract CTFont (toll-free bridged with NSFont)
        let fontObj = attrs[NSAttributedString.Key("NSFont")] ?? attrs[kCTFontAttributeName as NSAttributedString.Key]
        if let fontObj {
            let cfRef = fontObj as CFTypeRef
            if CFGetTypeID(cfRef) == CTFontGetTypeID() {
                let ctFont = unsafeBitCast(cfRef, to: CTFont.self)
                let rawPS = stripPDFSubsetPrefix(CTFontCopyPostScriptName(ctFont) as String)
                let rawFam = stripPDFSubsetPrefix(CTFontCopyFamilyName(ctFont) as String)
                let ptSize = Double(CTFontGetSize(ctFont))
                let traits = CTFontGetSymbolicTraits(ctFont)

                let lowerPS = rawPS.lowercased()
                let isBold = traits.contains(.boldTrait)
                    || lowerPS.contains("bold")
                    || lowerPS.contains("-bd")
                    || lowerPS.contains("semibold")
                    || lowerPS.contains("demi")
                    || lowerPS.contains("heavy")
                    || lowerPS.contains("black")
                    || lowerPS.contains("medium")
                let isItalic = traits.contains(.italicTrait)
                    || lowerPS.contains("italic")
                    || lowerPS.contains("oblique")
                    || lowerPS.contains("-it")

                result.postScriptName = rawPS.isEmpty ? nil : rawPS
                result.fontFamily = normalizeFontFamilyName(family: rawFam, postScript: rawPS)
                if ptSize >= 4.5 && ptSize <= 96.0 {
                    result.fontSize = ptSize
                    result.hadExplicitFont = true
                }
                result.isBold = isBold
                result.isItalic = isItalic
            }
        }

        // Extract foreground color if available as CGColor (including PDFKit's internal kCPfillColor key)
        let colorObj = attrs[NSAttributedString.Key("kCPfillColor")]
            ?? attrs[NSAttributedString.Key("NSColor")]
            ?? attrs[kCTForegroundColorAttributeName as NSAttributedString.Key]
        if let colorObj {
            let cfRef = colorObj as CFTypeRef
            if CFGetTypeID(cfRef) == CGColor.typeID {
                let cgColor = unsafeBitCast(cfRef, to: CGColor.self)
                if let hex = hexFromCGColor(cgColor) {
                    result.colorHex = hex
                }
            } else if let nsObj = colorObj as? NSObject,
                      nsObj.responds(to: Selector(("CGColor"))),
                      let unmanaged = nsObj.perform(Selector(("CGColor"))) {
                let cgColor = unsafeBitCast(unmanaged.toOpaque(), to: CGColor.self)
                if let hex = hexFromCGColor(cgColor) {
                    result.colorHex = hex
                }
            }
        }

        return result
    }

    private static func stripPDFSubsetPrefix(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 7 else { return trimmed }
        let plusIndex = trimmed.index(trimmed.startIndex, offsetBy: 6)
        if trimmed[plusIndex] == "+" {
            let prefix = trimmed[..<plusIndex]
            if prefix.allSatisfy({ $0 >= "A" && $0 <= "Z" }) {
                return String(trimmed[trimmed.index(after: plusIndex)...])
            }
        }
        return trimmed
    }

    private static func normalizeFontFamilyName(family: String, postScript: String) -> String {
        let candidate = family.isEmpty ? postScript : family
        // If this exact font (or embedded PDF font) is registered in the process, preserve its real family name!
        if PDFEmbeddedFontRegistry.shared.hasRegisteredFont(postScriptName: postScript, familyName: candidate) {
            return candidate.isEmpty ? postScript : candidate
        }
        if !postScript.isEmpty {
            let probe = CTFontCreateWithName(postScript as CFString, 12.0, nil)
            let actualPS = (CTFontCopyPostScriptName(probe) as String).lowercased()
            if actualPS == postScript.lowercased() {
                let fam = CTFontCopyFamilyName(probe) as String
                if !fam.isEmpty { return fam }
            }
        }
        let lower = candidate.lowercased()
        if lower.contains("arial") || lower.contains("liberation sans") || lower.contains("liberationsans") || lower.contains("arimo") {
            return "Arial"
        }
        if lower.contains("verdana") || lower.contains("dejavu sans") || lower.contains("dejavusans") || lower.contains("tahoma") {
            return "Verdana"
        }
        if lower.contains("trebuchet") {
            return "Trebuchet MS"
        }
        if lower.contains("calibri") || lower.contains("carlito") || lower.contains("candara") || lower.contains("segoe") || lower.contains("marianne") || lower.contains("ubuntu") || lower.contains("roboto") || lower.contains("open sans") || lower.contains("opensans") || lower.contains("source sans") || lower.contains("sourcesans") || lower.contains("lato") || lower.contains("noto sans") {
            return "Helvetica Neue"
        }
        if lower.contains("times") || lower.contains("liberation serif") || lower.contains("tinos") || lower.contains("nimbus roman") {
            return "Times New Roman"
        }
        if lower.contains("georgia") || lower.contains("cambria") || lower.contains("merriweather") {
            return "Georgia"
        }
        if lower.contains("courier") || lower.contains("consolas") || lower.contains("menlo") || lower.contains("mono") {
            return "Courier New"
        }
        if lower.contains("avenir") {
            return "Avenir Next"
        }
        if lower.contains("gill") {
            return "Gill Sans"
        }
        if lower.contains("helvetica") {
            return "Helvetica Neue"
        }
        return candidate.isEmpty ? "Helvetica Neue" : candidate
    }

    private static func hexFromCGColor(_ cgColor: CGColor) -> String? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
              let comps = converted.components, comps.count >= 3 else {
            return nil
        }
        return RGBAColor(r: Double(comps[0]), g: Double(comps[1]), b: Double(comps[2])).hexString
    }

    // MARK: - Unified Font Resolver & Metrics (`PDFCodec` + `CanvasViewportView`)

    /// Resolves the exact `CTFont` for a `TextPayload` at a requested point size, preserving PDF PostScript names,
    /// embedded PDF fonts, completed Google Fonts, font families, and bold/italic symbolic traits.
    public static func resolveCTFont(for payload: TextPayload, size: CGFloat) -> CTFont {
        let clampedSize = max(4.0, size)
        var requestedTraits: CTFontSymbolicTraits = []
        if payload.isBold { requestedTraits.insert(.boldTrait) }
        if payload.isItalic { requestedTraits.insert(.italicTrait) }

        // 1. If we have an explicit PostScript name and traits match its original state, try loading it directly
        if let psName = payload.postScriptFontName, !psName.isEmpty,
           payload.isBold == (payload.originalIsBold ?? payload.isBold),
           payload.isItalic == (payload.originalIsItalic ?? payload.isItalic) {
            if let regFont = PDFEmbeddedFontRegistry.shared.makeCTFont(
                postScriptName: psName,
                familyName: payload.fontFamily,
                size: clampedSize,
                isBold: payload.isBold,
                isItalic: payload.isItalic
            ) {
                return regFont
            }
            let direct = CTFontCreateWithName(psName as CFString, clampedSize, nil)
            let actualPS = (CTFontCopyPostScriptName(direct) as String).lowercased()
            let reqLower = psName.lowercased()
            if actualPS == reqLower || actualPS.hasPrefix(reqLower.prefix(5)) {
                return PDFEmbeddedFontRegistry.withMatchingCascadeFallback(
                    direct,
                    size: clampedSize,
                    isBold: payload.isBold,
                    isItalic: payload.isItalic
                )
            }
        }

        // 2. Check embedded/completed registry by family name
        if !payload.fontFamily.isEmpty,
           let regFamFont = PDFEmbeddedFontRegistry.shared.makeCTFont(
               postScriptName: payload.postScriptFontName,
               familyName: payload.fontFamily,
               size: clampedSize,
               isBold: payload.isBold,
               isItalic: payload.isItalic
           ) {
            return regFamFont
        }

        // 3. Create from family name and apply requested bold/italic symbolic traits
        let family = payload.fontFamily.isEmpty ? "Helvetica Neue" : payload.fontFamily
        let baseFont = CTFontCreateWithName(family as CFString, clampedSize, nil)
        if !requestedTraits.isEmpty,
           let traited = CTFontCreateCopyWithSymbolicTraits(baseFont, clampedSize, nil, requestedTraits, [.boldTrait, .italicTrait]) {
            return traited
        }
        let actualFam = (CTFontCopyFamilyName(baseFont) as String).lowercased()
        if actualFam == family.lowercased() {
            return baseFont
        }

        // 4. Explicit PostScript fallback for Helvetica Neue
        let fallbackName: String
        if payload.isBold && payload.isItalic {
            fallbackName = "HelveticaNeue-BoldItalic"
        } else if payload.isBold {
            fallbackName = "HelveticaNeue-Bold"
        } else if payload.isItalic {
            fallbackName = "HelveticaNeue-Italic"
        } else {
            fallbackName = "HelveticaNeue"
        }
        return CTFontCreateWithName(fallbackName as CFString, clampedSize, nil)
    }

    public static func measureTextWidth(for payload: TextPayload) -> Double {
        let ctFont = resolveCTFont(for: payload, size: CGFloat(payload.fontSize))
        let lines = payload.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var maxW = 12.0
        for line in lines {
            let w = measureSingleLineWidth(line, ctFont: ctFont, kern: payload.letterSpacing)
            if w > maxW { maxW = w }
        }
        return maxW
    }

    /// Updates `element.frame.width` (and `height` for multi-line edits) to match the edited text while keeping
    /// `originalPDFRect` untouched so only the original PDF glyphs are masked.
    public static func updateTextFrameForEditedContent(_ element: inout VectorElement) {
        guard case .text(let payload) = element.kind else { return }
        let measuredW = measureTextWidth(for: payload)
        element.frame.width = max(14.0, measuredW + 2.0)
        let lineCount = max(1, payload.text.split(separator: "\n", omittingEmptySubsequences: false).count)
        if lineCount > 1 {
            element.frame.height = max(element.frame.height, Double(lineCount) * payload.fontSize * 1.25)
        }
    }

    private static func measureSingleLineWidth(_ string: String, ctFont: CTFont, kern: Double) -> Double {
        guard !string.isEmpty else { return 0 }
        let kernNumber = kern as CFNumber
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: ctFont,
            kCTKernAttributeName: kernNumber,
        ]
        guard let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, string as CFString, attrs as CFDictionary) else {
            return Double(string.count) * Double(CTFontGetSize(ctFont)) * 0.55
        }
        let ctLine = CTLineCreateWithAttributedString(attrStr)
        return Double(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
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

        // 2. Mask out edited, moved, or deleted PDF text blocks using their sampled background color
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
            if let assetData = sig.assetData {
                drawExternalAsset(
                    data: assetData,
                    ext: sig.assetExtension,
                    removeWhiteBackground: sig.removeWhiteBackground,
                    in: f.cgRect,
                    ctx: ctx
                )
            } else {
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
                    let metaFont = CTFontCreateWithName("HelveticaNeue" as CFString, 8.5, nil)
                    drawCoreTextLine(
                        meta,
                        at: CGPoint(x: f.minX + 2, y: f.maxY - 2),
                        ctFont: metaFont,
                        kern: 0.0,
                        color: ink.cgColor,
                        alignment: .left,
                        boxWidth: f.width - 4,
                        in: ctx
                    )
                }
            }

        case .text(let t):
            let color = (fillColor ?? strokeColor ?? RGBAColor(r: 0.07, g: 0.07, b: 0.09)).cgColor
            let ctFont = resolveCTFont(for: t, size: CGFloat(t.fontSize))
            let lines = t.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let lineH = t.fontSize * 1.25
            let firstBaselineOffset = t.baselineOffset ?? Double(CTFontGetCapHeight(ctFont))
            for (idx, line) in lines.enumerated() {
                let baselineY = f.minY + firstBaselineOffset + Double(idx) * lineH
                drawCoreTextLine(
                    line,
                    at: CGPoint(x: f.minX, y: baselineY),
                    ctFont: ctFont,
                    kern: t.letterSpacing,
                    color: color,
                    alignment: t.alignment,
                    boxWidth: f.width,
                    in: ctx
                )
            }

        case .stamp(let st):
            if let assetData = st.assetData {
                drawExternalAsset(
                    data: assetData,
                    ext: st.assetExtension,
                    removeWhiteBackground: st.removeWhiteBackground,
                    in: f.cgRect,
                    ctx: ctx
                )
            } else {
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

                let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, CGFloat(min(14.0, f.height * 0.30)), nil)
                drawCoreTextLine(
                    st.title,
                    at: CGPoint(x: f.minX, y: f.minY + f.height * 0.52),
                    ctFont: titleFont,
                    kern: 0.0,
                    color: color.cgColor,
                    alignment: .center,
                    boxWidth: f.width,
                    in: ctx
                )
                if !st.subtitle.isEmpty {
                    let subFont = CTFontCreateWithName("HelveticaNeue" as CFString, CGFloat(min(9.0, f.height * 0.18)), nil)
                    drawCoreTextLine(
                        st.subtitle,
                        at: CGPoint(x: f.minX, y: f.minY + f.height * 0.80),
                        ctFont: subFont,
                        kern: 0.0,
                        color: color.cgColor,
                        alignment: .center,
                        boxWidth: f.width,
                        in: ctx
                    )
                }
            }
        }
    }

    private static func drawExternalAsset(
        data: Data,
        ext: String?,
        removeWhiteBackground: Bool,
        in rect: CGRect,
        ctx: CGContext
    ) {
        if !removeWhiteBackground,
           AssetImageCodec.isPDF(data: data, ext: ext),
           let provider = CGDataProvider(data: data as CFData),
           let cgPDF = CGPDFDocument(provider),
           let page = cgPDF.page(at: 1) {
            let box = page.getBoxRect(.cropBox).width > 1 ? page.getBoxRect(.cropBox) : page.getBoxRect(.mediaBox)
            ctx.saveGState()
            // Flip from top-left SimpleVector coordinates to bottom-left PDF coordinates inside rect
            ctx.translateBy(x: rect.minX, y: rect.maxY)
            ctx.scaleBy(x: rect.width / max(1, box.width), y: -rect.height / max(1, box.height))
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(page)
            ctx.restoreGState()
            return
        }
        guard let cgImg = AssetImageCodec.renderCGImage(
            from: data,
            ext: ext,
            targetMaxDimension: 1200,
            removeWhiteBackground: removeWhiteBackground
        ) else { return }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
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

    public enum SyntheticAccentKind: Sendable {
        case acute
        case grave
        case circumflex
        case diaeresis
        case cedilla
    }

    public struct SyntheticAccentPlacement: Sendable {
        public let centerX: Double
        public let capTopY: Double
        public let baselineY: Double
        public let capHeight: Double
        public let kind: SyntheticAccentKind
    }

    /// Adapts a string for rendering with `ctFont` when `ctFont` is an embedded PDF subset font:
    /// - If all characters have native glyphs in `ctFont` (true for system fonts and completed Google Fonts),
    ///   returns `(string, [])` with zero modifications.
    /// - If a character is missing (`glyph == 0`) in a subset font, checks if uppercase folding (for all-caps fonts)
    ///   or base-letter decomposition (`É` -> `E` + acute accent) allows rendering the character body in the exact
    ///   embedded PDF font instead of falling back to Helvetica.
    public static func adaptStringForSubsetFont(
        _ string: String,
        ctFont: CTFont,
        kern: Double = 0.0
    ) -> (adaptedString: String, accents: [SyntheticAccentPlacement]) {
        guard !string.isEmpty else { return (string, []) }
        let utf16 = Array(string.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        if CTFontGetGlyphsForCharacters(ctFont, utf16, &glyphs, utf16.count) {
            return (string, [])
        }

        // Check if this is an all-caps display subset font (has uppercase A/E/I/O/R/S/T but no lowercase a/e/i/o)
        let lowerProbe: [UniChar] = [0x61, 0x65, 0x69, 0x6F]
        var lowerGlyphs = [CGGlyph](repeating: 0, count: lowerProbe.count)
        _ = CTFontGetGlyphsForCharacters(ctFont, lowerProbe, &lowerGlyphs, lowerProbe.count)
        let upperProbe: [UniChar] = [0x41, 0x45, 0x49, 0x4F]
        var upperGlyphs = [CGGlyph](repeating: 0, count: upperProbe.count)
        _ = CTFontGetGlyphsForCharacters(ctFont, upperProbe, &upperGlyphs, upperProbe.count)
        let isAllCapsSubset = lowerGlyphs.allSatisfy({ $0 == 0 }) && upperGlyphs.contains(where: { $0 != 0 })

        let accentTable: [Character: (base: Character, kind: SyntheticAccentKind)] = [
            "É": ("E", .acute), "È": ("E", .grave), "Ê": ("E", .circumflex), "Ë": ("E", .diaeresis),
            "À": ("A", .grave), "Â": ("A", .circumflex), "Ä": ("A", .diaeresis),
            "Ù": ("U", .grave), "Û": ("U", .circumflex), "Ü": ("U", .diaeresis),
            "Î": ("I", .circumflex), "Ï": ("I", .diaeresis),
            "Ô": ("O", .circumflex), "Ö": ("O", .diaeresis),
            "Ç": ("C", .cedilla),
            "é": ("e", .acute), "è": ("e", .grave), "ê": ("e", .circumflex), "ë": ("e", .diaeresis),
            "à": ("a", .grave), "â": ("a", .circumflex), "ä": ("a", .diaeresis),
            "ù": ("u", .grave), "û": ("u", .circumflex), "ü": ("u", .diaeresis),
            "î": ("i", .circumflex), "ï": ("i", .diaeresis),
            "ô": ("o", .circumflex), "ö": ("o", .diaeresis),
            "ç": ("c", .cedilla),
        ]

        func hasGlyph(_ ch: Character) -> Bool {
            let u = Array(String(ch).utf16)
            var g = [CGGlyph](repeating: 0, count: u.count)
            return CTFontGetGlyphsForCharacters(ctFont, u, &g, u.count) && g.allSatisfy { $0 != 0 }
        }

        var outChars: [Character] = []
        var pendingAccents: [(utf16Offset: Int, utf16Len: Int, kind: SyntheticAccentKind, isUpper: Bool)] = []
        var currentUTF16Offset = 0

        for ch in string {
            if hasGlyph(ch) {
                outChars.append(ch)
                currentUTF16Offset += String(ch).utf16.count
                continue
            }
            // Try uppercase if all-caps subset font
            if isAllCapsSubset, let up = ch.uppercased().first, up != ch {
                if hasGlyph(up) {
                    outChars.append(up)
                    currentUTF16Offset += String(up).utf16.count
                    continue
                }
                if let entry = accentTable[up], hasGlyph(entry.base) {
                    let len = String(entry.base).utf16.count
                    pendingAccents.append((currentUTF16Offset, len, entry.kind, true))
                    outChars.append(entry.base)
                    currentUTF16Offset += len
                    continue
                }
            }
            // Try decomposing accented character into base letter + synthetic accent
            if let entry = accentTable[ch] {
                let candidateBase: Character = (isAllCapsSubset ? (entry.base.uppercased().first ?? entry.base) : entry.base)
                if hasGlyph(candidateBase) {
                    let len = String(candidateBase).utf16.count
                    pendingAccents.append((currentUTF16Offset, len, entry.kind, candidateBase.isUppercase))
                    outChars.append(candidateBase)
                    currentUTF16Offset += len
                    continue
                }
            }
            outChars.append(ch)
            currentUTF16Offset += String(ch).utf16.count
        }

        let adapted = String(outChars)
        guard !pendingAccents.isEmpty else { return (adapted, []) }

        let kernNumber = kern as CFNumber
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: ctFont,
            kCTKernAttributeName: kernNumber,
        ]
        guard let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, adapted as CFString, attrs as CFDictionary) else {
            return (adapted, [])
        }
        let ctLine = CTLineCreateWithAttributedString(attrStr)
        let capH = Double(CTFontGetCapHeight(ctFont))
        let xH = Double(CTFontGetXHeight(ctFont))

        var placements: [SyntheticAccentPlacement] = []
        for item in pendingAccents {
            let x0 = Double(CTLineGetOffsetForStringIndex(ctLine, item.utf16Offset, nil))
            let x1 = Double(CTLineGetOffsetForStringIndex(ctLine, item.utf16Offset + item.utf16Len, nil))
            let glyphH = item.isUpper ? capH : (xH > 2.0 ? xH : capH * 0.72)
            placements.append(SyntheticAccentPlacement(
                centerX: (x0 + x1) * 0.5,
                capTopY: -glyphH,
                baselineY: 0.0,
                capHeight: capH,
                kind: item.kind
            ))
        }
        return (adapted, placements)
    }

    private static func drawCoreTextLine(
        _ string: String,
        at origin: CGPoint,
        ctFont: CTFont,
        kern: Double,
        color: CGColor,
        alignment: TextAlignmentMode,
        boxWidth: Double,
        in ctx: CGContext
    ) {
        guard !string.isEmpty else { return }
        let (adaptedString, accents) = adaptStringForSubsetFont(string, ctFont: ctFont, kern: kern)
        let kernNumber = kern as CFNumber
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: ctFont,
            kCTForegroundColorAttributeName: color,
            kCTKernAttributeName: kernNumber,
        ]
        guard let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, adaptedString as CFString, attrs as CFDictionary) else { return }
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
        ctx.translateBy(x: drawX, y: origin.y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        CTLineDraw(ctLine, ctx)
        ctx.restoreGState()

        if !accents.isEmpty {
            ctx.saveGState()
            ctx.setStrokeColor(color)
            ctx.setFillColor(color)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for acc in accents {
                let cx = drawX + CGFloat(acc.centerX)
                let topY = origin.y + CGFloat(acc.capTopY)
                let baseY = origin.y
                let ch = CGFloat(acc.capHeight)
                let strokeW = max(1.1, ch * 0.125)
                ctx.setLineWidth(strokeW)
                switch acc.kind {
                case .acute:
                    ctx.move(to: CGPoint(x: cx - ch * 0.05, y: topY - ch * 0.08))
                    ctx.addLine(to: CGPoint(x: cx + ch * 0.12, y: topY - ch * 0.23))
                    ctx.strokePath()
                case .grave:
                    ctx.move(to: CGPoint(x: cx + ch * 0.05, y: topY - ch * 0.08))
                    ctx.addLine(to: CGPoint(x: cx - ch * 0.12, y: topY - ch * 0.23))
                    ctx.strokePath()
                case .circumflex:
                    ctx.move(to: CGPoint(x: cx - ch * 0.13, y: topY - ch * 0.08))
                    ctx.addLine(to: CGPoint(x: cx, y: topY - ch * 0.22))
                    ctx.addLine(to: CGPoint(x: cx + ch * 0.13, y: topY - ch * 0.08))
                    ctx.strokePath()
                case .diaeresis:
                    let r = strokeW * 0.65
                    ctx.fillEllipse(in: CGRect(x: cx - ch * 0.11 - r, y: topY - ch * 0.16 - r, width: r * 2, height: r * 2))
                    ctx.fillEllipse(in: CGRect(x: cx + ch * 0.11 - r, y: topY - ch * 0.16 - r, width: r * 2, height: r * 2))
                case .cedilla:
                    ctx.move(to: CGPoint(x: cx, y: baseY))
                    ctx.addLine(to: CGPoint(x: cx - ch * 0.03, y: baseY + ch * 0.12))
                    ctx.addLine(to: CGPoint(x: cx + ch * 0.06, y: baseY + ch * 0.20))
                    ctx.strokePath()
                }
            }
            ctx.restoreGState()
        }
    }
}

// MARK: - 2x sRGB Page Bitmap Analyzer (Exact Background Color, Ink Bounds & Baseline)

private final class PDFPageBitmapAnalyzer {
    let scale: Double = 2.0
    let pixelW: Int
    let pixelH: Int
    let bytesPerRow: Int
    let buffer: [UInt8]

    struct RegionMetrics {
        let maskColorHex: String
        let inkColorHex: String?
        let tightInkRect: VectorRect
        let baselineY: Double
        let measuredCapHeight: Double
        let hasReliableCapHeight: Bool
        let appearsBold: Bool
    }

    init?(pdfPage: PDFPage, singlePageData: Data?, pageIndex: Int = 0, pageWidth: Double, pageHeight: Double) {
        let s: Double = 2.0
        let pw = max(16, Int(round(pageWidth * s)))
        let ph = max(16, Int(round(pageHeight * s)))
        let bpr = pw * 4
        var raw = [UInt8](repeating: 255, count: ph * bpr)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let ok = raw.withUnsafeMutableBytes { ptr -> Bool in
            guard let base = ptr.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: pw,
                      height: ph,
                      bitsPerComponent: 8,
                      bytesPerRow: bpr,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }

            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))

            if let cgPage = pdfPage.pageRef {
                let mediaBox = cgPage.getBoxRect(.mediaBox)
                ctx.scaleBy(
                    x: CGFloat(pw) / max(1, mediaBox.width),
                    y: CGFloat(ph) / max(1, mediaBox.height)
                )
                ctx.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
                ctx.drawPDFPage(cgPage)
                return true
            } else if let data = singlePageData,
                      let provider = CGDataProvider(data: data as CFData),
                      let cgPDF = CGPDFDocument(provider),
                      let cgPage = cgPDF.page(at: max(1, pageIndex + 1)) {
                let mediaBox = cgPage.getBoxRect(.mediaBox)
                ctx.scaleBy(
                    x: CGFloat(pw) / max(1, mediaBox.width),
                    y: CGFloat(ph) / max(1, mediaBox.height)
                )
                ctx.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
                ctx.drawPDFPage(cgPage)
                return true
            }
            return false
        }
        guard ok else { return nil }
        self.pixelW = pw
        self.pixelH = ph
        self.bytesPerRow = bpr
        self.buffer = raw
    }

    func analyzeTextRegion(
        selectionRect: VectorRect,
        text: String,
        expectedFontSize: Double = 12.0
    ) -> RegionMetrics {
        let px0 = max(0, min(pixelW - 1, Int(floor(selectionRect.minX * scale))))
        let px1 = max(px0, min(pixelW - 1, Int(ceil(selectionRect.maxX * scale))))
        let py0 = max(0, min(pixelH - 1, Int(floor(selectionRect.minY * scale))))
        let py1 = max(py0, min(pixelH - 1, Int(ceil(selectionRect.maxY * scale))))

        // 1. Sample background color from pixels inside selectionRect (75th percentile by luminance)
        var samples: [(luma: Int, r: Int, g: Int, b: Int)] = []
        let stepX = max(1, (px1 - px0) / 48)
        let stepY = max(1, (py1 - py0) / 16)
        for py in stride(from: py0, through: py1, by: stepY) {
            let rowOffset = py * bytesPerRow
            for px in stride(from: px0, through: px1, by: stepX) {
                let idx = rowOffset + px * 4
                let r = Int(buffer[idx])
                let g = Int(buffer[idx + 1])
                let b = Int(buffer[idx + 2])
                let luma = (299 * r + 587 * g + 114 * b) / 1000
                samples.append((luma, r, g, b))
            }
        }

        samples.sort { $0.luma < $1.luma }
        let bgSample: (luma: Int, r: Int, g: Int, b: Int)
        if samples.isEmpty {
            bgSample = (255, 255, 255, 255)
        } else {
            let highIdx = min(samples.count - 1, (samples.count * 78) / 100)
            let lowIdx = min(samples.count - 1, (samples.count * 22) / 100)
            let medianIdx = samples.count / 2
            // If majority of box is dark (< 110), background is dark; otherwise background is the upper quartile
            bgSample = samples[medianIdx].luma < 110 ? samples[lowIdx] : samples[highIdx]
        }

        let maskColorHex = String(format: "#%02X%02X%02X", bgSample.r, bgSample.g, bgSample.b)

        // 2. Vertical ink band segmentation inside selectionRect:
        //    Some PDFs (e.g., Canva/Illustrator subset fonts) declare an inflated FontBBox whose selectionRect
        //    overlaps the line above or below. Segmenting the horizontal row-ink profile into contiguous vertical
        //    bands across blank inter-line gaps isolates strictly the target text line's glyphs.
        let rowCount = max(1, py1 - py0 + 1)
        var rowInkCount = [Int](repeating: 0, count: rowCount)
        var peakRowInk = 0
        for py in py0...py1 {
            let rowOffset = py * bytesPerRow
            var count = 0
            for px in px0...px1 {
                let idx = rowOffset + px * 4
                let r = Int(buffer[idx])
                let g = Int(buffer[idx + 1])
                let b = Int(buffer[idx + 2])
                let dist = max(abs(r - bgSample.r), max(abs(g - bgSample.g), abs(b - bgSample.b)))
                if dist >= 22 {
                    count += 1
                }
            }
            rowInkCount[py - py0] = count
            if count > peakRowInk { peakRowInk = count }
        }

        struct VerticalBand {
            var startPY: Int
            var endPY: Int
            var inkSum: Int
            var height: Int { endPY - startPY + 1 }
        }

        var rawBands: [VerticalBand] = []
        var currentBand: VerticalBand? = nil
        for py in py0...py1 {
            let c = rowInkCount[py - py0]
            if c > 0 {
                if var b = currentBand {
                    b.endPY = py
                    b.inkSum += c
                    currentBand = b
                } else {
                    currentBand = VerticalBand(startPY: py, endPY: py, inkSum: c)
                }
            } else if let b = currentBand {
                rawBands.append(b)
                currentBand = nil
            }
        }
        if let b = currentBand {
            rawBands.append(b)
        }

        guard !rawBands.isEmpty else {
            return RegionMetrics(
                maskColorHex: maskColorHex,
                inkColorHex: nil,
                tightInkRect: selectionRect,
                baselineY: selectionRect.minY + selectionRect.height * 0.80,
                measuredCapHeight: selectionRect.height * 0.65,
                hasReliableCapHeight: false,
                appearsBold: false
            )
        }

        // Merge small intra-line gaps (accents É/È/À/Î or dots on i/j above body, or cedilla below body)
        var mergedBands: [VerticalBand] = [rawBands[0]]
        for next in rawBands.dropFirst() {
            let prev = mergedBands[mergedBands.count - 1]
            let gap = next.startPY - prev.endPY - 1
            let isUpperAccent = (gap <= 5 && prev.height <= 6)
            let isLowerCedilla = (gap <= 3 && next.height <= 4)
            if gap <= 2 || isUpperAccent || isLowerCedilla {
                mergedBands[mergedBands.count - 1] = VerticalBand(
                    startPY: prev.startPY,
                    endPY: next.endPY,
                    inkSum: prev.inkSum + next.inkSum
                )
            } else {
                mergedBands.append(next)
            }
        }

        let hasInteriorBand = mergedBands.contains { $0.startPY > py0 + 1 && $0.endPY < py1 - 1 && $0.height >= 4 }
        let selMid = Double(py0 + py1) * 0.5
        let selHalfH = max(1.0, Double(py1 - py0) * 0.5)
        var chosenBand = mergedBands.max { a, b in
            func bandScore(_ band: VerticalBand) -> Double {
                let mid = Double(band.startPY + band.endPY) * 0.5
                let distNorm = abs(mid - selMid) / selHalfH
                let touchesEdge = (band.startPY <= py0 + 1) || (band.endPY >= py1 - 1)
                let edgePenalty = (hasInteriorBand && touchesEdge) ? 0.15 : 1.0
                return Double(band.inkSum) * edgePenalty / (1.0 + distNorm * 1.5)
            }
            return bandScore(a) < bandScore(b)
        } ?? mergedBands[0]

        // Valley split if a single descender pixel bridged across a narrow inter-line gap
        let maxExpectedBandPx = max(24, Int(ceil(expectedFontSize * scale * 1.32)))
        if chosenBand.height > maxExpectedBandPx && chosenBand.height >= 12 {
            let valleyThreshold = max(2, peakRowInk / 14)
            let searchMin = chosenBand.startPY + 4
            let searchMax = chosenBand.endPY - 4
            if searchMin < searchMax {
                var bestValleyPY: Int? = nil
                var minValleyInk = Int.max
                for py in searchMin...searchMax {
                    let c = rowInkCount[py - py0]
                    if c <= valleyThreshold && c < minValleyInk {
                        minValleyInk = c
                        bestValleyPY = py
                    }
                }
                if let vPY = bestValleyPY {
                    let topSub = VerticalBand(startPY: chosenBand.startPY, endPY: vPY - 1, inkSum: 1)
                    let botSub = VerticalBand(startPY: vPY + 1, endPY: chosenBand.endPY, inkSum: 1)
                    let topMid = Double(topSub.startPY + topSub.endPY) * 0.5
                    let botMid = Double(botSub.startPY + botSub.endPY) * 0.5
                    chosenBand = abs(topMid - selMid) <= abs(botMid - selMid) ? topSub : botSub
                }
            }
        }

        let scanY0 = chosenBand.startPY
        let scanY1 = chosenBand.endPY

        var minInkX = Int.max
        var maxInkX = Int.min
        var minInkY = Int.max
        var maxInkY = Int.min

        let colCount = max(1, px1 - px0 + 1)
        var colMinY = [Int](repeating: Int.max, count: colCount)
        var colMaxY = [Int](repeating: Int.min, count: colCount)
        var coreColMinY = [Int](repeating: Int.max, count: colCount)
        var coreColMaxY = [Int](repeating: Int.min, count: colCount)
        var inkSamples: [(dist: Int, r: Int, g: Int, b: Int)] = []
        var runLengths: [Int] = []

        for py in scanY0...scanY1 {
            let rowOffset = py * bytesPerRow
            var curRun = 0
            for px in px0...px1 {
                let idx = rowOffset + px * 4
                let r = Int(buffer[idx])
                let g = Int(buffer[idx + 1])
                let b = Int(buffer[idx + 2])
                let dist = max(abs(r - bgSample.r), max(abs(g - bgSample.g), abs(b - bgSample.b)))
                if dist >= 22 {
                    if px < minInkX { minInkX = px }
                    if px > maxInkX { maxInkX = px }
                    if py < minInkY { minInkY = py }
                    if py > maxInkY { maxInkY = py }
                    let cIdx = px - px0
                    if py < colMinY[cIdx] { colMinY[cIdx] = py }
                    if py > colMaxY[cIdx] { colMaxY[cIdx] = py }
                    if dist >= 48 {
                        if py < coreColMinY[cIdx] { coreColMinY[cIdx] = py }
                        if py > coreColMaxY[cIdx] { coreColMaxY[cIdx] = py }
                    }
                    if dist >= 45 {
                        curRun += 1
                    } else if curRun > 0 {
                        runLengths.append(curRun)
                        curRun = 0
                    }
                    if dist >= 55 {
                        inkSamples.append((dist, r, g, b))
                    }
                } else if curRun > 0 {
                    runLengths.append(curRun)
                    curRun = 0
                }
            }
            if curRun > 0 {
                runLengths.append(curRun)
            }
        }

        guard minInkX <= maxInkX, minInkY <= maxInkY else {
            return RegionMetrics(
                maskColorHex: maskColorHex,
                inkColorHex: nil,
                tightInkRect: selectionRect,
                baselineY: selectionRect.minY + selectionRect.height * 0.80,
                measuredCapHeight: selectionRect.height * 0.65,
                hasReliableCapHeight: false,
                appearsBold: false
            )
        }

        // 3. Determine dominant ink color from the highest-contrast core glyph pixels
        var inkColorHex: String? = nil
        if !inkSamples.isEmpty {
            inkSamples.sort { $0.dist > $1.dist }
            let coreCount = max(1, min(inkSamples.count, inkSamples.count / 4))
            var sumR = 0, sumG = 0, sumB = 0
            for i in 0..<coreCount {
                sumR += inkSamples[i].r
                sumG += inkSamples[i].g
                sumB += inkSamples[i].b
            }
            let avgR = sumR / coreCount
            let avgG = sumG / coreCount
            let avgB = sumB / coreCount
            if avgR < 38 && avgG < 38 && avgB < 38 {
                inkColorHex = "#111317"
            } else {
                inkColorHex = String(format: "#%02X%02X%02X", avgR, avgG, avgB)
            }
        }

        // 4. Determine exact baselineY and capTopY from substantial glyph columns (preferring core glyph ink >= 48)
        let totalInkH = max(1, maxInkY - minInkY + 1)
        let minColH = max(2, Int(Double(totalInkH) * 0.36))
        var bottoms: [Int] = []
        var tops: [Int] = []
        bottoms.reserveCapacity(colCount)
        tops.reserveCapacity(colCount)

        for i in 0..<colCount where coreColMinY[i] <= coreColMaxY[i] {
            let h = coreColMaxY[i] - coreColMinY[i] + 1
            if h >= minColH {
                bottoms.append(coreColMaxY[i])
                tops.append(coreColMinY[i])
            }
        }
        if bottoms.count < 3 {
            bottoms.removeAll()
            tops.removeAll()
            for i in 0..<colCount where colMinY[i] <= colMaxY[i] {
                let h = colMaxY[i] - colMinY[i] + 1
                if h >= minColH {
                    bottoms.append(colMaxY[i])
                    tops.append(colMinY[i])
                }
            }
        }

        let descenderChars = CharacterSet(charactersIn: "gjpqyçQJy()[]{};,")
        let hasDescenders = text.unicodeScalars.contains { descenderChars.contains($0) }
        let capOrDigitChars = CharacterSet.uppercaseLetters.union(.decimalDigits)
        let hasCapsOrDigits = text.unicodeScalars.contains { capOrDigitChars.contains($0) }

        let baselinePY: Double
        if bottoms.isEmpty {
            baselinePY = Double(maxInkY)
        } else {
            bottoms.sort()
            if hasDescenders {
                // 55th percentile of column bottoms sits directly on the baseline while ignoring descender stems
                let idx = min(bottoms.count - 1, (bottoms.count * 55) / 100)
                baselinePY = Double(bottoms[idx])
            } else {
                // Without descenders, the 85th percentile of column bottoms is the exact baseline
                let idx = min(bottoms.count - 1, (bottoms.count * 85) / 100)
                baselinePY = Double(bottoms[idx])
            }
        }

        let capTopPY: Double
        if tops.isEmpty {
            capTopPY = Double(minInkY)
        } else {
            tops.sort()
            let idx = min(tops.count - 1, (tops.count * 12) / 100)
            capTopPY = Double(tops[idx])
        }

        runLengths.sort()
        let medianRun = runLengths.isEmpty ? 0 : runLengths[runLengths.count / 2]
        let appearsBold = totalInkH >= 14 && (Double(medianRun) / Double(totalInkH)) >= 0.25

        let tightInkRect = VectorRect(
            x: Double(minInkX) / scale,
            y: Double(minInkY) / scale,
            width: max(6.0, Double(maxInkX - minInkX + 1) / scale),
            height: max(6.0, Double(maxInkY - minInkY + 1) / scale)
        )
        let baselineY = (baselinePY + 0.5) / scale
        let measuredCapHeight = max(4.0, (baselinePY - capTopPY + 0.5) / scale)

        return RegionMetrics(
            maskColorHex: maskColorHex,
            inkColorHex: inkColorHex,
            tightInkRect: tightInkRect,
            baselineY: baselineY,
            measuredCapHeight: measuredCapHeight,
            hasReliableCapHeight: hasCapsOrDigits && bottoms.count >= 4,
            appearsBold: appearsBold
        )
    }
}

// MARK: - Embedded PDF Font Extractor, CMap Patcher & Open-Font Auto-Completer

/// Extracts embedded font streams (`/FontFile`, `/FontFile2`, `/FontFile3`) and `/ToUnicode` maps directly from
/// `CGPDFDocument`, upgrades subset open fonts (e.g. `Poppins`, `DM Serif Display`, `Montserrat`, `Roboto`, `Lato`, `Inter`)
/// to complete `.ttf` fonts cached in `~/Library/Application Support/SimpleVector/Fonts/`, and strips `ABCDEF+` subset
/// prefixes in-place so `PDFSelection`, `CanvasViewportView`, and `PDFCodec.exportPDF` render using the exact PDF font.
public final class PDFEmbeddedFontRegistry: @unchecked Sendable {
    public static let shared = PDFEmbeddedFontRegistry()

    private let lock = NSLock()
    private var cgFontsByKey: [String: CGFont] = [:]
    private var completeFontsRegistered: Set<String> = []
    private var attemptedRemoteFamilies: Set<String> = []
    private var registeredFamilies: Set<String> = []

    private let persistentCacheDir: URL
    private let subsetTempDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.persistentCacheDir = appSupport
            .appendingPathComponent("SimpleVector", isDirectory: true)
            .appendingPathComponent("Fonts", isDirectory: true)
        self.subsetTempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SimpleVectorEmbeddedFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: persistentCacheDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: subsetTempDir, withIntermediateDirectories: true)
    }

    public var registeredFamilyNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(registeredFamilies).sorted()
    }

    public func hasRegisteredFont(postScriptName: String?, familyName: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let ps = postScriptName?.lowercased(), !ps.isEmpty, cgFontsByKey[ps] != nil {
            return true
        }
        if let fam = familyName?.lowercased(), !fam.isEmpty, cgFontsByKey[fam] != nil {
            return true
        }
        return false
    }

    public func makeCTFont(
        postScriptName: String?,
        familyName: String?,
        size: CGFloat,
        isBold: Bool,
        isItalic: Bool
    ) -> CTFont? {
        lock.lock()
        let cgFont: CGFont? = {
            if let ps = postScriptName?.lowercased(), !ps.isEmpty, let f = cgFontsByKey[ps] {
                return f
            }
            if let fam = familyName?.lowercased(), !fam.isEmpty, let f = cgFontsByKey[fam] {
                return f
            }
            return nil
        }()
        lock.unlock()

        if let cgFont {
            let ct = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
            return Self.withMatchingCascadeFallback(ct, size: size, isBold: isBold, isItalic: isItalic)
        }
        return nil
    }

    /// Attaches a weight- and style-matched fallback cascade descriptor (`Avenir Next` for geometric sans, `Georgia` for serif)
    /// so that if an offline commercial subset font is missing a newly typed base character, CoreText falls back to a
    /// visually matching font instead of thin `Helvetica`.
    public static func withMatchingCascadeFallback(
        _ ctFont: CTFont,
        size: CGFloat,
        isBold: Bool,
        isItalic: Bool
    ) -> CTFont {
        let psLower = (CTFontCopyPostScriptName(ctFont) as String).lowercased()
        let isSerif = psLower.contains("serif") || psLower.contains("roman") || psLower.contains("garamond") || psLower.contains("baskerville")
        let fallbackPS: String
        if isSerif {
            if isBold && isItalic { fallbackPS = "Georgia-BoldItalic" }
            else if isBold { fallbackPS = "Georgia-Bold" }
            else if isItalic { fallbackPS = "Georgia-Italic" }
            else { fallbackPS = "Georgia" }
        } else if psLower.contains("semibold") || psLower.contains("demi") {
            fallbackPS = isItalic ? "AvenirNext-DemiBoldItalic" : "AvenirNext-DemiBold"
        } else if psLower.contains("medium") {
            fallbackPS = isItalic ? "AvenirNext-MediumItalic" : "AvenirNext-Medium"
        } else if isBold {
            fallbackPS = isItalic ? "AvenirNext-BoldItalic" : "AvenirNext-Bold"
        } else {
            fallbackPS = isItalic ? "AvenirNext-Italic" : "AvenirNext-Regular"
        }
        let fallbackDesc = CTFontDescriptorCreateWithNameAndSize(fallbackPS as CFString, size)
        let attrs: [CFString: Any] = [
            kCTFontCascadeListAttribute: [fallbackDesc] as CFArray
        ]
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        return CTFontCreateCopyWithAttributes(ctFont, size, nil, desc)
    }

    // MARK: - Scan & Register All Fonts from PDF Data

    private struct ExtractedPDFFontEntry {
        var cleanPSName: String
        var subtype: String
        var fontStreamData: Data?
        var fontStreamExt: String
        var toUnicodeStrings: [String]
    }

    public func registerFonts(fromPDFData data: Data) {
        guard let provider = CGDataProvider(data: data as CFData),
              let cgDoc = CGPDFDocument(provider),
              cgDoc.numberOfPages > 0 else {
            return
        }

        var entriesByPS: [String: ExtractedPDFFontEntry] = [:]
        for pageIdx in 1...cgDoc.numberOfPages {
            guard let page = cgDoc.page(at: pageIdx),
                  let pageDict = page.dictionary else { continue }
            var resDict: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(pageDict, "Resources", &resDict), let resDict {
                collectFontsFromResources(resDict, into: &entriesByPS, depth: 0)
            }
        }

        guard !entriesByPS.isEmpty else { return }

        // Group font families that are not yet installed on macOS so we can resolve complete open fonts in a single batch
        var familiesToFetch: Set<String> = []
        for (cleanPS, _) in entriesByPS {
            if isCompleteSystemOrRegisteredFont(postScriptName: cleanPS) {
                continue
            }
            if loadFromLocalDiskCache(cleanPSName: cleanPS) {
                continue
            }
            let parsed = Self.parsePostScriptFontName(cleanPS)
            familiesToFetch.insert(parsed.family)
        }

        if !familiesToFetch.isEmpty {
            fetchAndCacheGoogleFonts(families: Array(familiesToFetch))
        }

        // Finally, for any font still not registered as a complete font (e.g. LEMONMILK-Bold, Calibri, or when offline),
        // patch and register its embedded PDF FontFile2 / FontFile3 / FontFile stream directly!
        for (cleanPS, entry) in entriesByPS {
            if isCompleteSystemOrRegisteredFont(postScriptName: cleanPS) {
                continue
            }
            guard let rawFontData = entry.fontStreamData, rawFontData.count > 32 else { continue }
            var patchedData = Self.stripSubsetPrefixFromTTF(rawFontData)
            var mergedToUnicode: [UInt16: UInt16] = [:]
            for s in entry.toUnicodeStrings {
                let map = Self.parseToUnicode(s)
                for (k, v) in map { mergedToUnicode[k] = v }
            }
            if !mergedToUnicode.isEmpty {
                patchedData = Self.patchTrueTypeCmapIfNeeded(
                    patchedData,
                    toUnicodeMap: mergedToUnicode,
                    isCIDFont: entry.subtype == "Type0"
                )
            }
            registerFontBinary(patchedData, cleanPSName: cleanPS, ext: entry.fontStreamExt, isComplete: false)
        }
    }

    private func collectFontsFromResources(
        _ resDict: CGPDFDictionaryRef,
        into entriesByPS: inout [String: ExtractedPDFFontEntry],
        depth: Int
    ) {
        guard depth <= 4 else { return }
        var fontDict: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resDict, "Font", &fontDict), let fontDict {
            withUnsafeMutablePointer(to: &entriesByPS) { ptr in
                CGPDFDictionaryApplyBlock(fontDict, { _, obj, ctx in
                    guard let entriesPtr = ctx?.assumingMemoryBound(to: [String: ExtractedPDFFontEntry].self) else {
                        return true
                    }
                    var d: CGPDFDictionaryRef?
                    guard CGPDFObjectGetValue(obj, .dictionary, &d), let d else { return true }
                    PDFEmbeddedFontRegistry.extractFontEntry(from: d, into: &entriesPtr.pointee)
                    return true
                }, ptr)
            }
        }

        // Also inspect Form XObjects that may carry their own /Resources -> /Font
        var xobjDict: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resDict, "XObject", &xobjDict), let xobjDict {
            var nestedResources: [CGPDFDictionaryRef] = []
            withUnsafeMutablePointer(to: &nestedResources) { ptr in
                CGPDFDictionaryApplyBlock(xobjDict, { _, obj, ctx in
                    guard let arrPtr = ctx?.assumingMemoryBound(to: [CGPDFDictionaryRef].self) else { return true }
                    var streamRef: CGPDFStreamRef?
                    guard CGPDFObjectGetValue(obj, .stream, &streamRef), let streamRef,
                          let sDict = CGPDFStreamGetDictionary(streamRef) else { return true }
                    var subPtr: UnsafePointer<CChar>?
                    if CGPDFDictionaryGetName(sDict, "Subtype", &subPtr), let subPtr,
                       String(cString: subPtr) == "Form" {
                        var subRes: CGPDFDictionaryRef?
                        if CGPDFDictionaryGetDictionary(sDict, "Resources", &subRes), let subRes {
                            arrPtr.pointee.append(subRes)
                        }
                    }
                    return true
                }, ptr)
            }
            for subRes in nestedResources {
                collectFontsFromResources(subRes, into: &entriesByPS, depth: depth + 1)
            }
        }
    }

    private static func extractFontEntry(
        from d: CGPDFDictionaryRef,
        into entriesByPS: inout [String: ExtractedPDFFontEntry]
    ) {
        var bfPtr: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(d, "BaseFont", &bfPtr), let bfPtr else { return }
        let rawBaseFont = String(cString: bfPtr)
        let cleanPS = stripSubsetPrefix(rawBaseFont)
        guard !cleanPS.isEmpty else { return }

        var subPtr: UnsafePointer<CChar>?
        let subtype = (CGPDFDictionaryGetName(d, "Subtype", &subPtr) && subPtr != nil) ? String(cString: subPtr!) : ""

        var fmt: CGPDFDataFormat = .raw
        var toUniStr: String? = nil
        var toUniStream: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(d, "ToUnicode", &toUniStream), let toUniStream,
           let cfData = CGPDFStreamCopyData(toUniStream, &fmt) {
            toUniStr = String(data: cfData as Data, encoding: .utf8) ?? String(data: cfData as Data, encoding: .isoLatin1)
        }

        var fd: CGPDFDictionaryRef?
        if !CGPDFDictionaryGetDictionary(d, "FontDescriptor", &fd) {
            var descArr: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(d, "DescendantFonts", &descArr), let descArr {
                var cidDict: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(descArr, 0, &cidDict), let cidDict {
                    CGPDFDictionaryGetDictionary(cidDict, "FontDescriptor", &fd)
                }
            }
        }

        var fontData: Data? = nil
        var ext = "ttf"
        if let fd {
            var sRef: CGPDFStreamRef?
            if CGPDFDictionaryGetStream(fd, "FontFile2", &sRef), let sRef,
               let cfData = CGPDFStreamCopyData(sRef, &fmt) {
                fontData = cfData as Data
                ext = "ttf"
            } else if CGPDFDictionaryGetStream(fd, "FontFile3", &sRef), let sRef,
                      let cfData = CGPDFStreamCopyData(sRef, &fmt) {
                fontData = cfData as Data
                ext = "otf"
            } else if CGPDFDictionaryGetStream(fd, "FontFile", &sRef), let sRef,
                      let cfData = CGPDFStreamCopyData(sRef, &fmt) {
                fontData = cfData as Data
                ext = "pfb"
            }
        }

        var entry = entriesByPS[cleanPS] ?? ExtractedPDFFontEntry(
            cleanPSName: cleanPS,
            subtype: subtype,
            fontStreamData: nil,
            fontStreamExt: ext,
            toUnicodeStrings: []
        )
        if let fontData, fontData.count > (entry.fontStreamData?.count ?? 0) {
            entry.fontStreamData = fontData
            entry.fontStreamExt = ext
        }
        if let toUniStr, !toUniStr.isEmpty {
            entry.toUnicodeStrings.append(toUniStr)
        }
        entriesByPS[cleanPS] = entry
    }

    private static func stripSubsetPrefix(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 7 else { return trimmed }
        let plusIndex = trimmed.index(trimmed.startIndex, offsetBy: 6)
        if trimmed[plusIndex] == "+" {
            let prefix = trimmed[..<plusIndex]
            if prefix.allSatisfy({ $0 >= "A" && $0 <= "Z" }) {
                return String(trimmed[trimmed.index(after: plusIndex)...])
            }
        }
        return trimmed
    }

    private func isCompleteSystemOrRegisteredFont(postScriptName: String) -> Bool {
        let key = postScriptName.lowercased()
        lock.lock()
        let alreadyComplete = completeFontsRegistered.contains(key)
        lock.unlock()
        if alreadyComplete { return true }

        let ct = CTFontCreateWithName(postScriptName as CFString, 12.0, nil)
        let actualPS = (CTFontCopyPostScriptName(ct) as String).lowercased()
        guard actualPS == key else { return false }

        let probeChars: [UniChar] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789éèêàùç".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: probeChars.count)
        _ = CTFontGetGlyphsForCharacters(ct, probeChars, &glyphs, probeChars.count)
        let nonZero = glyphs.filter { $0 != 0 }.count
        if nonZero >= 60 {
            let fam = CTFontCopyFamilyName(ct) as String
            lock.lock()
            completeFontsRegistered.insert(key)
            if !fam.isEmpty { registeredFamilies.insert(fam) }
            lock.unlock()
            return true
        }
        return false
    }

    private func loadFromLocalDiskCache(cleanPSName: String) -> Bool {
        let safe = cleanPSName.replacingOccurrences(of: "/", with: "_")
        let cachedURL = persistentCacheDir.appendingPathComponent("\(safe).ttf")
        if let data = try? Data(contentsOf: cachedURL), data.count > 64 {
            return registerFontBinary(data, cleanPSName: cleanPSName, ext: "ttf", isComplete: true, existingURL: cachedURL)
        }
        // Also check Microsoft Office bundle fonts on macOS if present (e.g. Calibri, Cambria, Candara, Consolas)
        let officeDirs = [
            "/Applications/Microsoft Word.app/Contents/Resources/DFonts",
            "/Library/Fonts/Microsoft"
        ]
        for dir in officeDirs {
            let dirURL = URL(fileURLWithPath: dir)
            guard let items = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else {
                continue
            }
            for item in items where item.pathExtension.lowercased() == "ttf" || item.pathExtension.lowercased() == "ttc" {
                let stem = item.deletingPathExtension().lastPathComponent.lowercased()
                if stem == cleanPSName.lowercased().replacingOccurrences(of: "-", with: "") ||
                   stem == cleanPSName.lowercased().split(separator: "-").first.map(String.init) {
                    var err: Unmanaged<CFError>?
                    CTFontManagerRegisterFontsForURL(item as CFURL, .process, &err)
                    if isCompleteSystemOrRegisteredFont(postScriptName: cleanPSName) {
                        return true
                    }
                }
            }
        }
        return false
    }

    @discardableResult
    private func registerFontBinary(
        _ data: Data,
        cleanPSName: String,
        ext: String,
        isComplete: Bool,
        existingURL: URL? = nil
    ) -> Bool {
        guard let provider = CGDataProvider(data: data as CFData),
              let cgFont = CGFont(provider) else {
            return false
        }

        let targetURL: URL
        if let existingURL {
            targetURL = existingURL
        } else {
            let safe = cleanPSName.replacingOccurrences(of: "/", with: "_")
            let dir = isComplete ? persistentCacheDir : subsetTempDir
            targetURL = dir.appendingPathComponent("\(safe).\(ext)")
            try? data.write(to: targetURL, options: .atomic)
        }

        var err: Unmanaged<CFError>?
        let registeredViaURL = CTFontManagerRegisterFontsForURL(targetURL as CFURL, .process, &err)
        if !registeredViaURL {
            if let descArr = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor] {
                CTFontManagerRegisterFontDescriptors(descArr as CFArray, .process, true, nil)
            }
        }

        let ct = CTFontCreateWithGraphicsFont(cgFont, 12.0, nil, nil)
        let ps = (CTFontCopyPostScriptName(ct) as String)
        let fam = (CTFontCopyFamilyName(ct) as String)

        lock.lock()
        cgFontsByKey[cleanPSName.lowercased()] = cgFont
        if !ps.isEmpty {
            cgFontsByKey[ps.lowercased()] = cgFont
        }
        if !fam.isEmpty {
            if cgFontsByKey[fam.lowercased()] == nil || isComplete {
                cgFontsByKey[fam.lowercased()] = cgFont
            }
            registeredFamilies.insert(fam)
        }
        if isComplete {
            completeFontsRegistered.insert(cleanPSName.lowercased())
            if !ps.isEmpty { completeFontsRegistered.insert(ps.lowercased()) }
        }
        lock.unlock()
        return true
    }

    // MARK: - Google Fonts Open-Font Auto-Completion

    private static func parsePostScriptFontName(_ psName: String) -> (family: String, weight: Int, italic: Bool) {
        let clean = stripSubsetPrefix(psName)
        let parts = clean.split(separator: "-", maxSplits: 1).map(String.init)
        let rawFam = parts[0]
        let style = parts.count > 1 ? parts[1].lowercased() : "regular"

        var spaced = ""
        let chars = Array(rawFam)
        for i in 0..<chars.count {
            let c = chars[i]
            if i > 0 && c.isUppercase {
                let prev = chars[i - 1]
                let nextIsLower = (i + 1 < chars.count) && chars[i + 1].isLowercase
                if prev.isLowercase || (prev.isUppercase && nextIsLower) {
                    spaced.append(" ")
                }
            }
            spaced.append(c)
        }

        var weight = 400
        if style.contains("thin") || style.contains("hairline") { weight = 100 }
        else if style.contains("extralight") || style.contains("ultralight") { weight = 200 }
        else if style.contains("light") { weight = 300 }
        else if style.contains("medium") { weight = 500 }
        else if style.contains("semibold") || style.contains("demibold") { weight = 600 }
        else if style.contains("extrabold") || style.contains("ultrabold") { weight = 800 }
        else if style.contains("black") || style.contains("heavy") { weight = 900 }
        else if style.contains("bold") { weight = 700 }
        let italic = style.contains("italic") || style.contains("oblique")
        return (spaced, weight, italic)
    }

    private func fetchAndCacheGoogleFonts(families: [String]) {
        var toQuery: [String] = []
        lock.lock()
        for fam in families {
            let key = fam.lowercased()
            if !attemptedRemoteFamilies.contains(key) {
                attemptedRemoteFamilies.insert(key)
                toQuery.append(fam)
            }
        }
        lock.unlock()

        guard !toQuery.isEmpty else { return }

        let familySpecs = toQuery.map { fam -> String in
            let plusFam = fam.replacingOccurrences(of: " ", with: "+")
            return "\(plusFam):300,400,500,600,700,800,400i,700i"
        }.joined(separator: "|")

        guard let encoded = familySpecs.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let cssURL = URL(string: "https://fonts.googleapis.com/css?family=\(encoded)") else {
            return
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 3.5
        let session = URLSession(configuration: config)

        var req = URLRequest(url: cssURL)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        var cssData: Data? = nil
        session.dataTask(with: req) { data, resp, _ in
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                cssData = data
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 2.2)

        guard let cssData, let css = String(data: cssData, encoding: .utf8), !css.isEmpty,
              let urlRegex = try? NSRegularExpression(pattern: "url\\((https://[^)]+\\.ttf)\\)") else {
            return
        }

        let matches = urlRegex.matches(in: css, range: NSRange(css.startIndex..., in: css))
        let group = DispatchGroup()
        var downloadedTTFs: [Data] = []
        let dlLock = NSLock()

        for m in matches {
            guard let r = Range(m.range(at: 1), in: css),
                  let ttfURL = URL(string: String(css[r])) else { continue }
            group.enter()
            session.dataTask(with: ttfURL) { data, resp, _ in
                defer { group.leave() }
                if let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let data, data.count > 100 {
                    dlLock.lock()
                    downloadedTTFs.append(data)
                    dlLock.unlock()
                }
            }.resume()
        }
        _ = group.wait(timeout: .now() + 3.0)

        for ttfData in downloadedTTFs {
            guard let provider = CGDataProvider(data: ttfData as CFData),
                  let cgFont = CGFont(provider),
                  let psName = cgFont.postScriptName as String?, !psName.isEmpty else {
                continue
            }
            registerFontBinary(ttfData, cleanPSName: psName, ext: "ttf", isComplete: true)
        }
    }

    // MARK: - In-Place TrueType `name` Subset Prefix Stripper & `/ToUnicode` `cmap` Patcher

    /// Strips 6-letter `ABCDEF+` subset prefixes inside a TrueType `name` table in-place by advancing string offsets.
    private static func stripSubsetPrefixFromTTF(_ data: Data) -> Data {
        guard data.count > 12 else { return data }
        let numTables = (Int(data[4]) << 8) | Int(data[5])
        guard numTables > 0, numTables < 64, data.count >= 12 + numTables * 16 else { return data }
        var out = data
        for i in 0..<numTables {
            let entryOffset = 12 + i * 16
            let tag = String(bytes: data[entryOffset..<(entryOffset + 4)], encoding: .ascii) ?? ""
            if tag == "name" {
                let tableOffset = (Int(data[entryOffset + 8]) << 24)
                    | (Int(data[entryOffset + 9]) << 16)
                    | (Int(data[entryOffset + 10]) << 8)
                    | Int(data[entryOffset + 11])
                let tableLen = (Int(data[entryOffset + 12]) << 24)
                    | (Int(data[entryOffset + 13]) << 16)
                    | (Int(data[entryOffset + 14]) << 8)
                    | Int(data[entryOffset + 15])
                guard tableOffset > 0, tableLen >= 6, tableOffset + tableLen <= data.count else { break }
                let count = (Int(data[tableOffset + 2]) << 8) | Int(data[tableOffset + 3])
                let stringStorageOffset = tableOffset + ((Int(data[tableOffset + 4]) << 8) | Int(data[tableOffset + 5]))
                for r in 0..<count {
                    let recOffset = tableOffset + 6 + r * 12
                    guard recOffset + 12 <= tableOffset + tableLen else { break }
                    let platformID = (Int(data[recOffset]) << 8) | Int(data[recOffset + 1])
                    let strLen = (Int(data[recOffset + 8]) << 8) | Int(data[recOffset + 9])
                    let strOff = (Int(data[recOffset + 10]) << 8) | Int(data[recOffset + 11])
                    let absStrOff = stringStorageOffset + strOff
                    guard absStrOff >= 0, absStrOff + strLen <= tableOffset + tableLen else { continue }
                    if platformID == 1 && strLen > 7 && out[absStrOff + 6] == 0x2B {
                        let isUpper = (0..<6).allSatisfy { out[absStrOff + $0] >= 0x41 && out[absStrOff + $0] <= 0x5A }
                        if isUpper {
                            let newLen = strLen - 7
                            out[recOffset + 8] = UInt8((newLen >> 8) & 0xFF)
                            out[recOffset + 9] = UInt8(newLen & 0xFF)
                            let newOff = strOff + 7
                            out[recOffset + 10] = UInt8((newOff >> 8) & 0xFF)
                            out[recOffset + 11] = UInt8(newOff & 0xFF)
                        }
                    } else if (platformID == 0 || platformID == 3) && strLen > 14 && out[absStrOff + 12] == 0x00 && out[absStrOff + 13] == 0x2B {
                        let isUpper = (0..<6).allSatisfy {
                            out[absStrOff + $0 * 2] == 0x00 && out[absStrOff + $0 * 2 + 1] >= 0x41 && out[absStrOff + $0 * 2 + 1] <= 0x5A
                        }
                        if isUpper {
                            let newLen = strLen - 14
                            out[recOffset + 8] = UInt8((newLen >> 8) & 0xFF)
                            out[recOffset + 9] = UInt8(newLen & 0xFF)
                            let newOff = strOff + 14
                            out[recOffset + 10] = UInt8((newOff >> 8) & 0xFF)
                            out[recOffset + 11] = UInt8(newOff & 0xFF)
                        }
                    }
                }
                break
            }
        }
        return out
    }

    private static func parseToUnicode(_ text: String) -> [UInt16: UInt16] {
        var map: [UInt16: UInt16] = [:]
        guard let hexRegex = try? NSRegularExpression(pattern: "<([0-9A-Fa-f]+)>") else { return map }
        let lines = text.components(separatedBy: .newlines)
        var mode = 0 // 1 = bfchar, 2 = bfrange
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("beginbfchar") { mode = 1; continue }
            if trimmed.hasSuffix("beginbfrange") { mode = 2; continue }
            if trimmed.hasPrefix("endbfchar") || trimmed.hasPrefix("endbfrange") { mode = 0; continue }
            guard mode != 0 else { continue }
            let matches = hexRegex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
            let hexes = matches.compactMap { m -> UInt16? in
                guard let r = Range(m.range(at: 1), in: trimmed) else { return nil }
                return UInt16(trimmed[r], radix: 16)
            }
            if mode == 1 && hexes.count >= 2 {
                map[hexes[1]] = hexes[0]
            } else if mode == 2 && hexes.count >= 3 {
                let startCode = hexes[0]
                let endCode = hexes[1]
                let startUni = hexes[2]
                if endCode >= startCode && (endCode - startCode) <= 512 {
                    for delta in 0...(endCode - startCode) {
                        map[startUni &+ delta] = startCode &+ delta
                    }
                }
            }
        }
        return map
    }

    private static func patchTrueTypeCmapIfNeeded(
        _ data: Data,
        toUnicodeMap: [UInt16: UInt16],
        isCIDFont: Bool
    ) -> Data {
        guard data.count > 12,
              let provider = CGDataProvider(data: data as CFData),
              let cgFont = CGFont(provider) else { return data }
        let ctFont = CTFontCreateWithGraphicsFont(cgFont, 12.0, nil, nil)

        var fullMap: [UInt16: UInt16] = [:]
        var probeChars: [UniChar] = Array(0x0020...0x024F)
        probeChars.append(contentsOf: [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026, 0x20AC])
        var existingGlyphs = [CGGlyph](repeating: 0, count: probeChars.count)
        _ = CTFontGetGlyphsForCharacters(ctFont, probeChars, &existingGlyphs, probeChars.count)
        for (i, u) in probeChars.enumerated() where existingGlyphs[i] != 0 {
            fullMap[u] = existingGlyphs[i]
        }

        var addedCount = 0
        for (uni, code) in toUnicodeMap {
            guard fullMap[uni] == nil || fullMap[uni] == 0 else { continue }
            if isCIDFont {
                if code != 0 && Int(code) < cgFont.numberOfGlyphs {
                    fullMap[uni] = code
                    addedCount += 1
                }
            } else if code < 256 {
                var puaChar: [UniChar] = [0xF000 &+ code]
                var puaGlyph: [CGGlyph] = [0]
                _ = CTFontGetGlyphsForCharacters(ctFont, &puaChar, &puaGlyph, 1)
                if puaGlyph[0] != 0 {
                    fullMap[uni] = puaGlyph[0]
                    addedCount += 1
                }
            }
        }

        guard addedCount > 0 else { return data }

        let numTables = (Int(data[4]) << 8) | Int(data[5])
        guard numTables > 0, numTables < 64, data.count >= 12 + numTables * 16 else { return data }
        var cmapDirEntryOffset: Int? = nil
        for i in 0..<numTables {
            let entryOffset = 12 + i * 16
            let tag = String(bytes: data[entryOffset..<(entryOffset + 4)], encoding: .ascii) ?? ""
            if tag == "cmap" {
                cmapDirEntryOffset = entryOffset
                break
            }
        }
        guard let entryOffset = cmapDirEntryOffset else { return data }

        let newCmap = buildFormat4CmapTable(mapping: fullMap)
        var out = data
        while (out.count % 4) != 0 {
            out.append(0)
        }
        let newOffset = UInt32(out.count)
        let newLen = UInt32(newCmap.count)
        out.append(newCmap)

        out[entryOffset + 8] = UInt8((newOffset >> 24) & 0xFF)
        out[entryOffset + 9] = UInt8((newOffset >> 16) & 0xFF)
        out[entryOffset + 10] = UInt8((newOffset >> 8) & 0xFF)
        out[entryOffset + 11] = UInt8(newOffset & 0xFF)
        out[entryOffset + 12] = UInt8((newLen >> 24) & 0xFF)
        out[entryOffset + 13] = UInt8((newLen >> 16) & 0xFF)
        out[entryOffset + 14] = UInt8((newLen >> 8) & 0xFF)
        out[entryOffset + 15] = UInt8(newLen & 0xFF)
        return out
    }

    private static func buildFormat4CmapTable(mapping: [UInt16: UInt16]) -> Data {
        let sorted = mapping.keys.sorted()
        var startCodes: [UInt16] = []
        var endCodes: [UInt16] = []
        var idDeltas: [UInt16] = []
        for uni in sorted {
            guard let gid = mapping[uni], gid != 0, uni < 0xFFFF else { continue }
            let delta = UInt16(bitPattern: Int16(truncatingIfNeeded: Int(gid) - Int(uni)))
            if let lastEnd = endCodes.last, let lastDelta = idDeltas.last, uni == lastEnd + 1 && delta == lastDelta {
                endCodes[endCodes.count - 1] = uni
            } else {
                startCodes.append(uni)
                endCodes.append(uni)
                idDeltas.append(delta)
            }
        }
        startCodes.append(0xFFFF)
        endCodes.append(0xFFFF)
        idDeltas.append(1)

        let segCount = UInt16(startCodes.count)
        let segCountX2 = segCount * 2
        var searchRange: UInt16 = 2
        var entrySelector: UInt16 = 0
        while searchRange * 2 <= segCountX2 {
            searchRange *= 2
            entrySelector += 1
        }
        let rangeShift = segCountX2 - searchRange
        let subtableLength = UInt16(16 + Int(segCount) * 8)

        var sub = Data()
        func appendU16(_ v: UInt16) {
            sub.append(UInt8((v >> 8) & 0xFF))
            sub.append(UInt8(v & 0xFF))
        }
        appendU16(4)
        appendU16(subtableLength)
        appendU16(0)
        appendU16(segCountX2)
        appendU16(searchRange)
        appendU16(entrySelector)
        appendU16(rangeShift)
        for c in endCodes { appendU16(c) }
        appendU16(0)
        for c in startCodes { appendU16(c) }
        for d in idDeltas { appendU16(d) }
        for _ in 0..<segCount { appendU16(0) }

        var cmap = Data()
        func cmapU16(_ v: UInt16) { cmap.append(UInt8((v >> 8) & 0xFF)); cmap.append(UInt8(v & 0xFF)) }
        func cmapU32(_ v: UInt32) {
            cmap.append(UInt8((v >> 24) & 0xFF))
            cmap.append(UInt8((v >> 16) & 0xFF))
            cmap.append(UInt8((v >> 8) & 0xFF))
            cmap.append(UInt8(v & 0xFF))
        }
        cmapU16(0)
        cmapU16(2)
        cmapU16(0); cmapU16(3); cmapU32(20)
        cmapU16(3); cmapU16(1); cmapU32(20)
        cmap.append(sub)
        return cmap
    }
}
