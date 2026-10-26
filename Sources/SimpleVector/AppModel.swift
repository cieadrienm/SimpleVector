import AppKit
import Foundation
import Observation
import SimpleVectorCore
import UniformTypeIdentifiers

enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case select
    case text
    case signature
    case pen
    case rectangle
    case ellipse
    case arrow
    case stamp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: return L("Sélection", "Select")
        case .text: return L("Texte", "Text")
        case .signature: return L("Signature", "Sign")
        case .pen: return L("Tracé", "Draw")
        case .rectangle: return L("Cadre", "Box")
        case .ellipse: return L("Ellipse", "Ellipse")
        case .arrow: return L("Flèche", "Arrow")
        case .stamp: return L("Tampon", "Stamp")
        }
    }

    var shortcutKey: String {
        switch self {
        case .select: return "V"
        case .text: return "T"
        case .signature: return "S"
        case .pen: return "P"
        case .rectangle: return "R"
        case .ellipse: return "O"
        case .arrow: return "L"
        case .stamp: return "K"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .text: return "character.cursor.ibeam"
        case .signature: return "signature"
        case .pen: return "pencil.tip"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .stamp: return "seal"
        }
    }

    var helpText: String {
        switch self {
        case .select: return L("Sélectionner, déplacer, redimensionner ou éditer un bloc (V)", "Select, move, resize, or edit a block (V)")
        case .text: return L("Éditer un texte PDF existant ou ajouter un bloc de texte (T)", "Edit existing PDF text or add a new text block (T)")
        case .signature: return L("Dessiner une signature manuscrite ou apposer sa signature (S)", "Draw a handwritten signature or stamp a saved signature (S)")
        case .pen: return L("Dessiner un tracé vectoriel libre lissé (P)", "Draw a smooth freehand vector path (P)")
        case .rectangle: return L("Tracer un rectangle ou cadre vectoriel (R)", "Draw a vector rectangle or box (R)")
        case .ellipse: return L("Tracer un cercle ou une ellipse (O)", "Draw a circle or ellipse (O)")
        case .arrow: return L("Tracer une ligne ou flèche de cote (L)", "Draw a line or dimension arrow (L)")
        case .stamp: return L("Apposer un tampon (« BON POUR ACCORD », « SIGNÉ »…) (K)", "Place an approval or stage stamp (K)")
        }
    }
}

enum CanvasDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case singlePage
    case multiPageContinuous
    case multiPageGrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .singlePage: return L("Page", "Page")
        case .multiPageContinuous: return L("Continu", "Scroll")
        case .multiPageGrid: return L("Planche", "Grid")
        }
    }

    var symbol: String {
        switch self {
        case .singlePage: return "doc.text"
        case .multiPageContinuous: return "rectangle.grid.1x2"
        case .multiPageGrid: return "square.grid.2x2"
        }
    }

    var shortcutLabel: String {
        switch self {
        case .singlePage: return "⌘1"
        case .multiPageContinuous: return "⌘2"
        case .multiPageGrid: return "⌘3"
        }
    }
}

/// UI state model for SimpleVector (panels, tools, viewport zoom/pan, ProMotion camera transitions, sheets).
@Observable
@MainActor
final class AppModel {
    struct AlertItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private static let defaultsPrefix = "net.cieadrienm.simplevector."
    private static let recentPathsKey = "net.cieadrienm.simplevector.recentPaths"
    private let persistEnabled: Bool

    let controller: VectorController
    let updater: SimpleUpdater
    var recentURLs: [URL] = []

    var language: AppLanguage {
        didSet { Localization.current = language }
    }

    var activeTool: EditorTool = .select
    var displayMode: CanvasDisplayMode = .singlePage
    var showSidebar: Bool = true
    var showInspector: Bool = true
    var showPDFTextBoxes: Bool = true
    var showPageGrid: Bool = false

    // Viewport camera state (zoom & pan)
    var zoomScale: CGFloat = 1.0
    var panOffset: CGSize = .zero
    private var cameraAnimationTask: Task<Void, Never>? = nil

    // Inline text editing state on canvas
    var editingTextElementID: UUID? = nil
    var searchFocusRequest: Int = 0

    // Modal sheets
    var showExportSheet: Bool = false
    var exportFormat: ExportFormat = .pdf
    var showNewPageSheet: Bool = false
    var showOSCGuide: Bool = false
    var showShortcuts: Bool = false
    var showHelp: Bool = false
    var showAbout: Bool = false
    var showUpdater: Bool = false
    var alert: AlertItem? = nil
    var flashMessage: String? = nil

    private var keyMonitor: Any? = nil

    init(startServices: Bool = true, persistEnabled: Bool = true) {
        self.persistEnabled = persistEnabled
        self.language = Localization.current
        self.controller = VectorController(startServices: startServices, persistEnabled: persistEnabled)
        self.updater = SimpleUpdater(
            appName: "SimpleVector",
            bundleID: "net.cieadrienm.simplevector",
            githubRepo: "cieadrienm/SimpleVector",
            currentVersion: AppVersion.current.version,
            startAutoCheck: startServices
        )

        if persistEnabled {
            loadRecentURLs()
        }

        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "-showPDFTextBoxes"), idx + 1 < args.count {
            self.showPDFTextBoxes = (args[idx + 1] != "0" && args[idx + 1].lowercased() != "false")
        }

        if startServices {
            installKeyboardShortcutMonitor()
        }
    }

    var hasOpenSheet: Bool {
        showExportSheet || showNewPageSheet || showOSCGuide || showShortcuts || showHelp || showAbout || showUpdater
    }

    func toggleInspector() {
        showInspector.toggle()
    }

    func flash(_ msg: String) {
        flashMessage = msg
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            if self?.flashMessage == msg {
                self?.flashMessage = nil
            }
        }
    }

    // MARK: - 60–120 Hz ProMotion Camera Transitions (`Z` & `⇧Z` / `F`, G42 & G58)

    func resetViewAnimated() {
        animateViewport(toZoom: 1.0, pan: .zero, duration: 0.22)
        flash(L("Vue réinitialisée (100 %)", "View reset (100%)"))
    }

    func fitSelectionOrPageAnimated(in paneSize: CGSize = CGSize(width: 820, height: 680)) {
        if let selected = controller.primarySelectedElement {
            let page = controller.currentPage
            let relX = (selected.frame.midX / max(1, page.width)) - 0.5
            let relY = (selected.frame.midY / max(1, page.height)) - 0.5
            let targetZoom: CGFloat = min(2.6, max(1.25, CGFloat(min(page.width / max(40, selected.frame.width), page.height / max(40, selected.frame.height)) * 0.45)))
            let sheetW = min(paneSize.width * 0.75, paneSize.height * 0.75 * CGFloat(page.width / max(1, page.height)))
            let sheetH = sheetW * CGFloat(page.height / max(1, page.width))
            let targetPan = CGSize(
                width: -CGFloat(relX) * sheetW * targetZoom,
                height: -CGFloat(relY) * sheetH * targetZoom
            )
            animateViewport(toZoom: targetZoom, pan: targetPan, duration: 0.24)
            flash(L("Cadré sur la sélection (\(Format.percent(targetZoom)))", "Framed selection (\(Format.percent(targetZoom)))"))
        } else {
            animateViewport(toZoom: 1.0, pan: .zero, duration: 0.22)
            flash(L("Cadré sur la page entière", "Fitted full page"))
        }
    }

    func stepZoom(factor: CGFloat) {
        let target = min(6.0, max(0.25, zoomScale * factor))
        animateViewport(toZoom: target, pan: panOffset, duration: 0.16)
    }

    private func animateViewport(toZoom targetZoom: CGFloat, pan targetPan: CGSize, duration: TimeInterval) {
        cameraAnimationTask?.cancel()
        let startZoom = zoomScale
        let startPan = panOffset
        if abs(startZoom - targetZoom) < 0.002 && hypot(startPan.width - targetPan.width, startPan.height - targetPan.height) < 0.5 {
            zoomScale = targetZoom
            panOffset = targetPan
            return
        }
        let fps = max(60, NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60)
        let frameInterval = 1.0 / Double(fps)
        let startTime = CACurrentMediaTime()

        cameraAnimationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = CACurrentMediaTime() - startTime
                let rawT = min(1.0, max(0.0, elapsed / duration))
                // Smooth cubic ease-out
                let inv = 1.0 - rawT
                let eased = CGFloat(1.0 - inv * inv * inv)
                self.zoomScale = startZoom + (targetZoom - startZoom) * eased
                self.panOffset = CGSize(
                    width: startPan.width + (targetPan.width - startPan.width) * eased,
                    height: startPan.height + (targetPan.height - startPan.height) * eased
                )
                if rawT >= 1.0 {
                    self.zoomScale = targetZoom
                    self.panOffset = targetPan
                    break
                }
                try? await Task.sleep(for: .seconds(frameInterval))
            }
        }
    }

    // MARK: - Open / Save Panels

    func openDocumentPanel() {
        let panel = NSOpenPanel()
        panel.title = L("Ouvrir un document SVG ou PDF", "Open SVG or PDF Document")
        panel.allowedContentTypes = [.pdf, .svg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func open(_ url: URL) {
        do {
            try controller.openFile(at: url)
            editingTextElementID = nil
            recordRecentURL(url)
            resetViewAnimated()
        } catch {
            alert = AlertItem(
                title: L("Impossible d'ouvrir le fichier", "Could not open file"),
                message: error.localizedDescription
            )
        }
    }

    func saveDocumentDirectOrPanel() {
        if let existingURL = controller.document.fileURL {
            do {
                try controller.saveFile(to: existingURL)
                recordRecentURL(existingURL)
                flash(L("Enregistré dans \(existingURL.lastPathComponent)", "Saved to \(existingURL.lastPathComponent)"))
                return
            } catch {
                alert = AlertItem(
                    title: L("Erreur d'enregistrement", "Save Error"),
                    message: error.localizedDescription
                )
            }
        }
        saveDocumentPanel(defaultFormat: controller.document.sourceFormat == .pdf ? .pdf : .svg)
    }

    func saveDocumentPanel(defaultFormat: ExportFormat) {
        let panel = NSSavePanel()
        panel.title = L("Enregistrer le document (\(defaultFormat.rawValue.uppercased()))", "Save Document (\(defaultFormat.rawValue.uppercased()))")
        panel.canCreateDirectories = true
        let baseName = (controller.document.title as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName).\(defaultFormat.rawValue)"
        switch defaultFormat {
        case .pdf: panel.allowedContentTypes = [.pdf]
        case .svg: panel.allowedContentTypes = [.svg]
        case .png: panel.allowedContentTypes = [.png]
        }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try controller.saveFile(to: url, format: defaultFormat)
                if defaultFormat == .pdf || defaultFormat == .svg {
                    recordRecentURL(url)
                }
                showExportSheet = false
                flash(L("Enregistré : \(url.lastPathComponent)", "Saved: \(url.lastPathComponent)"))
            } catch {
                alert = AlertItem(
                    title: L("Erreur d'enregistrement", "Save Error"),
                    message: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Recent Files (`Fichier > Ouvrir récent`)

    func loadRecentURLs() {
        let savedPaths = UserDefaults.standard.stringArray(forKey: Self.recentPathsKey) ?? []
        var urls = savedPaths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        for url in NSDocumentController.shared.recentDocumentURLs where FileManager.default.fileExists(atPath: url.path) {
            if !urls.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                urls.append(url)
            }
        }
        recentURLs = Array(urls.prefix(12))
    }

    func recordRecentURL(_ url: URL) {
        let standardized = url.standardizedFileURL
        recentURLs.removeAll { $0.standardizedFileURL == standardized }
        recentURLs.insert(standardized, at: 0)
        if recentURLs.count > 12 {
            recentURLs = Array(recentURLs.prefix(12))
        }
        if persistEnabled {
            UserDefaults.standard.set(recentURLs.map(\.path), forKey: Self.recentPathsKey)
            NSDocumentController.shared.noteNewRecentDocumentURL(standardized)
        }
    }

    func clearRecentURLs() {
        recentURLs.removeAll()
        if persistEnabled {
            UserDefaults.standard.removeObject(forKey: Self.recentPathsKey)
            NSDocumentController.shared.clearRecentDocuments(nil)
        }
    }

    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Single-Key Canvas Shortcut Monitor (`Z`, `⇧Z`, `F`, Tools `V/T/S/P/R/O/L/K`, G58)

    private func installKeyboardShortcutMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.hasOpenSheet || self.editingTextElementID != nil {
                return event
            }
            if event.window?.firstResponder is NSText {
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
                return event
            }
            guard let chars = event.charactersIgnoringModifiers?.lowercased(), let ch = chars.first else {
                return event
            }

            switch ch {
            case "z":
                if flags.contains(.shift) {
                    self.fitSelectionOrPageAnimated()
                } else {
                    self.resetViewAnimated()
                }
                return nil
            case "f":
                self.fitSelectionOrPageAnimated()
                return nil
            case "v":
                self.activeTool = .select
                return nil
            case "t":
                self.activeTool = .text
                return nil
            case "s":
                self.activeTool = .signature
                return nil
            case "p":
                self.activeTool = .pen
                return nil
            case "r":
                self.activeTool = .rectangle
                return nil
            case "o":
                self.activeTool = .ellipse
                return nil
            case "l":
                self.activeTool = .arrow
                return nil
            case "k":
                self.activeTool = .stamp
                return nil
            case "[":
                if self.controller.currentPageIndex > 0 {
                    self.controller.currentPageIndex -= 1
                }
                return nil
            case "]":
                if self.controller.currentPageIndex + 1 < self.controller.document.pages.count {
                    self.controller.currentPageIndex += 1
                }
                return nil
            case "\u{7f}", "\u{08}":
                if !self.controller.selection.isEmpty {
                    self.controller.deleteSelectedElements()
                    return nil
                }
                return event
            case "\u{1b}":
                self.controller.selection.removeAll()
                self.activeTool = .select
                return nil
            default:
                return event
            }
        }
    }
}
