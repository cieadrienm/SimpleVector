import AppKit
import SimpleVectorCore
import SwiftUI

/// Coordinate mapper between a viewport pane `(0...paneW, 0...paneH)` and page points `(0...pageW, 0...pageH)`.
struct PageCanvasGeometry {
    let paneSize: CGSize
    let pageWidth: Double
    let pageHeight: Double
    let zoomScale: CGFloat
    let panOffset: CGSize
    var pad: CGFloat = 28

    var baseSheetRect: CGRect {
        let availW = max(16, paneSize.width - pad * 2)
        let availH = max(16, paneSize.height - pad * 2)
        let aspect = CGFloat(max(1.0, pageWidth) / max(1.0, pageHeight))

        let fittedW: CGFloat
        let fittedH: CGFloat
        if availW / availH > aspect {
            fittedH = availH
            fittedW = availH * aspect
        } else {
            fittedW = availW
            fittedH = availW / aspect
        }
        return CGRect(
            x: (paneSize.width - fittedW) * 0.5,
            y: (paneSize.height - fittedH) * 0.5,
            width: fittedW,
            height: fittedH
        )
    }

    var scale: CGFloat {
        let rect = baseSheetRect
        return (rect.width / CGFloat(max(1.0, pageWidth))) * zoomScale
    }

    var zoomedSheetRect: CGRect {
        let base = baseSheetRect
        let center = CGPoint(x: paneSize.width * 0.5, y: paneSize.height * 0.5)
        let minX = center.x + (base.minX - center.x) * zoomScale + panOffset.width
        let minY = center.y + (base.minY - center.y) * zoomScale + panOffset.height
        return CGRect(
            x: minX,
            y: minY,
            width: base.width * zoomScale,
            height: base.height * zoomScale
        )
    }

    var pageToPaneTransform: CGAffineTransform {
        let sheet = zoomedSheetRect
        let s = sheet.width / CGFloat(max(1.0, pageWidth))
        return CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: sheet.minX, ty: sheet.minY)
    }

    var visiblePageRect: VectorRect {
        let p0 = paneToPage(.zero)
        let p1 = paneToPage(CGPoint(x: paneSize.width, y: paneSize.height))
        let minX = min(p0.x, p1.x) - 24.0
        let minY = min(p0.y, p1.y) - 24.0
        let maxX = max(p0.x, p1.x) + 24.0
        let maxY = max(p0.y, p1.y) + 24.0
        return VectorRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    func pageToPane(_ pt: VectorPoint) -> CGPoint {
        let sheet = zoomedSheetRect
        let s = sheet.width / CGFloat(max(1.0, pageWidth))
        return CGPoint(
            x: sheet.minX + CGFloat(pt.x) * s,
            y: sheet.minY + CGFloat(pt.y) * s
        )
    }

    func pageRectToPane(_ rect: VectorRect) -> CGRect {
        let p0 = pageToPane(VectorPoint(x: rect.minX, y: rect.minY))
        let p1 = pageToPane(VectorPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: p0.x, y: p0.y, width: p1.x - p0.x, height: p1.y - p0.y)
    }

    func paneToPage(_ panePt: CGPoint) -> VectorPoint {
        let sheet = zoomedSheetRect
        let s = max(1e-4, sheet.width / CGFloat(max(1.0, pageWidth)))
        return VectorPoint(
            x: Double((panePt.x - sheet.minX) / s),
            y: Double((panePt.y - sheet.minY) / s)
        )
    }
}

/// Pre-built geometry and PDF backdrop cache keyed by `(page.id, revision)` so zero `Path` or `NSImage`
/// is allocated per frame during 60–120 Hz panning and zooming (G46).
@MainActor
final class VectorSceneRenderCache {
    static let shared = VectorSceneRenderCache()

    struct CachedElementGeometry {
        let id: UUID
        let frame: VectorRect
        let path: Path?
        let arrowHeadPath: Path?
    }

    private var cachedPageID: UUID? = nil
    private var cachedRevision: Int = -1
    private var cachedGeometries: [UUID: CachedElementGeometry] = [:]
    private var pdfBackdropCache: [UUID: NSImage] = [:]
    private var assetImageCache: [String: NSImage] = [:]

    func assetImage(for data: Data, ext: String?, removeWhiteBackground: Bool) -> NSImage? {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data.prefix(64))
        hasher.combine(data.suffix(64))
        hasher.combine(ext ?? "")
        hasher.combine(removeWhiteBackground)
        let key = "\(hasher.finalize())_\(data.count)_\(removeWhiteBackground ? 1 : 0)"
        if let existing = assetImageCache[key] {
            return existing
        }
        guard let cgImg = AssetImageCodec.renderCGImage(
            from: data,
            ext: ext,
            targetMaxDimension: 720,
            removeWhiteBackground: removeWhiteBackground
        ) else { return nil }
        let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
        assetImageCache[key] = nsImg
        return nsImg
    }

    func backdropImage(for page: VectorPage) -> NSImage? {
        guard let pdfData = page.pdfPageData else { return nil }
        if let existing = pdfBackdropCache[page.id] {
            return existing
        }
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let cgPDF = CGPDFDocument(provider),
              let cgPage = cgPDF.page(at: max(1, page.pdfPageIndex + 1)) else { return nil }

        let scale: CGFloat = 2.0
        let pixelW = max(16, Int(round(page.width * Double(scale))))
        let pixelH = max(16, Int(round(page.height * Double(scale))))
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

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        let mediaBox = cgPage.getBoxRect(.mediaBox)
        ctx.scaleBy(
            x: CGFloat(pixelW) / max(1, mediaBox.width),
            y: CGFloat(pixelH) / max(1, mediaBox.height)
        )
        ctx.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
        ctx.drawPDFPage(cgPage)

        guard let cgImg = ctx.makeImage() else { return nil }
        let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: page.width, height: page.height))
        pdfBackdropCache[page.id] = nsImg
        return nsImg
    }

    func geometries(for page: VectorPage, revision: Int) -> [UUID: CachedElementGeometry] {
        if cachedPageID == page.id && cachedRevision == revision {
            return cachedGeometries
        }
        var map: [UUID: CachedElementGeometry] = [:]
        map.reserveCapacity(page.elements.count)
        for el in page.elements {
            let (path, arrowPath) = Self.buildPageSpacePath(for: el)
            map[el.id] = CachedElementGeometry(id: el.id, frame: el.frame, path: path, arrowHeadPath: arrowPath)
        }
        cachedPageID = page.id
        cachedRevision = revision
        cachedGeometries = map
        return map
    }

    static func buildPageSpacePath(for el: VectorElement) -> (Path?, Path?) {
        let f = el.frame
        switch el.kind {
        case .shape(let s):
            switch s.shapeType {
            case .rectangle:
                return (Path(f.cgRect), nil)
            case .roundedRectangle:
                let r = CGFloat(min(s.cornerRadius, min(f.width, f.height) * 0.5))
                return (Path(roundedRect: f.cgRect, cornerRadius: r), nil)
            case .ellipse:
                return (Path(ellipseIn: f.cgRect), nil)
            case .line, .arrow:
                var line = Path()
                let p0 = CGPoint(x: f.minX, y: f.maxY)
                let p1 = CGPoint(x: f.maxX, y: f.minY)
                line.move(to: p0)
                line.addLine(to: p1)
                var heads = Path()
                let len = CGFloat(max(8.0, el.style.strokeWidth * 4.0))
                if s.endArrow || s.shapeType == .arrow {
                    addArrowHead(to: &heads, from: p0, to: p1, size: len)
                }
                if s.startArrow {
                    addArrowHead(to: &heads, from: p1, to: p0, size: len)
                }
                return (line, heads.isEmpty ? nil : heads)
            case .diamond:
                var d = Path()
                d.move(to: CGPoint(x: f.midX, y: f.minY))
                d.addLine(to: CGPoint(x: f.maxX, y: f.midY))
                d.addLine(to: CGPoint(x: f.midX, y: f.maxY))
                d.addLine(to: CGPoint(x: f.minX, y: f.midY))
                d.closeSubpath()
                return (d, nil)
            }

        case .path(let p):
            var path = Path()
            for sub in p.subpaths where !sub.points.isEmpty {
                path.move(to: el.denormalize(sub.points[0]).cgPoint)
                for pt in sub.points.dropFirst() {
                    path.addLine(to: el.denormalize(pt).cgPoint)
                }
                if sub.isClosed {
                    path.closeSubpath()
                }
            }
            return (path, nil)

        case .signature(let sig):
            var path = Path()
            for stroke in sig.strokes where !stroke.isEmpty {
                path.move(to: el.denormalize(stroke[0]).cgPoint)
                for pt in stroke.dropFirst() {
                    path.addLine(to: el.denormalize(pt).cgPoint)
                }
            }
            return (path, nil)

        case .text, .stamp:
            return (nil, nil)
        }
    }

    private static func addArrowHead(to path: inout Path, from p0: CGPoint, to p1: CGPoint, size: CGFloat) {
        let angle = atan2(p1.y - p0.y, p1.x - p0.x)
        let wing: CGFloat = .pi / 6.5
        let left = CGPoint(x: p1.x - size * cos(angle - wing), y: p1.y - size * sin(angle - wing))
        let right = CGPoint(x: p1.x - size * cos(angle + wing), y: p1.y - size * sin(angle + wing))
        path.move(to: p1)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
    }
}

struct CanvasViewportView: View {
    @Bindable var model: AppModel

    // Transient interactive state during a drag gesture
    @State private var activeFreehandPoints: [VectorPoint] = []
    @State private var shapeDragStartPage: VectorPoint? = nil
    @State private var shapeDragCurrentPage: VectorPoint? = nil
    @State private var movingElementInitialFrames: [UUID: VectorRect] = [:]
    @State private var resizingHandleIndex: Int? = nil
    @State private var resizingInitialFrame: VectorRect? = nil
    @State private var isRotatingElement: Bool = false
    @State private var panDragInitialOffset: CGSize? = nil
    @State private var magnifyStartZoom: CGFloat? = nil

    var body: some View {
        switch model.displayMode {
        case .singlePage:
            singlePageInteractiveCanvas
        case .multiPageContinuous:
            multiPageScrollCanvas
        case .multiPageGrid:
            multiPageGridCanvas
        }
    }

    // MARK: - 1. Single-Page Interactive Vector & PDF Canvas

    private var singlePageInteractiveCanvas: some View {
        let ctrl = model.controller
        let page = ctrl.currentPage
        let revision = ctrl.document.revision
        let cachedGeoms = VectorSceneRenderCache.shared.geometries(for: page, revision: revision)
        let backdropImg = VectorSceneRenderCache.shared.backdropImage(for: page)

        return GeometryReader { geo in
            let geom = PageCanvasGeometry(
                paneSize: geo.size,
                pageWidth: page.width,
                pageHeight: page.height,
                zoomScale: model.zoomScale,
                panOffset: model.panOffset
            )

            ZStack(alignment: .top) {
                Canvas(rendersAsynchronously: true) { ctx, canvasSize in
                    drawSinglePageScene(
                        ctx: &ctx,
                        canvasSize: canvasSize,
                        page: page,
                        geom: geom,
                        cachedGeoms: cachedGeoms,
                        backdropImg: backdropImg
                    )
                }
                .background(CanvasScrollEventMonitor(model: model))
                .gesture(canvasDragGesture(geom: geom))
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if magnifyStartZoom == nil {
                                magnifyStartZoom = model.zoomScale
                            }
                            let base = magnifyStartZoom ?? 1.0
                            model.zoomScale = min(6.0, max(0.25, base * value.magnification))
                        }
                        .onEnded { _ in
                            magnifyStartZoom = nil
                        }
                )

                // Top floating quick bar when editing a PDF or SVG text element
                if let editID = model.editingTextElementID,
                   let el = page.elements.first(where: { $0.id == editID }),
                   case .text(let t) = el.kind {
                    InlineTextEditorBar(
                        model: model,
                        elementID: editID,
                        payload: t
                    )
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Bottom HUD badge showing page info, tool hint, and quick actions
                VStack {
                    Spacer()
                    canvasBottomHUD(page: page)
                        .padding(.bottom, 10)
                }
            }
        }
    }

    private func drawSinglePageScene(
        ctx: inout GraphicsContext,
        canvasSize: CGSize,
        page: VectorPage,
        geom: PageCanvasGeometry,
        cachedGeoms: [UUID: VectorSceneRenderCache.CachedElementGeometry],
        backdropImg: NSImage?
    ) {
        let sheet = geom.zoomedSheetRect
        let tx = geom.pageToPaneTransform
        let visibleRect = geom.visiblePageRect

        // Subtle workspace dot/line grid behind the page
        let shadowRect = sheet.offsetBy(dx: 0, dy: 4)
        ctx.fill(Path(roundedRect: shadowRect, cornerRadius: 4), with: .color(Color.black.opacity(0.45)))

        // Paper background
        let bg = RGBAColor(hex: page.backgroundColorHex) ?? RGBAColor(r: 1, g: 1, b: 1)
        ctx.fill(Path(sheet), with: .color(Color(red: bg.r, green: bg.g, blue: bg.b)))

        // Clip to the page sheet
        ctx.drawLayer { pageLayer in
            pageLayer.clip(to: Path(sheet))

            // 1. Original PDF vector backdrop if present
            if let backdropImg {
                let resolved = pageLayer.resolve(Image(nsImage: backdropImg))
                pageLayer.draw(resolved, in: sheet)
            }

            // 2. Mask out edited, moved, or deleted PDF text blocks
            for mask in page.activeMaskRects where mask.rect.intersects(visibleRect) {
                let paneMask = geom.pageRectToPane(mask.rect)
                let mc = RGBAColor(hex: mask.colorHex) ?? bg
                pageLayer.fill(Path(paneMask), with: .color(Color(red: mc.r, green: mc.g, blue: mc.b)))
            }

            // 3. Draw elements with frustum culling & pre-built geometry cache (G46)
            for el in page.elements where el.visible && el.frame.intersects(visibleRect) {
                let isSelected = model.controller.selection.contains(el.id)

                if case .text(let t) = el.kind, t.isPDFExtracted {
                    // Draw subtle editable PDF text frame when showPDFTextBoxes is enabled
                    if model.showPDFTextBoxes || model.activeTool == .text || isSelected {
                        let paneRect = geom.pageRectToPane(el.frame)
                        let boxColor = el.hasModifiedPDFText ? Theme.alive.swiftUI : Theme.tcp.swiftUI
                        pageLayer.stroke(
                            Path(roundedRect: paneRect.insetBy(dx: -1, dy: -1), cornerRadius: 2),
                            with: .color(boxColor.opacity(isSelected ? 0.85 : 0.40)),
                            style: StrokeStyle(lineWidth: isSelected ? 1.3 : 0.8, dash: [3, 2])
                        )
                    }
                    if !el.hasModifiedPDFText && page.pdfPageData != nil {
                        continue
                    }
                }

                Self.drawElementInLayer(
                    el,
                    in: &pageLayer,
                    geom: geom,
                    tx: tx,
                    cached: cachedGeoms[el.id]
                )
            }

            // 4. Transient freehand signature / pen stroke preview
            if activeFreehandPoints.count >= 2 {
                var preview = Path()
                preview.move(to: geom.pageToPane(activeFreehandPoints[0]))
                for pt in activeFreehandPoints.dropFirst() {
                    preview.addLine(to: geom.pageToPane(pt))
                }
                let strokeColor = model.activeTool == .signature ? Color(red: 0.12, green: 0.23, blue: 0.54) : Theme.accent.swiftUI
                pageLayer.stroke(preview, with: .color(strokeColor), style: StrokeStyle(lineWidth: 2.2 * geom.zoomScale, lineCap: .round, lineJoin: .round))
            }

            // 5. Transient shape / arrow creation preview
            if let p0 = shapeDragStartPage, let p1 = shapeDragCurrentPage {
                let rect = VectorRect(
                    x: min(p0.x, p1.x),
                    y: min(p0.y, p1.y),
                    width: abs(p1.x - p0.x),
                    height: abs(p1.y - p0.y)
                )
                let paneRect = geom.pageRectToPane(rect)
                pageLayer.stroke(
                    Path(paneRect),
                    with: .color(Theme.accent.swiftUI),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
            }
        }

        // Page border
        ctx.stroke(Path(sheet), with: .color(Color.white.opacity(0.22)), lineWidth: 1.0)

        // Selection bounding boxes, resize handles & rotation handle outside clip
        for el in page.elements where model.controller.selection.contains(el.id) && el.visible {
            let selRect = geom.pageRectToPane(el.frame)
            ctx.drawLayer { selLayer in
                if abs(el.rotationDegrees) > 0.01 {
                    selLayer.translateBy(x: selRect.midX, y: selRect.midY)
                    selLayer.rotate(by: .degrees(el.rotationDegrees))
                    selLayer.translateBy(x: -selRect.midX, y: -selRect.midY)
                }
                selLayer.stroke(
                    Path(selRect),
                    with: .color(Theme.accent.swiftUI),
                    style: StrokeStyle(lineWidth: 1.5)
                )
                for handlePt in cornerHandles(for: selRect) {
                    let hRect = CGRect(x: handlePt.x - 4, y: handlePt.y - 4, width: 8, height: 8)
                    selLayer.fill(Path(roundedRect: hRect, cornerRadius: 2), with: .color(Theme.background.swiftUI))
                    selLayer.stroke(Path(roundedRect: hRect, cornerRadius: 2), with: .color(Theme.accent.swiftUI), lineWidth: 1.5)
                }

                // Top-center rotation handle stem + circle
                if !el.locked {
                    let topMid = CGPoint(x: selRect.midX, y: selRect.minY)
                    let rotKnob = CGPoint(x: selRect.midX, y: selRect.minY - 22)
                    var stem = Path()
                    stem.move(to: topMid)
                    stem.addLine(to: rotKnob)
                    selLayer.stroke(stem, with: .color(Theme.accent.swiftUI), lineWidth: 1.4)
                    let knobRect = CGRect(x: rotKnob.x - 5.5, y: rotKnob.y - 5.5, width: 11, height: 11)
                    selLayer.fill(Path(ellipseIn: knobRect), with: .color(Theme.accent.swiftUI))
                    selLayer.stroke(Path(ellipseIn: knobRect), with: .color(Theme.background.swiftUI), lineWidth: 1.5)
                }
            }

            if isRotatingElement || abs(el.rotationDegrees) > 0.2 {
                let rotPt = rotationHandlePoint(for: selRect, rotationDegrees: el.rotationDegrees)
                let degStr = String(format: "%+.0f°", el.rotationDegrees)
                let badge = Text(degStr)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent.swiftUI)
                ctx.draw(badge, at: CGPoint(x: rotPt.x, y: rotPt.y - 14), anchor: .center)
            }
        }
    }

    fileprivate static func drawElementInLayer(
        _ el: VectorElement,
        in parentLayer: inout GraphicsContext,
        geom: PageCanvasGeometry,
        tx: CGAffineTransform,
        cached: VectorSceneRenderCache.CachedElementGeometry?
    ) {
        let paneRect = geom.pageRectToPane(el.frame)
        parentLayer.drawLayer { layer in
            if abs(el.rotationDegrees) > 0.01 {
                layer.translateBy(x: paneRect.midX, y: paneRect.midY)
                layer.rotate(by: .degrees(el.rotationDegrees))
                layer.translateBy(x: -paneRect.midX, y: -paneRect.midY)
            }
            let fillRGB = RGBAColor(hex: el.style.fillColorHex)
            let strokeRGB = RGBAColor(hex: el.style.strokeColorHex)
            let lineW = max(0.8, CGFloat(el.style.strokeWidth) * geom.scale)
            let dash: [CGFloat] = el.style.dashed ? [6 * geom.zoomScale, 4 * geom.zoomScale] : []

            if let path = cached?.path {
                let transformed = path.applying(tx)
                if let fillRGB {
                    layer.fill(
                        transformed,
                        with: .color(Color(red: fillRGB.r, green: fillRGB.g, blue: fillRGB.b, opacity: el.style.opacity))
                    )
                }
                if let strokeRGB, el.style.strokeWidth > 0 {
                    layer.stroke(
                        transformed,
                        with: .color(Color(red: strokeRGB.r, green: strokeRGB.g, blue: strokeRGB.b, opacity: el.style.opacity)),
                        style: StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round, dash: dash)
                    )
                }
                if let heads = cached?.arrowHeadPath?.applying(tx), let sc = strokeRGB ?? fillRGB {
                    layer.fill(
                        heads,
                        with: .color(Color(red: sc.r, green: sc.g, blue: sc.b, opacity: el.style.opacity))
                    )
                }
            }

            switch el.kind {
            case .signature(let sig):
                if let assetData = sig.assetData, !assetData.isEmpty,
                   let nsImg = VectorSceneRenderCache.shared.assetImage(
                       for: assetData,
                       ext: sig.assetExtension,
                       removeWhiteBackground: sig.removeWhiteBackground
                   ) {
                    layer.opacity = el.style.opacity
                    let resolved = layer.resolve(Image(nsImage: nsImg))
                    layer.draw(resolved, in: paneRect)
                } else {
                    let meta = [sig.signerName, sig.caption, sig.dateLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    if !meta.isEmpty {
                        let ink = strokeRGB ?? RGBAColor(hex: "#1E3A8A")!
                        let text = Text(meta)
                            .font(.system(size: max(6, 8.5 * geom.scale), weight: .medium))
                            .foregroundStyle(Color(red: ink.r, green: ink.g, blue: ink.b, opacity: el.style.opacity))
                        layer.draw(
                            text,
                            at: CGPoint(x: paneRect.minX + 2, y: paneRect.maxY - 2 * geom.scale),
                            anchor: .bottomLeading
                        )
                    }
                }

            case .text(let t):
                let tc = fillRGB ?? strokeRGB ?? RGBAColor(r: 0.07, g: 0.07, b: 0.09)
                let fontSize = max(4.5, CGFloat(t.fontSize) * geom.scale)
                let ctFont = PDFCodec.resolveCTFont(for: t, size: fontSize)
                let unscaledFont = PDFCodec.resolveCTFont(for: t, size: CGFloat(t.fontSize))
                let firstBaselineOffset = t.baselineOffset ?? Double(CTFontGetCapHeight(unscaledFont))
                let ascent = CTFontGetAscent(ctFont)
                let lineH = CGFloat(t.fontSize * 1.25) * geom.scale
                let lines = t.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                for (idx, lineStr) in lines.enumerated() where !lineStr.isEmpty {
                    let (adaptedStr, accents) = PDFCodec.adaptStringForSubsetFont(lineStr, ctFont: unscaledFont, kern: t.letterSpacing)
                    let textColor = Color(red: tc.r, green: tc.g, blue: tc.b, opacity: el.style.opacity)
                    let txt = Text(adaptedStr)
                        .font(Font(ctFont))
                        .tracking(CGFloat(t.letterSpacing) * geom.scale)
                        .foregroundStyle(textColor)
                    let paneBaselineY = paneRect.minY + CGFloat(firstBaselineOffset) * geom.scale + CGFloat(idx) * lineH
                    let drawTopY = paneBaselineY - ascent
                    let anchorPt: CGPoint
                    let unitAnchor: UnitPoint
                    switch t.alignment {
                    case .left:
                        anchorPt = CGPoint(x: paneRect.minX, y: drawTopY)
                        unitAnchor = .topLeading
                    case .center:
                        anchorPt = CGPoint(x: paneRect.midX, y: drawTopY)
                        unitAnchor = .top
                    case .right:
                        anchorPt = CGPoint(x: paneRect.maxX, y: drawTopY)
                        unitAnchor = .topTrailing
                    }
                    layer.draw(txt, at: anchorPt, anchor: unitAnchor)

                    if !accents.isEmpty {
                        var accentPath = Path()
                        for acc in accents {
                            let cx = paneRect.minX + CGFloat(acc.centerX) * geom.scale
                            let topY = paneBaselineY + CGFloat(acc.capTopY) * geom.scale
                            let ch = CGFloat(acc.capHeight) * geom.scale
                            switch acc.kind {
                            case .acute:
                                accentPath.move(to: CGPoint(x: cx - ch * 0.05, y: topY - ch * 0.08))
                                accentPath.addLine(to: CGPoint(x: cx + ch * 0.12, y: topY - ch * 0.23))
                            case .grave:
                                accentPath.move(to: CGPoint(x: cx + ch * 0.05, y: topY - ch * 0.08))
                                accentPath.addLine(to: CGPoint(x: cx - ch * 0.12, y: topY - ch * 0.23))
                            case .circumflex:
                                accentPath.move(to: CGPoint(x: cx - ch * 0.13, y: topY - ch * 0.08))
                                accentPath.addLine(to: CGPoint(x: cx, y: topY - ch * 0.22))
                                accentPath.addLine(to: CGPoint(x: cx + ch * 0.13, y: topY - ch * 0.08))
                            case .diaeresis:
                                let r = max(0.8, ch * 0.08)
                                accentPath.addEllipse(in: CGRect(x: cx - ch * 0.11 - r, y: topY - ch * 0.16 - r, width: r * 2, height: r * 2))
                                accentPath.addEllipse(in: CGRect(x: cx + ch * 0.11 - r, y: topY - ch * 0.16 - r, width: r * 2, height: r * 2))
                            case .cedilla:
                                accentPath.move(to: CGPoint(x: cx, y: paneBaselineY))
                                accentPath.addLine(to: CGPoint(x: cx - ch * 0.03, y: paneBaselineY + ch * 0.12))
                                accentPath.addLine(to: CGPoint(x: cx + ch * 0.06, y: paneBaselineY + ch * 0.20))
                            }
                        }
                        let strokeW = max(1.0, CGFloat(t.fontSize * 0.09) * geom.scale)
                        layer.stroke(accentPath, with: .color(textColor), style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round))
                    }
                }

            case .stamp(let st):
                if let assetData = st.assetData, !assetData.isEmpty,
                   let nsImg = VectorSceneRenderCache.shared.assetImage(
                       for: assetData,
                       ext: st.assetExtension,
                       removeWhiteBackground: st.removeWhiteBackground
                   ) {
                    layer.opacity = el.style.opacity
                    let resolved = layer.resolve(Image(nsImage: nsImg))
                    layer.draw(resolved, in: paneRect)
                } else {
                    let c = strokeRGB ?? RGBAColor(hex: st.stampKind.defaultColorHex) ?? RGBAColor(r: 0.1, g: 0.6, b: 0.3)
                    let color = Color(red: c.r, green: c.g, blue: c.b, opacity: el.style.opacity)
                    let outer = Path(roundedRect: paneRect, cornerRadius: 5 * geom.scale)
                    layer.fill(outer, with: .color(color.opacity(0.10)))
                    layer.stroke(outer, with: .color(color), lineWidth: max(1.2, 2.0 * geom.scale))
                    let inner = paneRect.insetBy(dx: 3 * geom.scale, dy: 3 * geom.scale)
                    if inner.width > 4 && inner.height > 4 {
                        layer.stroke(Path(roundedRect: inner, cornerRadius: 3.5 * geom.scale), with: .color(color), lineWidth: max(0.7, 0.9 * geom.scale))
                    }
                    let titleText = Text(st.title)
                        .font(.system(size: max(6, min(13.5, el.frame.height * 0.28) * geom.scale), weight: .bold))
                        .foregroundStyle(color)
                    layer.draw(titleText, at: CGPoint(x: paneRect.midX, y: paneRect.minY + paneRect.height * 0.38), anchor: .center)
                    if !st.subtitle.isEmpty {
                        let subText = Text(st.subtitle)
                            .font(.system(size: max(5, min(8.5, el.frame.height * 0.17) * geom.scale), weight: .medium))
                            .foregroundStyle(color)
                        layer.draw(subText, at: CGPoint(x: paneRect.midX, y: paneRect.minY + paneRect.height * 0.72), anchor: .center)
                    }
                }

            default:
                break
            }
        }
    }

    private func cornerHandles(for rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
    }

    private func rotatePoint(_ pt: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        guard abs(degrees) > 0.01 else { return pt }
        let rad = CGFloat(degrees * .pi / 180.0)
        let dx = pt.x - center.x
        let dy = pt.y - center.y
        return CGPoint(
            x: center.x + dx * cos(rad) - dy * sin(rad),
            y: center.y + dx * sin(rad) + dy * cos(rad)
        )
    }

    private func rotatedCornerHandles(for rect: CGRect, rotationDegrees: Double) -> [CGPoint] {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return cornerHandles(for: rect).map { rotatePoint($0, around: center, degrees: rotationDegrees) }
    }

    private func rotationHandlePoint(for rect: CGRect, rotationDegrees: Double) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let unrotated = CGPoint(x: rect.midX, y: rect.minY - 22)
        return rotatePoint(unrotated, around: center, degrees: rotationDegrees)
    }

    // MARK: - Interactive Gesture Handling (Select, Resize, Edit PDF Text, Sign, Draw)

    private func canvasDragGesture(geom: PageCanvasGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startPane = value.startLocation
                let currentPane = value.location
                let startPage = geom.paneToPage(startPane)
                let currentPagePt = geom.paneToPage(currentPane)
                let ctrl = model.controller

                switch model.activeTool {
                case .signature, .pen:
                    if activeFreehandPoints.isEmpty {
                        activeFreehandPoints = [startPage]
                    } else {
                        activeFreehandPoints.append(currentPagePt)
                    }

                case .rectangle, .ellipse, .arrow:
                    if shapeDragStartPage == nil {
                        shapeDragStartPage = startPage
                    }
                    shapeDragCurrentPage = currentPagePt

                case .stamp:
                    break

                case .text:
                    break

                case .select:
                    // Check if starting on the rotation handle or a resize handle of the selected element
                    if movingElementInitialFrames.isEmpty && resizingHandleIndex == nil && !isRotatingElement && panDragInitialOffset == nil {
                        if let sel = ctrl.primarySelectedElement, !sel.locked {
                            let paneRect = geom.pageRectToPane(sel.frame)
                            let rotPt = rotationHandlePoint(for: paneRect, rotationDegrees: sel.rotationDegrees)
                            if hypot(rotPt.x - startPane.x, rotPt.y - startPane.y) <= 11.0 {
                                isRotatingElement = true
                                ctrl.history.record(ctrl.document)
                                return
                            }
                            let handles = rotatedCornerHandles(for: paneRect, rotationDegrees: sel.rotationDegrees)
                            if let hIdx = handles.firstIndex(where: { hypot($0.x - startPane.x, $0.y - startPane.y) <= 9.0 }) {
                                resizingHandleIndex = hIdx
                                resizingInitialFrame = sel.frame
                                ctrl.history.record(ctrl.document)
                                return
                            }
                        }

                        // Hit-test elements from top to bottom (preferring tight containment and closest vertical center)
                        if let hit = Self.hitTestElement(at: startPage, in: ctrl.currentPage.elements, textOnly: false) {
                            if !ctrl.selection.contains(hit.id) {
                                ctrl.selection = [hit.id]
                            }
                            if case .text = hit.kind {
                                model.editingTextElementID = hit.id
                            } else {
                                model.editingTextElementID = nil
                            }
                            var map: [UUID: VectorRect] = [:]
                            for el in ctrl.selectedElements where !el.locked {
                                map[el.id] = el.frame
                            }
                            movingElementInitialFrames = map
                            if !map.isEmpty {
                                ctrl.history.record(ctrl.document)
                            }
                        } else {
                            ctrl.selection.removeAll()
                            model.editingTextElementID = nil
                            panDragInitialOffset = model.panOffset
                        }
                    }

                    // Apply rotation, resize, element move, or viewport pan if dragging
                    if isRotatingElement, let sel = ctrl.primarySelectedElement {
                        let paneRect = geom.pageRectToPane(sel.frame)
                        let center = CGPoint(x: paneRect.midX, y: paneRect.midY)
                        var deg = atan2(Double(currentPane.y - center.y), Double(currentPane.x - center.x)) * 180.0 / .pi + 90.0
                        while deg > 180.0 { deg -= 360.0 }
                        while deg < -180.0 { deg += 360.0 }
                        if NSEvent.modifierFlags.contains(.shift) {
                            deg = (deg / 15.0).rounded() * 15.0
                        } else {
                            for cardinal in [-180.0, -90.0, 0.0, 90.0, 180.0] where abs(deg - cardinal) < 2.2 {
                                deg = cardinal
                                break
                            }
                        }
                        VectorOperations.updateElement(id: sel.id, onPage: ctrl.currentPageIndex, in: &ctrl.document) { el in
                            el.rotationDegrees = deg
                        }
                        return
                    }

                    let dx = currentPagePt.x - startPage.x
                    let dy = currentPagePt.y - startPage.y
                    if let hIdx = resizingHandleIndex, let initFrame = resizingInitialFrame, let selID = ctrl.primarySelectedElement?.id {
                        var newFrame = initFrame
                        switch hIdx {
                        case 0: // top-left
                            newFrame = VectorRect(x: initFrame.x + dx, y: initFrame.y + dy, width: max(14, initFrame.width - dx), height: max(12, initFrame.height - dy))
                        case 1: // top-right
                            newFrame = VectorRect(x: initFrame.x, y: initFrame.y + dy, width: max(14, initFrame.width + dx), height: max(12, initFrame.height - dy))
                        case 2: // bottom-right
                            newFrame = VectorRect(x: initFrame.x, y: initFrame.y, width: max(14, initFrame.width + dx), height: max(12, initFrame.height + dy))
                        case 3: // bottom-left
                            newFrame = VectorRect(x: initFrame.x + dx, y: initFrame.y, width: max(14, initFrame.width - dx), height: max(12, initFrame.height + dy))
                        default:
                            break
                        }
                        VectorOperations.updateElement(id: selID, onPage: ctrl.currentPageIndex, in: &ctrl.document) { el in
                            el.frame = newFrame
                        }
                    } else if !movingElementInitialFrames.isEmpty && hypot(dx, dy) > 1.2 {
                        for (id, initFrame) in movingElementInitialFrames {
                            VectorOperations.updateElement(id: id, onPage: ctrl.currentPageIndex, in: &ctrl.document) { el in
                                el.frame = initFrame.offsetBy(dx: dx, dy: dy)
                            }
                        }
                    } else if let initPan = panDragInitialOffset, hypot(value.translation.width, value.translation.height) > 2.0 {
                        model.panOffset = CGSize(
                            width: initPan.width + value.translation.width,
                            height: initPan.height + value.translation.height
                        )
                    }
                }
            }
            .onEnded { value in
                let startPage = geom.paneToPage(value.startLocation)
                let endPage = geom.paneToPage(value.location)
                let ctrl = model.controller

                switch model.activeTool {
                case .signature:
                    if activeFreehandPoints.count >= 4, startPage.distance(to: endPage) > 8.0 {
                        let sigEl = VectorOperations.makeFreehandSignatureElement(
                            pageStrokes: [activeFreehandPoints],
                            signerName: ctrl.activeSignaturePreset.signerName,
                            colorHex: ctrl.activeSignaturePreset.colorHex
                        )
                        ctrl.perform(L("Signature manuscrite tracée", "Handwritten signature drawn")) { doc in
                            VectorOperations.addElement(sigEl, toPage: ctrl.currentPageIndex, in: &doc)
                        }
                        ctrl.selection = [sigEl.id]
                    } else {
                        ctrl.stampActiveSignature(at: endPage)
                    }
                    activeFreehandPoints.removeAll()
                    model.activeTool = .select

                case .pen:
                    if activeFreehandPoints.count >= 2 {
                        let smoothed = StrokeSmoother.smooth(activeFreehandPoints, iterations: 2)
                        let (bounds, norm) = StrokeSmoother.normalizeStrokes([smoothed])
                        let el = VectorElement(
                            name: L("Tracé libre", "Freehand Path"),
                            kind: .path(PathPayload(subpaths: [VectorSubpath(points: norm[0], isClosed: false)])),
                            frame: bounds,
                            style: VectorStyle(strokeColorHex: "#111317", fillColorHex: nil, strokeWidth: 2.0)
                        )
                        ctrl.perform(L("Tracé vectoriel ajouté", "Vector path added")) { doc in
                            VectorOperations.addElement(el, toPage: ctrl.currentPageIndex, in: &doc)
                        }
                        ctrl.selection = [el.id]
                    }
                    activeFreehandPoints.removeAll()

                case .rectangle, .ellipse, .arrow:
                    let shapeType: VectorShapeType
                    switch model.activeTool {
                    case .ellipse: shapeType = .ellipse
                    case .arrow: shapeType = .arrow
                    default: shapeType = .roundedRectangle
                    }
                    let w = max(36.0, abs(endPage.x - startPage.x))
                    let h = max(24.0, abs(endPage.y - startPage.y))
                    let rect = VectorRect(
                        x: min(startPage.x, endPage.x),
                        y: min(startPage.y, endPage.y),
                        width: w,
                        height: h
                    )
                    ctrl.addShape(shapeType, at: rect)
                    shapeDragStartPage = nil
                    shapeDragCurrentPage = nil
                    model.activeTool = .select

                case .stamp:
                    ctrl.stampApprovalBadge(at: endPage)
                    model.activeTool = .select

                case .text:
                    if let hit = Self.hitTestElement(at: endPage, in: ctrl.currentPage.elements, textOnly: true) {
                        ctrl.selection = [hit.id]
                        model.editingTextElementID = hit.id
                    } else {
                        ctrl.addTextBlock(at: endPage)
                        model.editingTextElementID = ctrl.selection.first
                    }
                    model.activeTool = .select

                case .select:
                    movingElementInitialFrames.removeAll()
                    resizingHandleIndex = nil
                    resizingInitialFrame = nil
                    isRotatingElement = false
                    panDragInitialOffset = nil
                }
            }
    }

    static func hitTestElement(at pagePt: VectorPoint, in elements: [VectorElement], textOnly: Bool) -> VectorElement? {
        let candidates = elements.reversed().filter { el in
            guard el.visible else { return false }
            if textOnly {
                guard case .text = el.kind else { return false }
            }
            return el.frame.contains(pagePt, margin: 3.0)
        }
        guard !candidates.isEmpty else { return nil }

        // Prefer elements whose tight frame (margin <= 0.5) contains the point
        let tightCandidates = candidates.filter { $0.frame.contains(pagePt, margin: 0.5) }
        let pool = tightCandidates.isEmpty ? candidates : tightCandidates

        return pool.min { a, b in
            let distA = abs(a.frame.midY - pagePt.y)
            let distB = abs(b.frame.midY - pagePt.y)
            return distA < distB
        }
    }

    private func canvasBottomHUD(page: VectorPage) -> some View {
        HStack(spacing: 10) {
            Text("\(page.title) · \(page.dimensionsLabel)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textDim.swiftUI)

            Divider().frame(height: 11)

            Text(model.activeTool.helpText)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.accent.swiftUI)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Theme.panel.swiftUI.opacity(0.92))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }

    // MARK: - 2. Multi-Page Continuous Scroll Mode (`⌘2`)

    private var multiPageScrollCanvas: some View {
        let ctrl = model.controller
        return ScrollView {
            LazyVStack(spacing: 22) {
                ForEach(Array(ctrl.document.pages.enumerated()), id: \.element.id) { index, page in
                    MultiPageCardView(
                        model: model,
                        page: page,
                        pageIndex: index,
                        isCurrent: index == ctrl.currentPageIndex,
                        cardWidth: 620
                    )
                }
            }
            .padding(24)
        }
        .background(Theme.background.swiftUI)
    }

    // MARK: - 3. Multi-Page Contact Sheet Grid Mode (`⌘3`)

    private var multiPageGridCanvas: some View {
        let ctrl = model.controller
        let columns = [GridItem(.adaptive(minimum: 340, maximum: 460), spacing: 20)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Array(ctrl.document.pages.enumerated()), id: \.element.id) { index, page in
                    MultiPageCardView(
                        model: model,
                        page: page,
                        pageIndex: index,
                        isCurrent: index == ctrl.currentPageIndex,
                        cardWidth: 360
                    )
                }
            }
            .padding(24)
        }
        .background(Theme.background.swiftUI)
    }
}

// MARK: - Inline Floating Editor Bar for PDF & SVG Text

private struct InlineTextEditorBar: View {
    @Bindable var model: AppModel
    let elementID: UUID
    let payload: TextPayload

    @State private var draftText: String = ""

    var body: some View {
        let ctrl = model.controller
        HStack(spacing: 8) {
            Chip(
                text: payload.isPDFExtracted ? "PDF TXT" : "TEXTE",
                tint: payload.isPDFExtracted ? Theme.tcp.swiftUI : Theme.accent.swiftUI,
                filled: true
            )

            TextField(L("Texte du bloc…", "Block text…"), text: $draftText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text.swiftUI)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minWidth: 280, maxWidth: 440)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.07)))
                .onSubmit { commitEdit() }

            TextButton(title: L("Appliquer", "Apply"), symbol: "checkmark", prominent: true, compact: true) {
                commitEdit()
            }

            if payload.isPDFExtracted, let orig = payload.originalPDFText, orig != payload.text {
                TextButton(title: L("Origine PDF", "Original PDF"), symbol: "arrow.uturn.backward", compact: true) {
                    ctrl.perform(L("Texte PDF restauré", "PDF text restored")) { doc in
                        VectorOperations.updateElement(id: elementID, onPage: ctrl.currentPageIndex, in: &doc) { el in
                            if case .text(var t) = el.kind {
                                t.text = orig
                                if let origRect = t.originalPDFRect {
                                    el.frame = origRect
                                }
                                if let origSize = t.originalFontSize {
                                    t.fontSize = origSize
                                }
                                if let origBold = t.originalIsBold {
                                    t.isBold = origBold
                                }
                                if let origItalic = t.originalIsItalic {
                                    t.isItalic = origItalic
                                }
                                el.kind = .text(t)
                                el.style.fillColorHex = t.originalTextColorHex ?? "#111317"
                            }
                        }
                    }
                    draftText = orig
                }
            }

            Button {
                model.editingTextElementID = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textDim.swiftUI)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.panel.swiftUI)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.accent.swiftUI.opacity(0.55), lineWidth: 1)
                )
        )
        .onAppear { draftText = payload.text }
        .onChange(of: elementID) { _, _ in draftText = payload.text }
        .onChange(of: payload.text) { _, newVal in draftText = newVal }
    }

    private func commitEdit() {
        let ctrl = model.controller
        guard draftText != payload.text else { return }
        ctrl.perform(L("Texte modifié", "Text edited")) { doc in
            VectorOperations.updateElement(id: elementID, onPage: ctrl.currentPageIndex, in: &doc) { el in
                if case .text(var t) = el.kind {
                    t.text = draftText
                    el.kind = .text(t)
                    PDFCodec.updateTextFrameForEditedContent(&el)
                }
            }
        }
    }
}

// MARK: - Multi-Page Card View (`⌘2` & `⌘3`)

private struct MultiPageCardView: View {
    @Bindable var model: AppModel
    let page: VectorPage
    let pageIndex: Int
    let isCurrent: Bool
    let cardWidth: CGFloat

    var body: some View {
        let ctrl = model.controller
        let aspect = CGFloat(page.height / max(1, page.width))
        let previewHeight = cardWidth * aspect
        let cachedGeoms = VectorSceneRenderCache.shared.geometries(for: page, revision: ctrl.document.revision)
        let backdropImg = VectorSceneRenderCache.shared.backdropImage(for: page)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text(L("PAGE \(pageIndex + 1)", "PAGE \(pageIndex + 1)"))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(isCurrent ? Theme.background.swiftUI : Theme.accent.swiftUI)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(isCurrent ? Theme.accent.swiftUI : Theme.accent.swiftUI.opacity(0.15)))

                    Text(page.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text.swiftUI)
                }
                Spacer()
                HStack(spacing: 6) {
                    TextButton(title: L("Signer", "Sign"), symbol: "signature", compact: true) {
                        ctrl.currentPageIndex = pageIndex
                        ctrl.stampActiveSignature()
                    }
                    TextButton(title: L("Éditer", "Edit"), symbol: "pencil", prominent: isCurrent, compact: true) {
                        ctrl.currentPageIndex = pageIndex
                        model.displayMode = .singlePage
                    }
                }
            }

            Button {
                ctrl.currentPageIndex = pageIndex
                model.displayMode = .singlePage
            } label: {
                Canvas { ctx, size in
                    let geom = PageCanvasGeometry(
                        paneSize: size,
                        pageWidth: page.width,
                        pageHeight: page.height,
                        zoomScale: 1.0,
                        panOffset: .zero,
                        pad: 0
                    )
                    let sheet = CGRect(origin: .zero, size: size)
                    let bg = RGBAColor(hex: page.backgroundColorHex) ?? RGBAColor(r: 1, g: 1, b: 1)
                    ctx.fill(Path(sheet), with: .color(Color(red: bg.r, green: bg.g, blue: bg.b)))

                    if let backdropImg {
                        let resolved = ctx.resolve(Image(nsImage: backdropImg))
                        ctx.draw(resolved, in: sheet)
                    }
                    for mask in page.activeMaskRects {
                        let r = geom.pageRectToPane(mask.rect)
                        let mc = RGBAColor(hex: mask.colorHex) ?? bg
                        ctx.fill(Path(r), with: .color(Color(red: mc.r, green: mc.g, blue: mc.b)))
                    }
                    let tx = geom.pageToPaneTransform
                    for el in page.elements where el.visible {
                        if case .text(let t) = el.kind, t.isPDFExtracted, !el.hasModifiedPDFText, page.pdfPageData != nil {
                            continue
                        }
                        CanvasViewportView.drawElementInLayer(
                            el,
                            in: &ctx,
                            geom: geom,
                            tx: tx,
                            cached: cachedGeoms[el.id]
                        )
                    }
                }
                .frame(width: cardWidth, height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isCurrent ? Theme.accent.swiftUI : Color.white.opacity(0.18), lineWidth: isCurrent ? 2.0 : 1.0)
                )
                .shadow(color: .black.opacity(0.38), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? Theme.laneSelected.swiftUI : Theme.panel.swiftUI)
        )
    }
}

// MARK: - 60–120 Hz Trackpad Two-Finger Scroll & Mouse Wheel Pan / Zoom Monitor

private struct CanvasScrollEventMonitor: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> ScrollMonitorNSView {
        let view = ScrollMonitorNSView()
        view.model = model
        return view
    }

    func updateNSView(_ nsView: ScrollMonitorNSView, context: Context) {
        nsView.model = model
    }

    @MainActor
    final class ScrollMonitorNSView: NSView {
        weak var model: AppModel?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                    guard let self,
                          let model = self.model,
                          model.displayMode == .singlePage,
                          !model.hasOpenSheet,
                          let win = self.window,
                          event.window === win else {
                        return event
                    }
                    let localPt = self.convert(event.locationInWindow, from: nil)
                    guard self.bounds.contains(localPt) else { return event }

                    let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
                    let dx = event.scrollingDeltaX * scale
                    let dy = event.scrollingDeltaY * scale
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                    if flags.contains(.command) || flags.contains(.option) {
                        let factor = exp(dy * 0.005)
                        let oldZoom = model.zoomScale
                        let newZoom = min(6.0, max(0.25, oldZoom * factor))
                        let ratio = newZoom / max(0.01, oldZoom)
                        let center = CGPoint(x: self.bounds.width * 0.5, y: self.bounds.height * 0.5)
                        let cursorOffset = CGPoint(
                            x: localPt.x - center.x,
                            y: (self.bounds.height - localPt.y) - center.y
                        )
                        model.zoomScale = newZoom
                        model.panOffset = CGSize(
                            width: model.panOffset.width * ratio + cursorOffset.x * (1.0 - ratio),
                            height: model.panOffset.height * ratio + cursorOffset.y * (1.0 - ratio)
                        )
                    } else {
                        model.panOffset = CGSize(
                            width: model.panOffset.width + dx,
                            height: model.panOffset.height + dy
                        )
                    }
                    return nil
                }
            } else if window == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit {
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
        }
    }
}
