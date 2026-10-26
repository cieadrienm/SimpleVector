import SimpleVectorCore
import SwiftUI

struct TopBar: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var ctrl = model.controller
        HStack(spacing: 7) {
            IconButton(
                symbol: "sidebar.left",
                helpText: L("Afficher ou masquer la barre latérale des pages et calques (⌥⌘S)", "Show or hide pages and layers sidebar (⌥⌘S)"),
                active: model.showSidebar
            ) {
                model.showSidebar.toggle()
            }

            Divider().frame(height: 16)

            // File actions
            IconButton(
                symbol: "folder",
                helpText: L("Ouvrir un document SVG ou PDF (⌘O)", "Open an SVG or PDF document (⌘O)")
            ) {
                model.openDocumentPanel()
            }

            IconButton(
                symbol: "square.and.arrow.down",
                helpText: L("Enregistrer le document (⌘S)", "Save document (⌘S)")
            ) {
                model.saveDocumentDirectOrPanel()
            }

            IconButton(
                symbol: "arrow.up.doc",
                helpText: L("Exporter en PDF multipage, SVG ou PNG (⌘E)", "Export to multi-page PDF, SVG, or PNG (⌘E)")
            ) {
                model.showExportSheet = true
            }

            IconButton(
                symbol: "arrow.uturn.backward",
                helpText: L("Annuler la dernière opération (⌘Z)", "Undo last operation (⌘Z)"),
                disabled: !ctrl.history.canUndo
            ) {
                ctrl.undo()
            }

            IconButton(
                symbol: "arrow.uturn.forward",
                helpText: L("Rétablir l'opération annulée (⇧⌘Z)", "Redo operation (⇧⌘Z)"),
                disabled: !ctrl.history.canRedo
            ) {
                ctrl.redo()
            }

            Divider().frame(height: 16)

            // Vector & PDF editing tools strip
            toolPickerStrip

            Divider().frame(height: 16)

            // Quick 1-click Sign & Page controls
            TextButton(
                title: L("Signer", "Sign"),
                symbol: "signature",
                prominent: true,
                compact: true
            ) {
                ctrl.stampActiveSignature()
            }
            .help(L("Apposer la signature active sur la page courante (S)", "Place active signature on current page (S)"))

            stampMenuButton

            IconButton(
                symbol: "doc.badge.plus",
                helpText: L("Ajouter une page au document multipage (⇧⌘N)", "Add a page to the multi-page document (⇧⌘N)")
            ) {
                ctrl.addBlankPage()
            }

            Divider().frame(height: 16)

            // Display mode & Zoom / Reset View (Z)
            displayModePicker

            zoomControls

            Spacer(minLength: 4)

            searchField

            IconButton(
                symbol: "sidebar.right",
                helpText: L("Afficher ou masquer l'inspecteur vectoriel (⌥⌘I)", "Show or hide vector inspector (⌥⌘I)"),
                active: model.showInspector
            ) {
                model.toggleInspector()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Theme.panel.swiftUI)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator.swiftUI).frame(height: 1) }
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
    }

    private var toolPickerStrip: some View {
        HStack(spacing: 2) {
            ForEach(EditorTool.allCases) { tool in
                let active = model.activeTool == tool
                Button {
                    model.activeTool = tool
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(tool.label)
                            .font(.system(size: 10.5, weight: active ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(active ? Theme.background.swiftUI : Theme.text.swiftUI)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 4)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(active ? Theme.accent.swiftUI : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tool.helpText)
            }
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
        .background(RoundedRectangle(cornerRadius: 5.5).fill(Color.white.opacity(0.05)))
    }

    private var stampMenuButton: some View {
        Menu {
            Section(L("Apposer un tampon vectoriel", "Place Vector Stamp")) {
                ForEach(VectorStampKind.allCases) { kind in
                    Button {
                        model.controller.activeStampKind = kind
                        model.controller.stampApprovalBadge(kind: kind)
                    } label: {
                        Label(kind.defaultTitle, systemImage: "seal.fill")
                    }
                }
            }
            Divider()
            Section(L("Choisir la signature active", "Choose Active Signature")) {
                ForEach(model.controller.signatures) { preset in
                    Button {
                        model.controller.activeSignaturePresetID = preset.id
                        model.controller.stampActiveSignature()
                    } label: {
                        Label("\(preset.title) (\(preset.caption))", systemImage: "signature")
                    }
                }
            }
            Divider()
            Button(L("Charger le document de démonstration (3 pages PDF + SVG)", "Load Demo Document (3 pages PDF + SVG)")) {
                model.controller.loadDemoDocument()
            }
        } label: {
            Image(systemName: "seal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text.swiftUI)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Tampons d'approbation, bibliothèque de signatures et document démo (K)", "Approval stamps, signature library, and demo document (K)"))
    }

    private var displayModePicker: some View {
        HStack(spacing: 2) {
            ForEach(CanvasDisplayMode.allCases) { mode in
                let active = model.displayMode == mode
                Button {
                    model.displayMode = mode
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? Theme.background.swiftUI : Theme.textDim.swiftUI)
                        .frame(width: 24, height: 22)
                        .background(RoundedRectangle(cornerRadius: 4).fill(active ? Theme.accent.swiftUI : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Vue \(mode.label) (\(mode.shortcutLabel))", "\(mode.label) view (\(mode.shortcutLabel))"))
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 5.5).fill(Color.white.opacity(0.05)))
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            IconButton(
                symbol: "minus.magnifyingglass",
                helpText: L("Zoom arrière (⌘-)", "Zoom out (⌘-)")
            ) {
                model.stepZoom(factor: 0.8)
            }

            Button {
                model.resetViewAnimated()
            } label: {
                Text(Format.percent(model.zoomScale))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(abs(model.zoomScale - 1.0) < 0.01 && model.panOffset == .zero ? Theme.textDim.swiftUI : Theme.accent.swiftUI)
                    .frame(width: 44)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help(L("Réinitialiser la vue à 100 % (Z)", "Reset view to 100% (Z)"))

            IconButton(
                symbol: "plus.magnifyingglass",
                helpText: L("Zoom avant (⌘+)", "Zoom in (⌘+)")
            ) {
                model.stepZoom(factor: 1.25)
            }

            IconButton(
                symbol: "arrow.up.left.and.down.right.magnifyingglass",
                helpText: L("Cadrer tout ou cadrer la sélection (⇧Z / F)", "Fit page or frame selection (⇧Z / F)")
            ) {
                model.fitSelectionOrPageAnimated()
            }

            IconButton(
                symbol: "character.textbox",
                helpText: L("Afficher ou masquer les cadres des textes PDF éditables", "Show or hide editable PDF text frames"),
                active: model.showPDFTextBoxes,
                tint: Theme.tcp.swiftUI
            ) {
                model.showPDFTextBoxes.toggle()
            }
        }
    }

    private var searchField: some View {
        @Bindable var ctrl = model.controller
        return HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(searchFocused ? Theme.accent.swiftUI : Theme.textDim.swiftUI)
            TextField(L("Filtrer texte / calque", "Filter text / layer"), text: $ctrl.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)
                .focused($searchFocused)
                .onExitCommand { ctrl.searchQuery = ""; searchFocused = false }
            if !ctrl.searchQuery.isEmpty {
                Button { ctrl.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textDim.swiftUI)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(width: 142)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(searchFocused ? Theme.accent.swiftUI.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .help(L("Rechercher un texte dans le PDF/SVG ou filtrer les éléments (⌘F)", "Search text in PDF/SVG or filter elements (⌘F)"))
    }
}

struct StatusBar: View {
    @Bindable var model: AppModel

    var body: some View {
        let ctrl = model.controller
        let doc = ctrl.document
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Chip(
                    text: doc.sourceFormat.rawValue,
                    tint: doc.sourceFormat == .pdf ? Theme.tcp.swiftUI : Theme.accent.swiftUI,
                    filled: false
                )
                Text(model.flashMessage ?? ctrl.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(ctrl.lastError != nil ? Theme.danger.swiftUI : Theme.textDim.swiftUI)
                    .lineLimit(1)
            }

            Spacer()

            // Multipage navigation pill in status bar
            HStack(spacing: 6) {
                Button {
                    if ctrl.currentPageIndex > 0 { ctrl.currentPageIndex -= 1 }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 9.5, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(ctrl.currentPageIndex <= 0)
                .help(L("Page précédente ([)", "Previous page ([)"))

                Text(L("Page \(ctrl.currentPageIndex + 1)/\(doc.pages.count)", "Page \(ctrl.currentPageIndex + 1)/\(doc.pages.count)"))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text.swiftUI)

                Button {
                    if ctrl.currentPageIndex + 1 < doc.pages.count { ctrl.currentPageIndex += 1 }
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(ctrl.currentPageIndex + 1 >= doc.pages.count)
                .help(L("Page suivante (])", "Next page (])"))
            }

            Divider().frame(height: 12)

            Text(summaryText)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textFaint.swiftUI)

            Divider().frame(height: 12)

            HStack(spacing: 12) {
                Button { model.showOSCGuide = true } label: {
                    Text(verbatim: "OSC :\(ctrl.oscServer?.port ?? kSimpleVectorDefaultOSCInPort)")
                        .foregroundStyle(Theme.osc.swiftUI)
                }
                .buttonStyle(.plain)
                .help(L("Guide des commandes OSC, API HTTP et MCP", "OSC Commands, HTTP API, and MCP Guide"))

                Button { model.showHelp = true } label: { Text(L("? aide", "? help")) }
                    .buttonStyle(.plain).help(L("Guide d'utilisation (⌘?)", "User Guide (⌘?)"))
                Button { model.showShortcuts = true } label: { Text(L("⌘/ raccourcis", "⌘/ shortcuts")) }
                    .buttonStyle(.plain).help(L("Raccourcis clavier (⌘/)", "Keyboard Shortcuts (⌘/)"))
                Button { model.showAbout = true } label: {
                    Text(AppVersion.current.shortLabel).foregroundStyle(Theme.textDim.swiftUI)
                }
                .buttonStyle(.plain).help(L("À propos de SimpleVector \(AppVersion.current.description)", "About SimpleVector \(AppVersion.current.description)"))

                if let rel = model.updater.availableRelease {
                    Button {
                        model.showUpdater = true
                    } label: {
                        Text(L("↑ MAJ v\(rel.version)", "↑ Update v\(rel.version)"))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.background.swiftUI)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Theme.accent.swiftUI))
                    }
                    .buttonStyle(.plain)
                    .help(L("Une mise à jour SimpleVector v\(rel.version) est disponible", "SimpleVector v\(rel.version) update is available"))
                }
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Theme.textFaint.swiftUI)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Theme.panel.swiftUI)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator.swiftUI).frame(height: 1) }
    }

    private var summaryText: String {
        let ctrl = model.controller
        let doc = ctrl.document
        var parts: [String] = []
        parts.append(L("\(ctrl.currentPage.elements.count) élém.", "\(ctrl.currentPage.elements.count) elem."))
        if doc.pdfTextElementCount > 0 {
            let mod = doc.modifiedPDFTextCount
            if mod > 0 {
                parts.append(L("\(doc.pdfTextElementCount) textes PDF (\(mod) éd.)", "\(doc.pdfTextElementCount) PDF texts (\(mod) ed.)"))
            } else {
                parts.append(L("\(doc.pdfTextElementCount) textes PDF", "\(doc.pdfTextElementCount) PDF texts"))
            }
        }
        if doc.signatureCount > 0 {
            parts.append(L(Format.count(doc.signatureCount, "signature"), "\(doc.signatureCount) sign."))
        }
        if !ctrl.selection.isEmpty {
            parts.append(L("\(ctrl.selection.count) sél.", "\(ctrl.selection.count) sel."))
        }
        return parts.joined(separator: " · ")
    }
}
