import AppKit
import SimpleVectorCore
import SwiftUI

@main
struct SimpleVectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("SimpleVector") {
            ContentView(model: appDelegate.model)
                .frame(minWidth: 980, minHeight: 600)
                .onAppear { appDelegate.didAppear() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1380, height: 820)
        .commands { appCommands(model: appDelegate.model) }

        Settings {
            PreferencesView(model: appDelegate.model)
        }
    }

    @CommandsBuilder
    private func appCommands(model: AppModel) -> some Commands {
        let _ = model.language
        let ctrl = model.controller

        CommandGroup(replacing: .appInfo) {
            Button(L("À propos de SimpleVector", "About SimpleVector")) { model.showAbout = true }
            Button(L("Rechercher des mises à jour…", "Check for Updates…")) {
                model.showUpdater = true
                model.updater.checkForUpdates(silent: false)
            }
        }

        CommandGroup(replacing: .newItem) {
            Button(L("Nouveau document A4 Portrait", "New A4 Portrait Document")) {
                ctrl.createNewDocument(preset: .a4Portrait)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button(L("Ajouter une page vierge", "Add Blank Page")) {
                ctrl.addBlankPage()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button(L("Ouvrir un document SVG ou PDF…", "Open SVG or PDF Document…")) {
                model.openDocumentPanel()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Menu(L("Ouvrir récent", "Open Recent")) {
                if model.recentURLs.isEmpty {
                    Text(L("Aucun élément récent", "No Recent Items"))
                } else {
                    ForEach(model.recentURLs, id: \.path) { url in
                        Button(url.lastPathComponent) {
                            model.open(url)
                        }
                    }
                    Divider()
                    Button(L("Effacer le menu", "Clear Menu")) {
                        model.clearRecentURLs()
                    }
                }
            }

            Divider()

            Button(L("Enregistrer le document…", "Save Document…")) {
                model.saveDocumentDirectOrPanel()
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button(L("Enregistrer sous / Exporter (PDF, SVG, PNG)…", "Save As / Export (PDF, SVG, PNG)…")) {
                model.showExportSheet = true
            }
            .keyboardShortcut("e", modifiers: [.command])
        }

        CommandGroup(replacing: .undoRedo) {
            Button(L("Annuler", "Undo")) { ctrl.undo() }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!ctrl.history.canUndo)
            Button(L("Rétablir", "Redo")) { ctrl.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!ctrl.history.canRedo)
        }

        CommandGroup(replacing: .pasteboard) {
            Button(L("Dupliquer la sélection", "Duplicate Selection")) {
                ctrl.duplicateSelectedElements()
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(ctrl.selection.isEmpty)

            Button(L("Supprimer la sélection", "Delete Selection")) {
                ctrl.deleteSelectedElements()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(ctrl.selection.isEmpty)

            Divider()

            Button(L("Tout sélectionner sur la page", "Select All on Page")) {
                ctrl.selection = Set(ctrl.currentPage.elements.map(\.id))
            }
            .keyboardShortcut("a", modifiers: [.command])

            Button(L("Rechercher un texte / Filtrer les calques", "Search Text / Filter Layers")) {
                model.searchFocusRequest += 1
            }
            .keyboardShortcut("f", modifiers: [.command])
        }

        CommandMenu(L("Édition Vectorielle & PDF", "Vector & PDF Editing")) {
            Button(L("Apposer la signature active (S)", "Place Active Signature (S)")) {
                ctrl.stampActiveSignature()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Menu(L("Apposer un tampon d'approbation (K)", "Place Approval Stamp (K)")) {
                ForEach(VectorStampKind.allCases) { kind in
                    Button(kind.defaultTitle) {
                        ctrl.activeStampKind = kind
                        ctrl.stampApprovalBadge(kind: kind)
                    }
                }
            }

            Button(L("Ajouter un bloc de texte (T)", "Add Text Block (T)")) {
                ctrl.addTextBlock()
            }

            Menu(L("Ajouter une forme ou flèche", "Add Shape or Arrow")) {
                ForEach(VectorShapeType.allCases) { shape in
                    Button(shape.label) {
                        ctrl.addShape(shape)
                    }
                }
            }

            Divider()

            Button(L("Page précédente ([)", "Previous Page ([)")) {
                if ctrl.currentPageIndex > 0 { ctrl.currentPageIndex -= 1 }
            }
            .disabled(ctrl.currentPageIndex <= 0)

            Button(L("Page suivante (])", "Next Page (])")) {
                if ctrl.currentPageIndex + 1 < ctrl.document.pages.count { ctrl.currentPageIndex += 1 }
            }
            .disabled(ctrl.currentPageIndex + 1 >= ctrl.document.pages.count)

            Button(L("Dupliquer la page courante", "Duplicate Current Page")) {
                ctrl.duplicateCurrentPage()
            }

            Button(L("Pivoter la page de 90°", "Rotate Page 90°")) {
                ctrl.rotateCurrentPage(clockwise: true)
            }
        }

        CommandGroup(after: .toolbar) {
            Button(L("Vue Page unique", "Single Page View")) { model.displayMode = .singlePage }
                .keyboardShortcut("1", modifiers: [.command])
            Button(L("Vue Continu multipage", "Multi-Page Continuous View")) { model.displayMode = .multiPageContinuous }
                .keyboardShortcut("2", modifiers: [.command])
            Button(L("Vue Planche multipage", "Multi-Page Grid View")) { model.displayMode = .multiPageGrid }
                .keyboardShortcut("3", modifiers: [.command])

            Divider()

            Button(L("Réinitialiser la vue à 100 % (Z)", "Reset View to 100% (Z)")) {
                model.resetViewAnimated()
            }
            Button(L("Cadrer tout ou la sélection (⇧Z / F)", "Fit Page or Selection (⇧Z / F)")) {
                model.fitSelectionOrPageAnimated()
            }
            Button(L("Zoom avant", "Zoom In")) { model.stepZoom(factor: 1.25) }
                .keyboardShortcut("+", modifiers: [.command])
            Button(L("Zoom arrière", "Zoom Out")) { model.stepZoom(factor: 0.8) }
                .keyboardShortcut("-", modifiers: [.command])

            Divider()

            Button(model.showSidebar ? L("Masquer la barre latérale", "Hide Sidebar") : L("Afficher la barre latérale", "Show Sidebar")) {
                model.showSidebar.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button(model.showInspector ? L("Masquer l'inspecteur", "Hide Inspector") : L("Afficher l'inspecteur", "Show Inspector")) {
                model.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Divider()

            Button(L("Commandes OSC, API HTTP & MCP…", "OSC, HTTP API & MCP Commands…")) {
                model.showOSCGuide = true
            }
        }

        CommandGroup(replacing: .help) {
            Button(L("Aide SimpleVector", "SimpleVector Help")) { model.showHelp = true }
                .keyboardShortcut("?", modifiers: [.command])
            Divider()
            Button(L("Raccourcis clavier", "Keyboard Shortcuts")) { model.showShortcuts = true }
                .keyboardShortcut("/", modifiers: [.command])
            Button(L("Guide OSC, HTTP & MCP", "OSC, HTTP & MCP Guide")) { model.showOSCGuide = true }
            Divider()
            Button(L("Site web Simple Apps (adrien-m.net/software)", "Simple Apps Website (adrien-m.net/software)")) {
                if let url = URL(string: "https://adrien-m.net/software") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var model = AppModel(startServices: !headless, persistEnabled: !headless)
    private var headless = false
    private var didStart = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppVersion.runIfRequested()
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.contains("-h") {
            headless = true
            HeadlessCLI.printHelpAndExit()
        }
        if args.contains("--self-test") {
            headless = true
            SelfTest.runAndExit()
        }
        if let index = args.firstIndex(of: "--info") {
            headless = true
            HeadlessCLI.runInfoAndExit(arguments: Array(args[(index + 1)...]))
        }
        if let index = args.firstIndex(of: "--convert") {
            headless = true
            HeadlessCLI.runConvertAndExit(arguments: Array(args[(index + 1)...]))
        }
        if let index = args.firstIndex(of: "--snapshot") {
            headless = true
            let path = index + 1 < args.count && !args[index + 1].hasPrefix("-") ? args[index + 1] : "/tmp/simplevector.png"
            let view = args.firstIndex(of: "--view").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "single"
            Snapshot.runCLISnapshot(outputPath: path, view: view)
        }
    }

    func didAppear() {
        guard !didStart else { return }
        didStart = true
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let args = Array(CommandLine.arguments.dropFirst())
        var idx = 0
        while idx < args.count {
            let arg = args[idx]
            if arg.hasPrefix("-") {
                idx += 2
                continue
            }
            let url = URL(fileURLWithPath: (arg as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                model.open(url)
                break
            }
            idx += 1
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let first = urls.first {
            model.open(first)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model.controller.stopAllServices()
    }
}
