import AppKit
import Darwin
import Foundation
import Observation
import SimpleVectorCore
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf = "pdf"
    case svg = "svg"
    case png = "png"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdf: return L("Document PDF vectoriel multipage (.pdf)", "Multi-Page Vector PDF (.pdf)")
        case .svg: return L("Graphique vectoriel SVG 1.1 (.svg)", "SVG 1.1 Vector Graphic (.svg)")
        case .png: return L("Image haute définition PNG (.png)", "High-DPI PNG Image (.png)")
        }
    }

    var detail: String {
        switch self {
        case .pdf:
            return L("Conserve le flux PDF d'origine, applique les textes édités, signatures et formes en pur vectoriel.", "Preserves original PDF vector streams, applies edited text blocks, signatures, and vector shapes.")
        case .svg:
            return L("Export SVG standard compatible Illustrator, Inkscape, navigateurs web et SimpleVectorizer.", "Standard SVG export compatible with Illustrator, Inkscape, web browsers, and SimpleVectorizer.")
        case .png:
            return L("Rendu bitmap Retina (2×) de la page active pour partage rapide ou fiche régie.", "Retina (2×) bitmap render of the active page for quick sharing or stage sheets.")
        }
    }
}

private final class LockBox<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ newValue: T) { lock.lock(); value = newValue; lock.unlock() }
}

/// Core controller owning the `VectorDocument`, undo/redo history, signature library, OSC server, and HTTP `/v1` API (G31).
@Observable
@MainActor
final class VectorController {
    var document: VectorDocument
    var history = VectorDocumentHistory()
    var currentPageIndex: Int = 0
    var selection: Set<UUID> = []
    var signatures: [SignaturePreset]
    var activeSignaturePresetID: UUID
    var customStamps: [StampPreset] = []
    var activeCustomStampPresetID: UUID? = nil
    var activeStampKind: VectorStampKind = .approved
    var statusMessage: String = ""
    var lastError: String? = nil
    var searchQuery: String = ""

    private let persistEnabled: Bool
    private static let signaturesDefaultsKey = "net.cieadrienm.simplevector.customSignatures"
    private static let legacySignaturesDefaultsKey = "net.cieadrienm.simplevector.signatures"

    static var signaturesDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("SimpleVector/Signatures", isDirectory: true)
    }

    static var stampsDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("SimpleVector/Stamps", isDirectory: true)
    }

    private(set) var oscServer: OSCUDPServer?
    private var httpListenFD: Int32 = -1
    private(set) var httpPort: UInt16 = kSimpleVectorDefaultHTTPPort

    init(startServices: Bool = true, persistEnabled: Bool = true) {
        self.persistEnabled = persistEnabled
        let size = PageFormatPreset.a4Portrait.sizePoints
        let initialPage = VectorPage(title: "Page 1", width: size.width, height: size.height, backgroundColorHex: "#FFFFFF")
        let initialDoc = VectorDocument(
            title: L("Sans titre", "Untitled"),
            sourceFormat: .svg,
            fileURL: nil,
            pages: [initialPage]
        )
        self.document = initialDoc
        if persistEnabled {
            UserDefaults.standard.removeObject(forKey: Self.legacySignaturesDefaultsKey)
        }
        let loadedSignatures: [SignaturePreset]
        if persistEnabled,
           let data = UserDefaults.standard.data(forKey: Self.signaturesDefaultsKey),
           let decoded = try? JSONDecoder().decode([SignaturePreset].self, from: data) {
            loadedSignatures = decoded
        } else {
            loadedSignatures = []
        }
        self.signatures = loadedSignatures
        self.activeSignaturePresetID = loadedSignatures.first?.id ?? UUID()
        self.reloadSignaturesAndStampsFromDisk()
        self.statusMessage = L(
            "Prêt · Ouvrir un document PDF ou SVG (⌘O) ou dessiner sur la page A4",
            "Ready · Open a PDF or SVG document (⌘O) or draw on the A4 page"
        )

        if startServices {
            startOSCServer()
            startHTTPServer()
        }
    }

    var currentPage: VectorPage {
        get {
            guard document.pages.indices.contains(currentPageIndex) else {
                return document.pages[0]
            }
            return document.pages[currentPageIndex]
        }
        set {
            guard document.pages.indices.contains(currentPageIndex) else { return }
            document.pages[currentPageIndex] = newValue
        }
    }

    var selectedElements: [VectorElement] {
        currentPage.elements.filter { selection.contains($0.id) }
    }

    var primarySelectedElement: VectorElement? {
        currentPage.elements.last { selection.contains($0.id) }
    }

    var activeSignaturePreset: SignaturePreset {
        signatures.first { $0.id == activeSignaturePresetID }
            ?? signatures.first
            ?? SignaturePreset(
                title: L("Signature", "Signature"),
                signerName: "",
                caption: "",
                colorHex: "#1E3A8A",
                strokes: SignaturePreset.calligraphicStrokes(seed: 1)
            )
    }

    var filteredElementsOnCurrentPage: [VectorElement] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return currentPage.elements }
        return currentPage.elements.filter { el in
            if el.name.lowercased().contains(q) || el.displayTitle.lowercased().contains(q) {
                return true
            }
            if case .text(let t) = el.kind, t.text.lowercased().contains(q) {
                return true
            }
            return false
        }
    }

    // MARK: - Single Write Path (`perform`, G35)

    func perform(_ actionName: String = "", mutate: (inout VectorDocument) -> Void) {
        history.record(document)
        var nextDoc = document
        mutate(&nextDoc)
        document = nextDoc
        if !document.pages.indices.contains(currentPageIndex) {
            currentPageIndex = max(0, min(currentPageIndex, document.pages.count - 1))
        }
        lastError = nil
        if !actionName.isEmpty {
            statusMessage = actionName
        }
    }

    func undo() {
        guard let prev = history.undo(current: document) else { return }
        document = prev
        if currentPageIndex >= document.pages.count {
            currentPageIndex = max(0, document.pages.count - 1)
        }
        statusMessage = L("Annulé", "Undone")
    }

    func redo() {
        guard let next = history.redo(current: document) else { return }
        document = next
        if currentPageIndex >= document.pages.count {
            currentPageIndex = max(0, document.pages.count - 1)
        }
        statusMessage = L("Rétabli", "Redone")
    }

    // MARK: - Document Loading & Saving

    func createNewDocument(preset: PageFormatPreset = .a4Portrait) {
        let size = preset.sizePoints
        let page = VectorPage(title: "Page 1", width: size.width, height: size.height, backgroundColorHex: "#FFFFFF")
        document = VectorDocument(
            title: L("Sans titre", "Untitled"),
            sourceFormat: .svg,
            fileURL: nil,
            pages: [page]
        )
        history.clear()
        currentPageIndex = 0
        selection.removeAll()
        lastError = nil
        statusMessage = L("Nouveau document \(preset.rawValue) créé", "New \(preset.rawValue) document created")
    }

    func openFile(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let baseTitle = url.deletingPathExtension().lastPathComponent

        let imported: VectorDocument
        if ext == "pdf" || Self.looksLikePDF(data) {
            imported = try PDFCodec.importPDF(data: data, title: baseTitle, fileURL: url)
        } else {
            imported = try SVGCodec.importSVG(data: data, title: baseTitle, fileURL: url)
        }
        document = imported
        history.clear()
        currentPageIndex = 0
        selection.removeAll()
        lastError = nil
        statusMessage = L(
            "Ouvert : \(url.lastPathComponent) (\(imported.pages.count) page\(imported.pages.count > 1 ? "s" : ""), \(imported.totalElementsCount) éléments)",
            "Opened: \(url.lastPathComponent) (\(imported.pages.count) page\(imported.pages.count > 1 ? "s" : ""), \(imported.totalElementsCount) elements)"
        )
    }

    func saveFile(to url: URL, format: ExportFormat? = nil) throws {
        let ext = url.pathExtension.lowercased()
        let resolvedFormat: ExportFormat
        if let format {
            resolvedFormat = format
        } else if ext == "pdf" {
            resolvedFormat = .pdf
        } else if ext == "png" {
            resolvedFormat = .png
        } else {
            resolvedFormat = .svg
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        switch resolvedFormat {
        case .pdf:
            let data = try PDFCodec.exportPDF(document: document)
            try data.write(to: url, options: .atomic)
            document.fileURL = url
            document.sourceFormat = .pdf
        case .svg:
            let svgText = SVGCodec.exportSVG(document: document)
            try Data(svgText.utf8).write(to: url, options: .atomic)
            document.fileURL = url
            document.sourceFormat = .svg
        case .png:
            guard let pngData = PDFCodec.renderPagePNG(page: currentPage, scale: 2.0) else {
                throw NSError(domain: "SimpleVector", code: 10, userInfo: [
                    NSLocalizedDescriptionKey: L("Impossible de rendre l'image PNG.", "Failed to render PNG image.")
                ])
            }
            try pngData.write(to: url, options: .atomic)
        }

        lastError = nil
        statusMessage = L(
            "Enregistré : \(url.lastPathComponent) (\(resolvedFormat.rawValue.uppercased()))",
            "Saved: \(url.lastPathComponent) (\(resolvedFormat.rawValue.uppercased()))"
        )
    }

    private static func looksLikePDF(_ data: Data) -> Bool {
        guard data.count >= 5 else { return false }
        let header = String(decoding: data.prefix(5), as: UTF8.self)
        return header == "%PDF-"
    }

    // MARK: - High-Level Editing Helpers

    func addBlankPage(preset: PageFormatPreset = .a4Portrait) {
        perform(L("Page ajoutée", "Page added")) { doc in
            currentPageIndex = VectorOperations.addPage(to: &doc, after: currentPageIndex, preset: preset)
        }
        selection.removeAll()
    }

    func duplicateCurrentPage() {
        perform(L("Page dupliquée", "Page duplicated")) { doc in
            currentPageIndex = VectorOperations.duplicatePage(in: &doc, at: currentPageIndex)
        }
        selection.removeAll()
    }

    func deleteCurrentPage() {
        guard document.pages.count > 1 else { return }
        perform(L("Page supprimée", "Page deleted")) { doc in
            currentPageIndex = VectorOperations.deletePage(in: &doc, at: currentPageIndex)
        }
        selection.removeAll()
    }

    func moveCurrentPage(offset: Int) {
        let dest = currentPageIndex + offset
        guard document.pages.indices.contains(dest) else { return }
        perform(L("Page déplacée", "Page moved")) { doc in
            currentPageIndex = VectorOperations.movePage(in: &doc, from: currentPageIndex, to: dest)
        }
    }

    func rotateCurrentPage(clockwise: Bool = true) {
        perform(L("Page pivotée de 90°", "Page rotated 90°")) { doc in
            VectorOperations.rotatePage(in: &doc, at: currentPageIndex, clockwise: clockwise)
        }
    }

    func stampActiveSignature(at point: VectorPoint? = nil) {
        let pt = point ?? VectorPoint(x: currentPage.width * 0.68, y: currentPage.height * 0.82)
        let includeDate = (activeSignaturePreset.assetData == nil)
        let el = VectorOperations.makeSignatureElement(preset: activeSignaturePreset, at: pt, includeDate: includeDate)
        perform(L("Signature apposée (\(activeSignaturePreset.title))", "Signature placed (\(activeSignaturePreset.title))")) { doc in
            VectorOperations.addElement(el, toPage: currentPageIndex, in: &doc)
        }
        selection = [el.id]
    }

    func stampApprovalBadge(kind: VectorStampKind? = nil, at point: VectorPoint? = nil) {
        if kind == nil,
           let customID = activeCustomStampPresetID,
           let customPreset = customStamps.first(where: { $0.id == customID }) {
            stampCustomStamp(customPreset, at: point)
            return
        }
        let k = kind ?? activeStampKind
        let pt = point ?? VectorPoint(x: currentPage.width * 0.30, y: currentPage.height * 0.82)
        let el = VectorOperations.makeStampElement(kind: k, at: pt)
        perform(L("Tampon « \(k.defaultTitle) » ajouté", "Stamp \"\(k.defaultTitle)\" added")) { doc in
            VectorOperations.addElement(el, toPage: currentPageIndex, in: &doc)
        }
        selection = [el.id]
    }

    func stampCustomStamp(_ preset: StampPreset, at point: VectorPoint? = nil) {
        let pt = point ?? VectorPoint(x: currentPage.width * 0.30, y: currentPage.height * 0.82)
        let el = VectorOperations.makeCustomStampElement(preset: preset, at: pt)
        perform(L("Tampon « \(preset.title) » ajouté", "Stamp \"\(preset.title)\" added")) { doc in
            VectorOperations.addElement(el, toPage: currentPageIndex, in: &doc)
        }
        selection = [el.id]
    }

    // MARK: - Signatures & Stamps Folders (`~/Library/Application Support/SimpleVector/{Signatures,Stamps}`)

    func reloadSignaturesAndStampsFromDisk() {
        let fm = FileManager.default
        let sigDir = Self.signaturesDirectoryURL
        let stDir = Self.stampsDirectoryURL
        try? fm.createDirectory(at: sigDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: stDir, withIntermediateDirectories: true)

        // Keep non-disk signatures (defaults + user-saved calligraphic signatures)
        let baseSigs = signatures.filter { $0.fileURL == nil }
        var diskSigs: [SignaturePreset] = []
        if let urls = try? fm.contentsOfDirectory(at: sigDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for url in urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                let ext = url.pathExtension.lowercased()
                guard AssetImageCodec.supportedExtensions.contains(ext),
                      let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
                let title = url.deletingPathExtension().lastPathComponent
                let deterministicID = Self.deterministicUUID(for: "sig:" + url.lastPathComponent)
                diskSigs.append(
                    SignaturePreset(
                        id: deterministicID,
                        title: title,
                        signerName: title,
                        caption: ext.uppercased(),
                        colorHex: "#1E3A8A",
                        strokes: [],
                        assetData: data,
                        assetExtension: ext,
                        removeWhiteBackground: true,
                        fileURL: url
                    )
                )
            }
        }
        signatures = diskSigs + baseSigs
        if !signatures.contains(where: { $0.id == activeSignaturePresetID }), let first = signatures.first {
            activeSignaturePresetID = first.id
        }

        var loadedStamps: [StampPreset] = []
        if let urls = try? fm.contentsOfDirectory(at: stDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for url in urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                let ext = url.pathExtension.lowercased()
                guard AssetImageCodec.supportedExtensions.contains(ext),
                      let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
                let title = url.deletingPathExtension().lastPathComponent
                let deterministicID = Self.deterministicUUID(for: "stamp:" + url.lastPathComponent)
                loadedStamps.append(
                    StampPreset(
                        id: deterministicID,
                        title: title,
                        assetData: data,
                        assetExtension: ext,
                        removeWhiteBackground: true,
                        fileURL: url
                    )
                )
            }
        }
        customStamps = loadedStamps
        if let activeID = activeCustomStampPresetID, !customStamps.contains(where: { $0.id == activeID }) {
            activeCustomStampPresetID = customStamps.first?.id
        }
    }

    func openSignaturesFolderInFinder() {
        let dir = Self.signaturesDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func openStampsFolderInFinder() {
        let dir = Self.stampsDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func importSignatureFileInteractive() {
        let panel = NSOpenPanel()
        panel.title = L("Importer une signature (PDF, PNG, JPG, SVG…)", "Import a Signature (PDF, PNG, JPG, SVG…)")
        panel.allowedContentTypes = [.pdf, .image, .svg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let dir = Self.signaturesDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lastImportedName: String? = nil
        for url in panel.urls {
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
            lastImportedName = url.lastPathComponent
        }
        reloadSignaturesAndStampsFromDisk()
        if let name = lastImportedName {
            let id = Self.deterministicUUID(for: "sig:" + name)
            if signatures.contains(where: { $0.id == id }) {
                activeSignaturePresetID = id
            }
            statusMessage = L("Signature importée : \(name)", "Signature imported: \(name)")
        }
    }

    func importStampFileInteractive() {
        let panel = NSOpenPanel()
        panel.title = L("Importer un tampon (PDF, PNG, JPG, SVG…)", "Import a Stamp (PDF, PNG, JPG, SVG…)")
        panel.allowedContentTypes = [.pdf, .image, .svg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let dir = Self.stampsDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lastImportedName: String? = nil
        for url in panel.urls {
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
            lastImportedName = url.lastPathComponent
        }
        reloadSignaturesAndStampsFromDisk()
        if let name = lastImportedName {
            let id = Self.deterministicUUID(for: "stamp:" + name)
            if let preset = customStamps.first(where: { $0.id == id }) {
                activeCustomStampPresetID = preset.id
                stampCustomStamp(preset)
            }
        }
    }

    private static func deterministicUUID(for key: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let utf8 = Array(key.utf8)
        for (i, b) in utf8.enumerated() {
            bytes[i % 16] = bytes[i % 16] &+ b &* UInt8((i % 7) + 1)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    func addTextBlock(text: String = L("Texte éditable", "Editable text"), at point: VectorPoint? = nil) {
        let pt = point ?? VectorPoint(x: currentPage.width * 0.25, y: currentPage.height * 0.35)
        let el = VectorOperations.makeTextElement(text: text, at: pt, fontSize: 15.0)
        perform(L("Bloc de texte ajouté", "Text block added")) { doc in
            VectorOperations.addElement(el, toPage: currentPageIndex, in: &doc)
        }
        selection = [el.id]
    }

    func addShape(_ shapeType: VectorShapeType, at rect: VectorRect? = nil) {
        let r = rect ?? VectorRect(
            x: currentPage.width * 0.32,
            y: currentPage.height * 0.36,
            width: 140,
            height: 84
        )
        let style: VectorStyle
        if shapeType == .line || shapeType == .arrow {
            style = VectorStyle(strokeColorHex: "#D97706", fillColorHex: nil, strokeWidth: 2.2)
        } else {
            style = VectorStyle(strokeColorHex: "#1E3A8A", fillColorHex: "#DBEAFE", strokeWidth: 1.8)
        }
        let el = VectorElement(
            name: shapeType.label,
            kind: .shape(ShapePayload(shapeType: shapeType, cornerRadius: shapeType == .roundedRectangle ? 8 : 0, endArrow: shapeType == .arrow)),
            frame: r,
            style: style
        )
        perform(L("\(shapeType.label) ajouté", "\(shapeType.label) added")) { doc in
            VectorOperations.addElement(el, toPage: currentPageIndex, in: &doc)
        }
        selection = [el.id]
    }

    func saveCustomSignature(from element: VectorElement) {
        guard case .signature(let payload) = element.kind else { return }
        let title = payload.signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L("Signature manuscrite", "Handwritten Signature")
            : payload.signerName
        let preset = SignaturePreset(
            title: title,
            signerName: payload.signerName,
            caption: payload.caption ?? "",
            colorHex: element.style.strokeColorHex ?? "#1E3A8A",
            strokes: payload.strokes
        )
        signatures.append(preset)
        activeSignaturePresetID = preset.id
        let nonDisk = signatures.filter { $0.fileURL == nil }
        if persistEnabled, let data = try? JSONEncoder().encode(nonDisk) {
            UserDefaults.standard.set(data, forKey: Self.signaturesDefaultsKey)
        }
        statusMessage = L("Signature enregistrée dans la bibliothèque", "Signature saved to library")
    }

    func deleteSelectedElements() {
        guard !selection.isEmpty else { return }
        let ids = selection
        perform(L("Sélection supprimée", "Selection deleted")) { doc in
            VectorOperations.deleteElements(ids: ids, onPage: currentPageIndex, in: &doc)
        }
        selection.removeAll()
    }

    func duplicateSelectedElements() {
        guard !selection.isEmpty else { return }
        let ids = selection
        var newIDs: Set<UUID> = []
        perform(L("Sélection dupliquée", "Selection duplicated")) { doc in
            newIDs = VectorOperations.duplicateElements(ids: ids, onPage: currentPageIndex, in: &doc)
        }
        selection = newIDs
    }

    // MARK: - OSC UDP Server (`:9160`)

    func startOSCServer(port: UInt16? = nil) {
        oscServer?.stop()
        let envPort = ProcessInfo.processInfo.environment["SIMPLEVECTOR_OSC_IN_PORT"].flatMap(UInt16.init)
        let targetPort = port ?? envPort ?? kSimpleVectorDefaultOSCInPort
        let server = OSCUDPServer(port: targetPort) { [weak self] msg in
            Task { @MainActor [weak self] in
                self?.handleOSCMessage(msg)
            }
        }
        if server.start() {
            self.oscServer = server
        }
    }

    func handleOSCMessage(_ message: OSCCodec.Message) {
        let addr = message.address.lowercased()
        let firstArg = message.arguments.first

        switch addr {
        case "/simplevector/page":
            if let p = firstArg?.intValue {
                let idx = max(0, min(document.pages.count - 1, p - 1))
                currentPageIndex = idx
                statusMessage = "OSC · Page \(idx + 1)/\(document.pages.count)"
            }
        case "/simplevector/page/next":
            if currentPageIndex + 1 < document.pages.count {
                currentPageIndex += 1
            }
        case "/simplevector/page/prev":
            if currentPageIndex > 0 {
                currentPageIndex -= 1
            }
        case "/simplevector/sign":
            if let signer = firstArg?.stringValue, !signer.isEmpty {
                let preset = SignaturePreset(
                    title: signer,
                    signerName: signer,
                    caption: "",
                    colorHex: "#1E3A8A",
                    strokes: SignaturePreset.calligraphicStrokes(seed: signer.count)
                )
                let el = VectorOperations.makeSignatureElement(
                    preset: preset,
                    at: VectorPoint(x: currentPage.width * 0.68, y: currentPage.height * 0.82)
                )
                perform("OSC · Signature \(signer)") { doc in
                    VectorOperations.addElement(el, toPage: currentPageIndex, in: &doc)
                }
            } else {
                stampActiveSignature()
            }
        case "/simplevector/stamp":
            let raw = firstArg?.stringValue ?? "approved"
            let kind = VectorStampKind(rawValue: raw) ?? .approved
            stampApprovalBadge(kind: kind)
        case "/simplevector/open":
            if let path = firstArg?.stringValue, !path.isEmpty {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                try? openFile(at: url)
            }
        case "/simplevector/export":
            if let path = firstArg?.stringValue, !path.isEmpty {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                try? saveFile(to: url)
            }
        case "/simplevector/undo":
            undo()
        case "/simplevector/redo":
            redo()
        default:
            break
        }
    }

    // MARK: - Local HTTP JSON Server (`127.0.0.1:17960/v1`)

    func startHTTPServer(port: UInt16? = nil) {
        stopHTTPServer()
        let envPort = ProcessInfo.processInfo.environment["SIMPLEVECTOR_API_PORT"].flatMap(UInt16.init)
        let targetPort = port ?? envPort ?? kSimpleVectorDefaultHTTPPort

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = targetPort.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0, Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            return
        }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(fd, $0, &len)
            }
        }
        self.httpListenFD = fd
        self.httpPort = UInt16(bigEndian: bound.sin_port)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                var caddr = sockaddr_in()
                var clen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let cfd = withUnsafeMutablePointer(to: &caddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.accept(fd, $0, &clen)
                    }
                }
                if cfd < 0 { break }
                var one: Int32 = 1
                setsockopt(cfd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                self?.handleHTTPConnection(cfd)
            }
        }
    }

    func stopHTTPServer() {
        if httpListenFD >= 0 {
            Darwin.close(httpListenFD)
            httpListenFD = -1
        }
    }

    func stopAllServices() {
        oscServer?.stop()
        stopHTTPServer()
    }

    nonisolated private func handleHTTPConnection(_ fd: Int32) {
        defer { Darwin.close(fd) }
        var buf = [UInt8](repeating: 0, count: 32768)
        let n = Darwin.recv(fd, &buf, buf.count, 0)
        guard n > 0 else { return }
        let requestText = String(decoding: buf[0..<n], as: UTF8.self)
        let firstLine = requestText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let tokens = firstLine.split(separator: " ").map(String.init)
        guard tokens.count >= 2 else { return }
        let method = tokens[0].uppercased()
        let rawTarget = tokens[1]
        let pathParts = rawTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(pathParts.first ?? "")
        let query = pathParts.count > 1 ? String(pathParts[1]) : ""

        var jsonArgs: [String: Any] = [:]
        if let bodyRange = requestText.range(of: "\r\n\r\n") {
            let bodyStr = String(requestText[bodyRange.upperBound...])
            if let data = bodyStr.data(using: .utf8),
               let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                jsonArgs = parsed
            }
        }
        let args = jsonArgs

        let sem = DispatchSemaphore(value: 0)
        let box = LockBox<Data>(Data("{\"ok\":true}".utf8))
        let statusBox = LockBox<Int>(200)
        let contentTypeBox = LockBox<String>("application/json; charset=utf-8")

        Task { @MainActor [weak self] in
            defer { sem.signal() }
            guard let self else { return }
            self.dispatchHTTPRequest(
                method: method,
                path: path,
                query: query,
                args: args,
                box: box,
                statusBox: statusBox,
                contentTypeBox: contentTypeBox
            )
        }
        _ = sem.wait(timeout: .now() + 8.0)

        let body = box.get()
        let code = statusBox.get()
        let ctype = contentTypeBox.get()
        let header = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Bad Request")\r\nContent-Type: \(ctype)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        _ = response.withUnsafeBytes { ptr in
            Darwin.send(fd, ptr.baseAddress!, response.count, 0)
        }
    }

    private func dispatchHTTPRequest(
        method: String,
        path: String,
        query: String,
        args: [String: Any],
        box: LockBox<Data>,
        statusBox: LockBox<Int>,
        contentTypeBox: LockBox<String>
    ) {
        func writeJSON(_ dict: [String: Any]) {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                box.set(data)
            }
        }

        switch (method, path) {
        case ("GET", "/v1/state"), ("GET", "/v1/status"):
            writeJSON([
                "app": "SimpleVector",
                "version": AppVersion.current.version,
                "title": document.title,
                "sourceFormat": document.sourceFormat.rawValue,
                "pageCount": document.pages.count,
                "currentPageIndex": currentPageIndex + 1,
                "totalElementsCount": document.totalElementsCount,
                "pdfTextElementCount": document.pdfTextElementCount,
                "modifiedPDFTextCount": document.modifiedPDFTextCount,
                "signatureCount": document.signatureCount,
                "canUndo": history.canUndo,
                "canRedo": history.canRedo,
                "oscInPort": Int(oscServer?.port ?? kSimpleVectorDefaultOSCInPort),
                "apiPort": Int(httpPort),
                "statusMessage": statusMessage,
            ])

        case ("GET", "/v1/pages"):
            let pagesJSON: [[String: Any]] = document.pages.enumerated().map { idx, p in
                [
                    "page": idx + 1,
                    "title": p.title,
                    "width": p.width,
                    "height": p.height,
                    "hasPDFStream": p.pdfPageData != nil,
                    "redactedRectCount": p.redactedPDFRects.count,
                    "elements": p.elements.map { el -> [String: Any] in
                        var dict: [String: Any] = [
                            "id": el.id.uuidString,
                            "name": el.name,
                            "type": el.typeBadge,
                            "x": el.frame.x,
                            "y": el.frame.y,
                            "width": el.frame.width,
                            "height": el.frame.height,
                            "visible": el.visible,
                            "locked": el.locked,
                        ]
                        if case .text(let t) = el.kind {
                            dict["text"] = t.text
                            dict["isPDFExtracted"] = t.isPDFExtracted
                            dict["modified"] = el.hasModifiedPDFText
                        } else if case .signature(let sig) = el.kind {
                            dict["signerName"] = sig.signerName
                            dict["dateLabel"] = sig.dateLabel ?? ""
                        }
                        return dict
                    },
                ]
            }
            writeJSON(["pages": pagesJSON])

        case ("GET", "/v1/help"):
            writeJSON([
                "app": "SimpleVector",
                "httpEndpoints": [
                    "GET /v1/state",
                    "GET /v1/pages",
                    "GET /v1/help",
                    "GET /v1/svg",
                    "GET /v1/snapshot.png?view=single|multipage|grid",
                    "POST /v1/open {\"path\":\"/path/to/file.pdf\"}",
                    "POST /v1/text {\"page\":1,\"match\":\"Statut\",\"text\":\"Statut : VALIDÉ\"}",
                    "POST /v1/sign {\"page\":1,\"signer\":\"Direction Technique\",\"x\":420,\"y\":695,\"stamp\":\"approved\"}",
                    "POST /v1/page {\"format\":\"A4 Portrait\",\"duplicate\":false}",
                    "POST /v1/export {\"outputPath\":\"/tmp/out.pdf\",\"format\":\"pdf|svg|png\"}",
                ],
                "oscAddresses": [
                    "/simplevector/page <1..N>",
                    "/simplevector/page/next",
                    "/simplevector/page/prev",
                    "/simplevector/sign <signerName>",
                    "/simplevector/stamp <approved|signed|stagePlot|confidential|draft>",
                    "/simplevector/open <filepath>",
                    "/simplevector/export <filepath>",
                    "/simplevector/undo",
                    "/simplevector/redo",
                ],
            ])

        case ("GET", "/v1/svg"):
            let svg = SVGCodec.exportSVG(document: document)
            contentTypeBox.set("image/svg+xml; charset=utf-8")
            box.set(Data(svg.utf8))

        case ("GET", "/v1/snapshot.png"):
            let snapModel = AppModel(startServices: false, persistEnabled: false)
            snapModel.controller.document = self.document
            snapModel.controller.currentPageIndex = self.currentPageIndex
            if query.contains("view=multipage") {
                snapModel.displayMode = .multiPageContinuous
            } else if query.contains("view=grid") {
                snapModel.displayMode = .multiPageGrid
            } else {
                snapModel.displayMode = .singlePage
            }
            if let png = Snapshot.renderOffscreenPNG(model: snapModel) {
                contentTypeBox.set("image/png")
                box.set(png)
            } else {
                statusBox.set(500)
                writeJSON(["ok": false, "error": "snapshot failed"])
            }

        case ("POST", "/v1/open"):
            if let path = args["path"] as? String, !path.isEmpty {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                do {
                    try openFile(at: url)
                    writeJSON(["ok": true, "title": document.title, "pages": document.pages.count])
                } catch {
                    statusBox.set(400)
                    writeJSON(["ok": false, "error": error.localizedDescription])
                }
            } else {
                statusBox.set(400)
                writeJSON(["ok": false, "error": "missing 'path'"])
            }

        case ("POST", "/v1/text"):
            guard let newText = args["text"] as? String else {
                statusBox.set(400)
                writeJSON(["ok": false, "error": "missing 'text'"])
                return
            }
            let pageIdx = ((args["page"] as? Int).map { $0 - 1 }) ?? currentPageIndex
            guard document.pages.indices.contains(pageIdx) else {
                statusBox.set(400)
                writeJSON(["ok": false, "error": "invalid page"])
                return
            }
            if let match = args["match"] as? String, !match.isEmpty {
                var matchedID: UUID? = nil
                for el in document.pages[pageIdx].elements {
                    if case .text(let t) = el.kind, t.text.localizedCaseInsensitiveContains(match) {
                        matchedID = el.id
                        break
                    }
                }
                if let id = matchedID {
                    perform("HTTP · Texte modifié") { doc in
                        VectorOperations.updateElement(id: id, onPage: pageIdx, in: &doc) { el in
                            if case .text(var t) = el.kind {
                                t.text = newText
                                el.kind = .text(t)
                            }
                        }
                    }
                    writeJSON(["ok": true, "updatedElementID": id.uuidString])
                    return
                }
            }
            let x = (args["x"] as? Double) ?? 72.0
            let y = (args["y"] as? Double) ?? 120.0
            let fontSize = (args["fontSize"] as? Double) ?? 15.0
            let el = VectorOperations.makeTextElement(text: newText, at: VectorPoint(x: x, y: y), fontSize: fontSize)
            perform("HTTP · Texte ajouté") { doc in
                VectorOperations.addElement(el, toPage: pageIdx, in: &doc)
            }
            writeJSON(["ok": true, "createdElementID": el.id.uuidString])

        case ("POST", "/v1/sign"):
            let pageIdx = ((args["page"] as? Int).map { $0 - 1 }) ?? currentPageIndex
            guard document.pages.indices.contains(pageIdx) else {
                statusBox.set(400)
                writeJSON(["ok": false, "error": "invalid page"])
                return
            }
            let signer = (args["signer"] as? String) ?? activeSignaturePreset.signerName
            let x = (args["x"] as? Double) ?? (document.pages[pageIdx].width * 0.68)
            let y = (args["y"] as? Double) ?? (document.pages[pageIdx].height * 0.82)
            let preset = SignaturePreset(
                title: signer.isEmpty ? L("Signature", "Signature") : signer,
                signerName: signer,
                caption: "",
                colorHex: "#1E3A8A",
                strokes: SignaturePreset.calligraphicStrokes(seed: max(1, signer.count))
            )
            let sigEl = VectorOperations.makeSignatureElement(preset: preset, at: VectorPoint(x: x, y: y), includeDate: true)
            perform("HTTP · Signature \(signer)") { doc in
                VectorOperations.addElement(sigEl, toPage: pageIdx, in: &doc)
                if let stampRaw = args["stamp"] as? String, let kind = VectorStampKind(rawValue: stampRaw) {
                    let stEl = VectorOperations.makeStampElement(kind: kind, at: VectorPoint(x: max(100, x - 210), y: y))
                    VectorOperations.addElement(stEl, toPage: pageIdx, in: &doc)
                }
            }
            writeJSON(["ok": true, "signatureID": sigEl.id.uuidString, "page": pageIdx + 1])

        case ("POST", "/v1/page"):
            if (args["duplicate"] as? Bool) == true {
                duplicateCurrentPage()
            } else {
                let fmtRaw = (args["format"] as? String) ?? PageFormatPreset.a4Portrait.rawValue
                let preset = PageFormatPreset(rawValue: fmtRaw) ?? .a4Portrait
                addBlankPage(preset: preset)
            }
            writeJSON(["ok": true, "pageCount": document.pages.count, "currentPage": currentPageIndex + 1])

        case ("POST", "/v1/export"):
            guard let outputPath = args["outputPath"] as? String, !outputPath.isEmpty else {
                statusBox.set(400)
                writeJSON(["ok": false, "error": "missing 'outputPath'"])
                return
            }
            let fmt = (args["format"] as? String).flatMap { ExportFormat(rawValue: $0.lowercased()) }
            let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            do {
                try saveFile(to: url, format: fmt)
                writeJSON(["ok": true, "outputPath": url.path])
            } catch {
                statusBox.set(400)
                writeJSON(["ok": false, "error": error.localizedDescription])
            }

        default:
            statusBox.set(400)
            writeJSON(["ok": false, "error": "unknown endpoint \(method) \(path)"])
        }
    }
}
