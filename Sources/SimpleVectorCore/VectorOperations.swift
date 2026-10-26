import Foundation

/// Pure, testable editing operations and undo/redo history store for `VectorDocument` (G35).
public enum VectorOperations {

    // MARK: - Page Operations

    public static func addPage(
        to doc: inout VectorDocument,
        after index: Int? = nil,
        preset: PageFormatPreset = .a4Portrait,
        title: String? = nil
    ) -> Int {
        let size = preset.sizePoints
        let pageNum = doc.pages.count + 1
        let page = VectorPage(
            title: title ?? "Page \(pageNum)",
            width: size.width,
            height: size.height,
            backgroundColorHex: "#FFFFFF"
        )
        let insertIndex: Int
        if let index, index >= 0, index < doc.pages.count {
            insertIndex = index + 1
        } else {
            insertIndex = doc.pages.count
        }
        doc.pages.insert(page, at: insertIndex)
        doc.revision &+= 1
        return insertIndex
    }

    public static func duplicatePage(in doc: inout VectorDocument, at index: Int) -> Int {
        guard doc.pages.indices.contains(index) else { return max(0, doc.pages.count - 1) }
        var copy = doc.pages[index]
        copy.id = UUID()
        copy.title = "\(copy.title) (copie)"
        copy.elements = copy.elements.map { el in
            var cloned = el
            cloned.id = UUID()
            return cloned
        }
        let target = index + 1
        doc.pages.insert(copy, at: target)
        doc.revision &+= 1
        return target
    }

    public static func deletePage(in doc: inout VectorDocument, at index: Int) -> Int {
        guard doc.pages.count > 1, doc.pages.indices.contains(index) else {
            return max(0, min(index, doc.pages.count - 1))
        }
        doc.pages.remove(at: index)
        doc.revision &+= 1
        return max(0, min(index, doc.pages.count - 1))
    }

    public static func movePage(in doc: inout VectorDocument, from source: Int, to destination: Int) -> Int {
        guard doc.pages.indices.contains(source),
              doc.pages.indices.contains(destination),
              source != destination else { return source }
        let page = doc.pages.remove(at: source)
        doc.pages.insert(page, at: destination)
        doc.revision &+= 1
        return destination
    }

    public static func rotatePage(in doc: inout VectorDocument, at index: Int, clockwise: Bool = true) {
        guard doc.pages.indices.contains(index) else { return }
        let oldW = doc.pages[index].width
        let oldH = doc.pages[index].height
        doc.pages[index].width = oldH
        doc.pages[index].height = oldW
        for i in doc.pages[index].elements.indices {
            let f = doc.pages[index].elements[i].frame
            if clockwise {
                doc.pages[index].elements[i].frame = VectorRect(
                    x: oldH - f.y - f.height,
                    y: f.x,
                    width: f.height,
                    height: f.width
                )
            } else {
                doc.pages[index].elements[i].frame = VectorRect(
                    x: f.y,
                    y: oldW - f.x - f.width,
                    width: f.height,
                    height: f.width
                )
            }
        }
        doc.revision &+= 1
    }

    // MARK: - Element Operations

    @discardableResult
    public static func addElement(_ element: VectorElement, toPage pageIndex: Int, in doc: inout VectorDocument) -> UUID {
        guard doc.pages.indices.contains(pageIndex) else { return element.id }
        doc.pages[pageIndex].elements.append(element)
        doc.revision &+= 1
        return element.id
    }

    public static func updateElement(
        id: UUID,
        onPage pageIndex: Int,
        in doc: inout VectorDocument,
        mutate: (inout VectorElement) -> Void
    ) {
        guard doc.pages.indices.contains(pageIndex),
              let idx = doc.pages[pageIndex].elements.firstIndex(where: { $0.id == id }) else { return }
        mutate(&doc.pages[pageIndex].elements[idx])
        doc.revision &+= 1
    }

    public static func deleteElements(ids: Set<UUID>, onPage pageIndex: Int, in doc: inout VectorDocument) {
        guard doc.pages.indices.contains(pageIndex), !ids.isEmpty else { return }
        for el in doc.pages[pageIndex].elements where ids.contains(el.id) && !el.locked {
            if case .text(let payload) = el.kind, payload.isPDFExtracted, let origRect = payload.originalPDFRect {
                doc.pages[pageIndex].redactedPDFRects.append(origRect)
            }
        }
        doc.pages[pageIndex].elements.removeAll { ids.contains($0.id) && !$0.locked }
        doc.revision &+= 1
    }

    public static func duplicateElements(ids: Set<UUID>, onPage pageIndex: Int, in doc: inout VectorDocument) -> Set<UUID> {
        guard doc.pages.indices.contains(pageIndex), !ids.isEmpty else { return [] }
        var newIDs: Set<UUID> = []
        for el in doc.pages[pageIndex].elements where ids.contains(el.id) {
            var copy = el
            copy.id = UUID()
            copy.frame = el.frame.offsetBy(dx: 16, dy: 16)
            if case .text(var t) = copy.kind {
                t.isPDFExtracted = false
                t.originalPDFRect = nil
                t.originalPDFText = nil
                copy.kind = .text(t)
            }
            doc.pages[pageIndex].elements.append(copy)
            newIDs.insert(copy.id)
        }
        if !newIDs.isEmpty {
            doc.revision &+= 1
        }
        return newIDs
    }

    public static func moveElements(
        ids: Set<UUID>,
        by delta: VectorPoint,
        onPage pageIndex: Int,
        in doc: inout VectorDocument
    ) {
        guard doc.pages.indices.contains(pageIndex), !ids.isEmpty else { return }
        for i in doc.pages[pageIndex].elements.indices {
            if ids.contains(doc.pages[pageIndex].elements[i].id) && !doc.pages[pageIndex].elements[i].locked {
                doc.pages[pageIndex].elements[i].frame = doc.pages[pageIndex].elements[i].frame.offsetBy(dx: delta.x, dy: delta.y)
            }
        }
        doc.revision &+= 1
    }

    public static func bringToFront(ids: Set<UUID>, onPage pageIndex: Int, in doc: inout VectorDocument) {
        guard doc.pages.indices.contains(pageIndex), !ids.isEmpty else { return }
        let remaining = doc.pages[pageIndex].elements.filter { !ids.contains($0.id) }
        let moving = doc.pages[pageIndex].elements.filter { ids.contains($0.id) }
        doc.pages[pageIndex].elements = remaining + moving
        doc.revision &+= 1
    }

    public static func sendToBack(ids: Set<UUID>, onPage pageIndex: Int, in doc: inout VectorDocument) {
        guard doc.pages.indices.contains(pageIndex), !ids.isEmpty else { return }
        let moving = doc.pages[pageIndex].elements.filter { ids.contains($0.id) }
        let remaining = doc.pages[pageIndex].elements.filter { !ids.contains($0.id) }
        doc.pages[pageIndex].elements = moving + remaining
        doc.revision &+= 1
    }

    // MARK: - High-Level Factories (Signature, Text, Stamp, Shape)

    public static func makeSignatureElement(
        preset: SignaturePreset,
        at center: VectorPoint,
        includeDate: Bool = true
    ) -> VectorElement {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        let dateStr = (includeDate && preset.assetData == nil) ? df.string(from: Date()) : nil
        let width: Double
        let height: Double
        if let data = preset.assetData {
            let aspect = AssetImageCodec.aspectRatio(for: data, ext: preset.assetExtension)
            if aspect >= 1.0 {
                width = 185.0
                height = max(36.0, round(width / aspect))
            } else {
                height = 110.0
                width = max(42.0, round(height * aspect))
            }
        } else {
            width = 190.0
            height = 74.0
        }
        let rect = VectorRect(
            x: max(12, center.x - width * 0.5),
            y: max(12, center.y - height * 0.5),
            width: width,
            height: height
        )
        return VectorElement(
            name: "\(L("Signature", "Signature")) \(preset.signerName)",
            kind: .signature(SignaturePayload(
                signerName: preset.signerName,
                dateLabel: dateStr,
                caption: preset.assetData == nil ? preset.caption : nil,
                strokes: preset.strokes,
                assetData: preset.assetData,
                assetExtension: preset.assetExtension,
                removeWhiteBackground: preset.removeWhiteBackground
            )),
            frame: rect,
            style: VectorStyle(strokeColorHex: preset.colorHex, fillColorHex: nil, strokeWidth: 2.2, opacity: 1.0)
        )
    }

    public static func makeFreehandSignatureElement(
        pageStrokes: [[VectorPoint]],
        signerName: String = "",
        colorHex: String = "#1E3A8A"
    ) -> VectorElement {
        let smoothed = pageStrokes.map { StrokeSmoother.smooth($0, iterations: 2) }
        let (bounds, norm) = StrokeSmoother.normalizeStrokes(smoothed)
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        let trimmedSigner = signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let elemName = trimmedSigner.isEmpty ? L("Signature", "Signature") : "\(L("Signature", "Signature")) \(trimmedSigner)"
        return VectorElement(
            name: elemName,
            kind: .signature(SignaturePayload(
                signerName: trimmedSigner,
                dateLabel: df.string(from: Date()),
                caption: nil,
                strokes: norm
            )),
            frame: VectorRect(
                x: bounds.x,
                y: bounds.y,
                width: max(90, bounds.width),
                height: max(42, bounds.height)
            ),
            style: VectorStyle(strokeColorHex: colorHex, fillColorHex: nil, strokeWidth: 2.2, opacity: 1.0)
        )
    }

    public static func makeTextElement(
        text: String = L("Nouveau texte", "New text"),
        at origin: VectorPoint,
        fontSize: Double = 16.0,
        colorHex: String = "#111317",
        isBold: Bool = false
    ) -> VectorElement {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let maxChars = max(8, lines.map(\.count).max() ?? 12)
        let estWidth = max(90.0, Double(maxChars) * fontSize * 0.58)
        let estHeight = max(24.0, Double(max(1, lines.count)) * fontSize * 1.38)
        return VectorElement(
            name: L("Bloc de texte", "Text Block"),
            kind: .text(TextPayload(
                text: text,
                fontFamily: "Helvetica Neue",
                fontSize: fontSize,
                isBold: isBold
            )),
            frame: VectorRect(x: origin.x, y: origin.y, width: estWidth, height: estHeight),
            style: VectorStyle(strokeColorHex: nil, fillColorHex: colorHex, strokeWidth: 0, opacity: 1.0)
        )
    }

    public static func makeStampElement(
        kind: VectorStampKind,
        at center: VectorPoint
    ) -> VectorElement {
        let width = 176.0
        let height = 52.0
        let payload = StampPayload(stampKind: kind)
        return VectorElement(
            name: payload.title,
            kind: .stamp(payload),
            frame: VectorRect(
                x: max(12, center.x - width * 0.5),
                y: max(12, center.y - height * 0.5),
                width: width,
                height: height
            ),
            rotationDegrees: -4.0,
            style: VectorStyle(
                strokeColorHex: kind.defaultColorHex,
                fillColorHex: kind.defaultColorHex,
                strokeWidth: 2.2,
                opacity: 0.94
            )
        )
    }

    public static func makeCustomStampElement(
        preset: StampPreset,
        at center: VectorPoint,
        rotationDegrees: Double = -4.0
    ) -> VectorElement {
        let aspect = AssetImageCodec.aspectRatio(for: preset.assetData, ext: preset.assetExtension)
        let width: Double
        let height: Double
        if aspect >= 1.0 {
            width = 165.0
            height = max(44.0, round(width / aspect))
        } else {
            height = 140.0
            width = max(44.0, round(height * aspect))
        }
        let payload = StampPayload(
            stampKind: .approved,
            title: preset.title,
            subtitle: "",
            assetData: preset.assetData,
            assetExtension: preset.assetExtension,
            removeWhiteBackground: preset.removeWhiteBackground
        )
        return VectorElement(
            name: preset.title,
            kind: .stamp(payload),
            frame: VectorRect(
                x: max(12, center.x - width * 0.5),
                y: max(12, center.y - height * 0.5),
                width: width,
                height: height
            ),
            rotationDegrees: rotationDegrees,
            style: VectorStyle(
                strokeColorHex: "#1E3A8A",
                fillColorHex: nil,
                strokeWidth: 0,
                opacity: 0.96
            )
        )
    }
}

/// Undo/Redo history store with single write path (`perform`, G35).
public struct VectorDocumentHistory: Sendable {
    public private(set) var undoStack: [VectorDocument] = []
    public private(set) var redoStack: [VectorDocument] = []
    public let maxDepth: Int

    public init(maxDepth: Int = 60) {
        self.maxDepth = maxDepth
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func record(_ current: VectorDocument) {
        undoStack.append(current)
        if undoStack.count > maxDepth {
            undoStack.removeFirst(undoStack.count - maxDepth)
        }
        redoStack.removeAll()
    }

    public mutating func undo(current: VectorDocument) -> VectorDocument? {
        guard let prev = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return prev
    }

    public mutating func redo(current: VectorDocument) -> VectorDocument? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    public mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
