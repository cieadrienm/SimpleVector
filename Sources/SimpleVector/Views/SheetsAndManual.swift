import AppKit
import SimpleVectorCore
import SwiftUI

// MARK: - Export Sheet

struct ExportSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        let doc = model.controller.document
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Exporter le document vectoriel", "Export Vector Document"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text.swiftUI)

            SectionHeader("Format")
            VStack(spacing: 4) {
                ForEach(ExportFormat.allCases) { format in
                    let active = model.exportFormat == format
                    Button { model.exportFormat = format } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: active ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(active ? Theme.accent.swiftUI : Theme.textFaint.swiftUI)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.text.swiftUI)
                                Text(format.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.textDim.swiftUI)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.laneSelected.swiftUI : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Chip(text: L("\(doc.pages.count) pages", "\(doc.pages.count) pages"), tint: Theme.accent.swiftUI)
                Chip(text: L("\(doc.totalElementsCount) éléments", "\(doc.totalElementsCount) elements"), tint: Theme.tcp.swiftUI)
                if doc.signatureCount > 0 {
                    Chip(text: L("\(doc.signatureCount) signatures", "\(doc.signatureCount) signatures"), tint: Theme.alive.swiftUI)
                }
            }

            HStack {
                Button(L("Annuler", "Cancel")) { model.showExportSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if model.exportFormat == .svg {
                    TextButton(title: L("Copier le code SVG", "Copy SVG Code"), symbol: "doc.on.doc") {
                        let svg = SVGCodec.exportSVG(document: doc)
                        AppModel.copyToPasteboard(svg)
                        model.showExportSheet = false
                        model.flash(L("Code SVG copié dans le presse-papiers", "SVG code copied to clipboard"))
                    }
                }
                TextButton(title: L("Enregistrer…", "Save…"), symbol: "square.and.arrow.down", prominent: true) {
                    model.saveDocumentPanel(defaultFormat: model.exportFormat)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 470)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}

// MARK: - OSC, HTTP & MCP Reference Sheet

struct OSCGuideSheet: View {
    @Bindable var model: AppModel
    let close: () -> Void

    private static var oscExamples: [(String, String, String)] {
        [
            ("/simplevector/page", "1..N", L("Aller à la page n°1..N du document multipage", "Jump to page #1..N of the multi-page document")),
            ("/simplevector/page/next", L("(aucun)", "(none)"), L("Passer à la page suivante", "Go to next page")),
            ("/simplevector/page/prev", L("(aucun)", "(none)"), L("Revenir à la page précédente", "Go to previous page")),
            ("/simplevector/sign", "\"Adrien Mondot\"", L("Apposer une signature calligraphique sur la page active", "Place a calligraphic signature on the active page")),
            ("/simplevector/stamp", "\"approved\"", L("Apposer un tampon (« approved », « signed », « stagePlot »)", "Place an approval or stage stamp")),
            ("/simplevector/open", "\"/chemin/plan.pdf\"", L("Ouvrir un document SVG ou PDF", "Open an SVG or PDF document")),
            ("/simplevector/export", "\"/tmp/sortie.pdf\"", L("Enregistrer en PDF vectoriel multipage, SVG ou PNG", "Export to multi-page vector PDF, SVG, or PNG")),
            ("/simplevector/undo", L("(aucun)", "(none)"), L("Annuler la dernière opération", "Undo last operation")),
        ]
    }

    private static let mcpConfigJSON = """
    {
      "mcpServers": {
        "simplevector": {
          "command": "/Applications/SimpleVector.app/Contents/MacOS/simplevector-mcp"
        }
      }
    }
    """

    var body: some View {
        let ctrl = model.controller
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Pilotage OSC, API HTTP & Serveur MCP — SimpleVector", "OSC, HTTP API & MCP Server — SimpleVector"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text.swiftUI)
                    Text(L("Intégration directe avec OSCScore, Montage, eMotion et agents IA.", "Direct integration with OSCScore, Montage, eMotion, and AI agents."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
                Spacer()
                Chip(text: "OSC UDP :\(ctrl.oscServer?.port ?? kSimpleVectorDefaultOSCInPort)", tint: Theme.osc.swiftUI)
                Chip(text: "HTTP / MCP :\(ctrl.httpPort)", tint: Theme.tcp.swiftUI)
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            SectionHeader(L("Adresses OSC entrantes (UDP :\(ctrl.oscServer?.port ?? kSimpleVectorDefaultOSCInPort))", "Incoming OSC Addresses (UDP :\(ctrl.oscServer?.port ?? kSimpleVectorDefaultOSCInPort))"))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Self.oscExamples, id: \.0) { addr, arg, desc in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(addr)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.osc.swiftUI)
                            .frame(width: 185, alignment: .leading)
                        Text(arg)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.accent.swiftUI)
                            .frame(width: 120, alignment: .leading)
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textDim.swiftUI)
                        Spacer()
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.lane.swiftUI))

            SectionHeader(L("Configuration MCP (simplevector-mcp)", "MCP Configuration (simplevector-mcp)")) {
                TextButton(title: L("Copier JSON", "Copy JSON"), symbol: "doc.on.doc", compact: true) {
                    AppModel.copyToPasteboard(Self.mcpConfigJSON)
                }
            }
            Text(Self.mcpConfigJSON)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.text.swiftUI)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.lane.swiftUI))

            HStack {
                Spacer()
                Button(L("Fermer", "Close"), action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 720)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}

// MARK: - About Sheet (`G60`)

struct AboutSheet: View {
    @Bindable var model: AppModel
    let openHelp: () -> Void
    let close: () -> Void
    @State private var copiedVersion = false

    struct FeatureItem: Identifiable {
        let id = UUID()
        let icon: String
        let tint: NSColor
        let title: String
        let detail: String
    }

    private static var features: [FeatureItem] {
        [
            FeatureItem(
                icon: "doc.text.magnifyingglass",
                tint: Theme.tcp,
                title: L("Édition directe du texte des PDF", "Direct PDF Text Editing"),
                detail: L("Extraction automatique des lignes de texte PDF avec masquage vectoriel propre et remplacement haute précision.", "Automatic extraction of PDF text lines with clean vector masking and high-precision replacement.")
            ),
            FeatureItem(
                icon: "signature",
                tint: Theme.accent,
                title: L("Signatures calligraphiques & Tampons", "Calligraphic Signatures & Stamps"),
                detail: L("Tracé manuscrit lissé en courbes de Bézier, bibliothèque de signatures enregistrées et tampons « BON POUR ACCORD ».", "Freehand strokes smoothed into Bezier curves, saved signature library, and approval stamps.")
            ),
            FeatureItem(
                icon: "rectangle.stack",
                tint: Theme.alive,
                title: L("Mode Multipage SVG & PDF natif", "Native Multi-Page SVG & PDF"),
                detail: L("Navigation par miniatures, vue continue ou planche contact, ajout, duplication, rotation et réorganisation des pages.", "Thumbnail navigation, continuous scroll or contact grid, page insertion, duplication, rotation, and reordering.")
            ),
            FeatureItem(
                icon: "bolt.horizontal.circle",
                tint: Theme.osc,
                title: L("Fluidité 120 Hz, Zéro dépendance & MCP", "120 Hz Fluidity, Zero Dependency & MCP"),
                detail: L("Caches géométriques avec frustum culling, pilotage OSC (:9160), API HTTP (/v1 :17960) et serveur MCP embarqué.", "Geometry caches with frustum culling, OSC control (:9160), HTTP API (/v1 :17960), and embedded MCP server.")
            ),
        ]
    }

    var body: some View {
        let ctrl = model.controller
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                VectorHeroGraphic(active: true, size: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Theme.header.swiftUI)
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("SimpleVector")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.text.swiftUI)
                        Button {
                            AppModel.copyToPasteboard(AppVersion.current.cliLine)
                            copiedVersion = true
                        } label: {
                            Text(copiedVersion ? L("copié", "copied") : AppVersion.current.shortLabel)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.background.swiftUI)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.accent.swiftUI))
                        }
                        .buttonStyle(.plain)
                    }
                    Text(L("Éditeur vectoriel multipage ultra-léger pour ouvrir, modifier le texte, signer et enregistrer les SVG et PDF", "Ultra-lightweight multi-page vector editor to open, edit text, sign, and save SVG and PDF documents"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textDim.swiftUI)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        pill(icon: "doc.richtext", text: "SVG & PDF Multipage", tint: Theme.accent)
                        pill(icon: "waveform.path", text: "OSC UDP :\(ctrl.oscServer?.port ?? kSimpleVectorDefaultOSCInPort)", tint: Theme.osc)
                        pill(icon: "network", text: "HTTP / MCP :\(ctrl.httpPort)", tint: Theme.tcp)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(L("POINTS FORTS", "HIGHLIGHTS"))
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.textFaint.swiftUI)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Self.features) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(item.tint.swiftUI)
                                .frame(width: 24, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6).fill(item.tint.swiftUI.opacity(0.14)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Theme.text.swiftUI)
                                Text(item.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.textDim.swiftUI)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    }
                }
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Adrien Mondot ·")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.text.swiftUI)
                        Button {
                            if let url = URL(string: "https://adrien-m.net") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("cie Adrien M")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .underline()
                                Text("(adrien-m.net)")
                                    .font(.system(size: 10.5, design: .monospaced))
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 9.5))
                            }
                            .foregroundStyle(Theme.accent.swiftUI)
                        }
                        .buttonStyle(.plain)
                        .help("https://adrien-m.net")
                    }
                    Text(L("Licence publique générale GNU (GPL v3+). Zéro dépendance externe, aucune télémétrie.", "GNU General Public License (GPL v3+). Zero external dependencies, zero telemetry."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textFaint.swiftUI)
                }
                Spacer()
                Button {
                    close()
                    DispatchQueue.main.async {
                        model.showUpdater = true
                        model.updater.checkForUpdates(silent: false)
                    }
                } label: {
                    Label(
                        model.updater.availableRelease.map { L("↑ MAJ v\($0.version)", "↑ Update v\($0.version)") }
                            ?? L("Mises à jour…", "Check for Updates…"),
                        systemImage: "arrow.down.circle"
                    )
                    .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.updater.availableRelease != nil ? Theme.accent.swiftUI : Theme.textDim.swiftUI)

                Button { close(); openHelp() } label: {
                    Label(L("Guide (⌘?)", "Guide (⌘?)"), systemImage: "book.closed").font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim.swiftUI)
                Button("OK", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 650)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private func pill(icon: String, text: String, tint: NSColor) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint.swiftUI)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.swiftUI.opacity(0.12)))
    }
}

// MARK: - Shortcuts Sheet (`G61`)

struct ShortcutsSheet: View {
    let close: () -> Void

    static var groups: [(String, [(String, String)])] {
        [
            (L("Outils d'édition vectorielle", "Vector Editing Tools"), [
                ("V", L("Outil Sélection / Déplacement / Redimensionnement", "Select / Move / Resize tool")),
                ("T", L("Outil Texte (éditer un texte PDF ou ajouter un texte)", "Text tool (edit PDF text or add text)")),
                ("S", L("Outil Signature (signer à main levée ou apposer)", "Signature tool (freehand or stamp)")),
                ("P", L("Outil Tracé vectoriel libre lissé", "Smooth freehand vector path tool")),
                ("R / O", L("Tracer un Rectangle (R) ou une Ellipse (O)", "Draw Rectangle (R) or Ellipse (O)")),
                ("L / K", L("Tracer une Flèche (L) ou apposer un Tampon (K)", "Draw Arrow (L) or place Stamp (K)")),
                ("⌫", L("Supprimer les éléments sélectionnés (ou masquer le texte PDF)", "Delete selected elements (or redact PDF text)")),
            ]),
            (L("Documents & Multipage", "Documents & Multi-Page"), [
                ("⌘O / ⌘S", L("Ouvrir un SVG/PDF · Enregistrer le document", "Open SVG/PDF · Save document")),
                ("⌘E", L("Exporter en PDF multipage, SVG ou PNG", "Export to multi-page PDF, SVG, or PNG")),
                ("⇧⌘N", L("Ajouter une nouvelle page au document", "Add a new page to document")),
                ("[ / ]", L("Aller à la page précédente / suivante", "Previous / Next page")),
                ("⌘Z / ⇧⌘Z", L("Annuler / Rétablir l'opération", "Undo / Redo operation")),
                ("⌘D", L("Dupliquer la sélection", "Duplicate selection")),
            ]),
            (L("Cadrage & Panneaux", "Framing & Panels"), [
                ("Z", L("Réinitialiser la vue à 100 % (transition 120 Hz)", "Reset view to 100% (120 Hz transition)")),
                ("⇧Z / F", L("Cadrer toute la page ou la sélection active", "Fit entire page or active selection")),
                ("⌘1 / ⌘2 / ⌘3", L("Vue Page unique / Continu multipage / Planche", "Single page / Multi-page scroll / Grid view")),
                ("⌥⌘S / ⌥⌘I", L("Afficher ou masquer la barre latérale / l'inspecteur", "Show or hide sidebar / inspector")),
                ("⌘F", L("Rechercher un texte ou filtrer les calques", "Search text or filter layers")),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("Raccourcis clavier — SimpleVector", "Keyboard Shortcuts — SimpleVector"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Spacer()
                Button(L("Fermer", "Close"), action: close).keyboardShortcut(.defaultAction)
            }
            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)
            HStack(alignment: .top, spacing: 16) {
                ForEach(Self.groups, id: \.0) { groupTitle, items in
                    VStack(alignment: .leading, spacing: 7) {
                        SectionHeader(groupTitle)
                        ForEach(items, id: \.0) { key, label in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(key)
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.accent.swiftUI)
                                    .frame(width: 86, alignment: .leading)
                                Text(label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textDim.swiftUI)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(width: 860)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Multi-Section Help Manual Sheet (`G62`)

struct HelpManualSheet: View {
    let openShortcuts: () -> Void
    let close: () -> Void

    enum SectionID: String, CaseIterable, Identifiable {
        case quickStart
        case pdfTextEditing
        case signaturesAndStamps
        case multipageAndSVG
        case oscAndMCP

        var id: String { rawValue }

        var title: String {
            switch self {
            case .quickStart: return L("Démarrage rapide", "Quick Start")
            case .pdfTextEditing: return L("Édition du texte PDF", "PDF Text Editing")
            case .signaturesAndStamps: return L("Signatures & Tampons", "Signatures & Stamps")
            case .multipageAndSVG: return L("Multipage, SVG & PDF", "Multi-Page, SVG & PDF")
            case .oscAndMCP: return L("OSC, API HTTP & MCP", "OSC, HTTP API & MCP")
            }
        }

        var icon: String {
            switch self {
            case .quickStart: return "play.circle"
            case .pdfTextEditing: return "doc.text.magnifyingglass"
            case .signaturesAndStamps: return "signature"
            case .multipageAndSVG: return "rectangle.stack"
            case .oscAndMCP: return "antenna.radiowaves.left.and.right"
            }
        }
    }

    @State private var selectedSection: SectionID = .quickStart

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "book.closed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent.swiftUI)
                Text(L("Guide d’utilisation — SimpleVector", "User Guide — SimpleVector"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Spacer()
                Text(AppVersion.current.shortLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.textFaint.swiftUI)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.header.swiftUI)

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 204)
                Rectangle().fill(Theme.separator.swiftUI).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sectionContent(selectedSection)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Theme.panel.swiftUI)
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            HStack {
                Button {
                    close()
                    openShortcuts()
                } label: {
                    Label(L("Raccourcis clavier (⌘/)", "Keyboard Shortcuts (⌘/)"), systemImage: "command")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textDim.swiftUI)

                Spacer()

                Button("OK", action: close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.header.swiftUI)
        }
        .frame(width: 760, height: 520)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SectionID.allCases) { sec in
                let active = selectedSection == sec
                Button {
                    selectedSection = sec
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: sec.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(active ? Theme.accent.swiftUI : Theme.textDim.swiftUI)
                            .frame(width: 18)
                        Text(sec.title)
                            .font(.system(size: 12, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? Theme.text.swiftUI : Theme.textDim.swiftUI)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(active ? Theme.laneSelected.swiftUI : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .background(Theme.header.swiftUI)
    }

    @ViewBuilder
    private func sectionContent(_ sec: SectionID) -> some View {
        switch sec {
        case .quickStart:
            sectionHeader(
                title: L("Démarrage rapide", "Quick Start"),
                subtitle: L("Ouvrir, modifier, signer et enregistrer un SVG ou un PDF multipage en quelques secondes.", "Open, edit, sign, and save a multi-page SVG or PDF in seconds.")
            )
            numberedStep(
                number: "1",
                title: L("Ouvrir ou glisser-déposer un fichier SVG ou PDF (⌘O)", "Open or drag-and-drop an SVG or PDF file (⌘O)"),
                body: L("SimpleVector conserve le rendu vectoriel natif de chaque page PDF tout en extrayant automatiquement les lignes de texte pour les rendre éditables.", "SimpleVector preserves the native vector stream of each PDF page while automatically extracting text lines so they can be edited directly.")
            )
            numberedStep(
                number: "2",
                title: L("Éditer le texte, signer et annoter (V, T, S, R, L, K)", "Edit text, sign, and annotate (V, T, S, R, L, K)"),
                body: L("Cliquer sur n'importe quelle ligne du PDF pour corriger son texte, cliquer sur « Signer » (S) pour apposer une signature calligraphique ou tracer à main levée, et ajouter des flèches, cadres ou tampons.", "Click any line in the PDF to edit its text, click \"Sign\" (S) to stamp a calligraphic signature or draw freehand, and add arrows, boxes, or stamps.")
            )
            numberedStep(
                number: "3",
                title: L("Enregistrer en PDF multipage, SVG ou PNG (⌘S / ⌘E)", "Save as Multi-Page PDF, SVG, or PNG (⌘S / ⌘E)"),
                body: L("L'enregistrement PDF produit un PDF vectoriel multipage propre intégrant toutes les modifications de texte, signatures et formes.", "Saving to PDF produces a clean multi-page vector PDF embedding all text edits, signatures, and vector shapes.")
            )

        case .pdfTextEditing:
            sectionHeader(
                title: L("Édition directe du texte des PDF", "Direct PDF Text Editing"),
                subtitle: L("Modifier un contrat, une fiche technique ou un plan de feu PDF sans perdre la mise en page.", "Update a contract, technical rider, or stage plot PDF without losing its layout.")
            )
            bulletList([
                (L("Détection automatique des lignes de texte PDF", "Automatic PDF text line detection"), L("À l'ouverture d'un PDF contenant du texte, chaque ligne est convertie en bloc vectoriel sélectionnable (encadré pointillé cyan).", "When opening a PDF containing text, each line becomes a selectable vector block (dashed cyan frame).")),
                (L("Masquage vectoriel automatique à l'édition", "Automatic vector masking when edited"), L("Dès qu'une ligne PDF est modifiée, déplacée ou supprimée, SimpleVector masque proprement le glyphe d'origine sur le flux PDF et trace le nouveau texte vectoriel à la même position.", "As soon as a PDF line is edited, moved, or deleted, SimpleVector cleanly masks the original glyph on the PDF stream and renders the new vector text in place.")),
                (L("Restauration en 1 clic", "1-click restore"), L("Le bouton « Origine PDF » de la barre flottante restaure à tout moment le texte et la position d'origine du PDF.", "The \"Original PDF\" button in the floating bar restores the original PDF text and position at any time.")),
            ])

        case .signaturesAndStamps:
            sectionHeader(
                title: L("Signatures calligraphiques & Tampons", "Calligraphic Signatures & Stamps"),
                subtitle: L("Signer des contrats, fiches de validation et plans de régie en un clic.", "Sign contracts, approval sheets, and stage plots in one click.")
            )
            bulletList([
                (L("Bibliothèque de signatures enregistrées", "Saved signature library"), L("Choisir une signature dans l'inspecteur droit (« Adrien Mondot », « Paraphe AM », « Visa Régie ») et cliquer sur « Signer » dans la barre haute.", "Choose a signature in the right inspector and click \"Sign\" in the top bar.")),
                (L("Tracé manuscrit lissé au trackpad ou à la souris (S)", "Smooth freehand signing with trackpad or mouse (S)"), L("Sélectionner l'outil Signature (S) et signer directement sur la feuille : le tracé est lissé en courbes souples et peut être enregistré dans la bibliothèque.", "Select the Signature tool (S) and sign directly on the sheet: the stroke is smoothed and can be saved to the library.")),
                (L("Tampons vectoriels prêts à l'emploi (K)", "Ready-to-use vector stamps (K)"), L("Apposer les cartouches « BON POUR ACCORD », « SIGNÉ & VALIDÉ », « RÉGIE PLATEAU » ou « CONFIDENTIEL » avec date automatique.", "Stamp \"APPROVED\", \"SIGNED & VERIFIED\", \"STAGE CONTROL\", or \"CONFIDENTIAL\" badges with automatic date.")),
            ])

        case .multipageAndSVG:
            sectionHeader(
                title: L("Mode Multipage, SVG & PDF", "Multi-Page Mode, SVG & PDF"),
                subtitle: L("Gérer des documents d'une ou plusieurs pages en SVG comme en PDF.", "Manage single-page or multi-page documents across SVG and PDF.")
            )
            bulletList([
                (L("Vues Page (⌘1), Continu multipage (⌘2) et Planche (⌘3)", "Single Page (⌘1), Multi-Page Scroll (⌘2), and Grid (⌘3)"), L("Basculer instantanément entre l'édition de précision sur une page et la vue d'ensemble de toutes les pages du document.", "Switch instantly between precision single-page editing and full multi-page overview.")),
                (L("Ajout, duplication, rotation 90° et réorganisation", "Insert, duplicate, rotate 90°, and reorder"), L("La barre latérale gauche permet d'ajouter des pages (A4 Portrait/Paysage, 16:9), de les dupliquer, de les pivoter ou de changer leur ordre.", "The left sidebar lets you add pages, duplicate them, rotate them, or change their order.")),
            ])

        case .oscAndMCP:
            sectionHeader(
                title: L("OSC, API HTTP & Serveur MCP", "OSC, HTTP API & MCP Server"),
                subtitle: L("Automatisation locale sur les ports de la famille Simple (x = 6).", "Local automation on the Simple family ports (x = 6).")
            )
            bulletList([
                (L("Serveur OSC UDP (:9160 par défaut)", "OSC UDP Server (:9160 by default)"), "/simplevector/page <1..N>, /simplevector/sign <nom>, /simplevector/stamp <kind>, /simplevector/open <path>, /simplevector/export <path>."),
                (L("API HTTP JSON locale (127.0.0.1:17960/v1)", "Local JSON HTTP API (127.0.0.1:17960/v1)"), L("Expose GET /v1/state, GET /v1/pages, GET /v1/help, GET /v1/svg, GET /v1/snapshot.png, POST /v1/open, POST /v1/text, POST /v1/sign, POST /v1/page, POST /v1/export.", "Exposes GET /v1/state, GET /v1/pages, GET /v1/help, GET /v1/svg, GET /v1/snapshot.png, POST /v1/open, POST /v1/text, POST /v1/sign, POST /v1/page, POST /v1/export.")),
                (L("Serveur MCP embarqué (simplevector-mcp)", "Embedded MCP Server (simplevector-mcp)"), L("Expose 9 outils MCP sur stdio pour inspecter, modifier le texte d'un PDF, signer et exporter.", "Exposes 9 MCP tools over stdio to inspect, edit PDF text, sign, and export.")),
            ])
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text.swiftUI)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim.swiftUI)
            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1).padding(.top, 6)
        }
    }

    private func numberedStep(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.accent.swiftUI)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent.swiftUI.opacity(0.14)))
                .overlay(Circle().strokeBorder(Theme.accent.swiftUI.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text.swiftUI)
                Text(body)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
    }

    private func bulletList(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.0) { title, detail in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Theme.accent.swiftUI).frame(width: 5, height: 5).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text.swiftUI)
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textDim.swiftUI)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(1.5)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.lane.swiftUI))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Preferences View (`G63`)

struct PreferencesView: View {
    @Bindable var model: AppModel
    @State private var oscPortText: String = ""
    @State private var httpPortText: String = ""

    var body: some View {
        @Bindable var updater = model.updater
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(L("Langue & Mises à jour", "Language & Updates"))
            FieldRow(L("Langue", "Language"), width: 170) {
                Picker("", selection: $model.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            HStack(spacing: 10) {
                Toggle(L("Vérifier les mises à jour au lancement", "Check for updates on launch"), isOn: $updater.autoCheckOnLaunch)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text.swiftUI)
                Spacer()
                TextButton(title: L("Vérifier maintenant…", "Check Now…"), symbol: "arrow.down.circle", compact: true) {
                    model.showUpdater = true
                    model.updater.checkForUpdates(silent: false)
                }
            }

            Divider().overlay(Theme.separator.swiftUI)

            SectionHeader(L("Affichage & Édition PDF", "Display & PDF Editing"))
            Toggle(L("Encadrer les blocs de texte PDF éditables", "Highlight editable PDF text blocks"), isOn: $model.showPDFTextBoxes)
                .font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            Toggle(L("Barre latérale des pages et calques", "Pages and layers sidebar"), isOn: $model.showSidebar)
                .font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)
            Toggle(L("Inspecteur vectoriel détaillé", "Detailed vector inspector"), isOn: $model.showInspector)
                .font(.system(size: 11.5)).foregroundStyle(Theme.text.swiftUI)

            Divider().overlay(Theme.separator.swiftUI)

            SectionHeader(L("Ports OSC, API HTTP & MCP", "OSC, HTTP API & MCP Ports"))
            FieldRow(L("Port OSC entrant (UDP)", "Incoming OSC Port (UDP)"), width: 170) {
                HStack(spacing: 6) {
                    TextField("9160", text: $oscPortText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text.swiftUI)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(width: 80)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05)))
                        .onSubmit { applyPorts() }
                    TextButton(title: L("Appliquer", "Apply"), compact: true) { applyPorts() }
                }
            }
            FieldRow("Port HTTP / MCP (127.0.0.1)", width: 170) {
                HStack(spacing: 6) {
                    TextField("17960", text: $httpPortText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text.swiftUI)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(width: 80)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05)))
                        .onSubmit { applyPorts() }
                    Text(verbatim: "/v1")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
            }

            Divider().overlay(Theme.separator.swiftUI)

            SectionHeader(L("Réseau & Confidentialité", "Network & Privacy"))
            Text(L("SimpleVector travaille intégralement en local sur les fichiers SVG et PDF. Il écoute uniquement les commandes locales de régie (OSC UDP :9160, HTTP 127.0.0.1:17960) et le relais MCP local (simplevector-mcp). Aucune télémétrie, aucune connexion externe hors vérification optionnelle des mises à jour GitHub.", "SimpleVector processes SVG and PDF files strictly locally. It only listens to local show-control commands (OSC UDP :9160, HTTP 127.0.0.1:17960) and the local MCP relay (simplevector-mcp). Zero telemetry, zero external connections besides optional GitHub update checks."))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim.swiftUI)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 500, height: 500, alignment: .topLeading)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
        .onAppear {
            oscPortText = "\(model.controller.oscServer?.port ?? kSimpleVectorDefaultOSCInPort)"
            httpPortText = "\(model.controller.httpPort)"
        }
    }

    private func applyPorts() {
        if let oscP = UInt16(oscPortText.trimmingCharacters(in: .whitespaces)), oscP > 0 {
            model.controller.startOSCServer(port: oscP)
        }
        if let httpP = UInt16(httpPortText.trimmingCharacters(in: .whitespaces)), httpP > 0 {
            model.controller.startHTTPServer(port: httpP)
        }
        model.flash(L("Ports OSC (:\(oscPortText)) et HTTP/MCP (:\(httpPortText)) mis à jour", "OSC (:\(oscPortText)) and HTTP/MCP (:\(httpPortText)) ports updated"))
    }
}

// MARK: - Update Sheet (`SimpleUpdater`)

struct UpdateSheet: View {
    @Bindable var model: AppModel
    let close: () -> Void

    var body: some View {
        let updater = model.updater
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VectorHeroGraphic(active: updater.state == .checking, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Mises à jour — SimpleVector", "Software Update — SimpleVector"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text.swiftUI)
                    Text(L("Version installée : v\(updater.currentVersion) (build \(updater.currentBuild))", "Installed version: v\(updater.currentVersion) (build \(updater.currentBuild))"))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
                Spacer()
            }

            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            switch updater.state {
            case .idle, .checking:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L("Recherche de mises à jour en cours…", "Checking for updates…"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
                .padding(.vertical, 14)

            case .upToDate(let v):
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.alive.swiftUI)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("SimpleVector v\(v) est à jour.", "SimpleVector v\(v) is up to date."))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.text.swiftUI)
                        Text(L("Cette version est la dernière disponible.", "This is the latest available version."))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textDim.swiftUI)
                    }
                }
                .padding(.vertical, 10)

            case .updateAvailable(let rel):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Chip(text: L("NOUVELLE VERSION v\(rel.version)", "NEW VERSION v\(rel.version)"), tint: Theme.accent.swiftUI, filled: true)
                        Spacer()
                    }
                    ScrollView {
                        Text(rel.localizedNotes)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.text.swiftUI)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 70, maxHeight: 140)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                }

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Téléchargement de la mise à jour…", "Downloading update…"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text.swiftUI)
                    ProgressView(value: progress)
                        .tint(Theme.accent.swiftUI)
                }
                .padding(.vertical, 10)

            case .installing:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L("Vérification de la signature et installation…", "Verifying code signature and installing…"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text.swiftUI)
                }
                .padding(.vertical, 10)

            case .failed(let message):
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.warning.swiftUI)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Impossible de vérifier ou d'installer la mise à jour", "Could not check or install update"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text.swiftUI)
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textDim.swiftUI)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
            }

            HStack {
                TextButton(title: L("Rechercher à nouveau", "Check Again"), symbol: "arrow.clockwise", compact: true) {
                    updater.checkForUpdates(silent: false)
                }
                Spacer()
                if case .updateAvailable(let rel) = updater.state {
                    Button(L("Plus tard", "Later"), action: close)
                    TextButton(title: L("Mettre à jour et relancer", "Update & Relaunch"), symbol: "arrow.down.circle.fill", prominent: true) {
                        updater.downloadAndInstall(rel)
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(L("Fermer", "Close"), action: close)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.panel.swiftUI)
        .preferredColorScheme(.dark)
    }
}
