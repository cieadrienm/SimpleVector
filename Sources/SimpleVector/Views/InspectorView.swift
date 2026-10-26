import SimpleVectorCore
import SwiftUI

struct InspectorView: View {
    @Bindable var model: AppModel

    private static let colorSwatches: [(String, String)] = [
        ("#111317", L("Noir", "Black")),
        ("#1E3A8A", L("Bleu encre", "Ink Blue")),
        ("#0F766E", L("Vert sarcelle", "Teal")),
        ("#16A34A", L("Vert accord", "Green")),
        ("#D97706", L("Ambre", "Amber")),
        ("#DC2626", L("Rouge", "Red")),
        ("#7C3AED", L("Violet", "Violet")),
        ("#DBEAFE", L("Bleu clair", "Light Blue")),
        ("#FEF3C7", L("Jaune pâle", "Soft Yellow")),
        ("#F3F4F6", L("Gris clair", "Light Gray")),
        ("#FFFFFF", L("Blanc", "White")),
    ]

    var body: some View {
        let ctrl = model.controller
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let selected = ctrl.primarySelectedElement {
                    selectedElementSection(selected)
                    Divider().overlay(Theme.separator.swiftUI)
                }

                signatureLibrarySection

                Divider().overlay(Theme.separator.swiftUI)

                quickStampsSection

                Divider().overlay(Theme.separator.swiftUI)

                pageAndDocumentSection
            }
            .padding(12)
        }
        .background(Theme.panel.swiftUI)
    }

    // MARK: - 1. Selected Element Section

    @ViewBuilder
    private func selectedElementSection(_ el: VectorElement) -> some View {
        let ctrl = model.controller
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(L("Élément sélectionné", "Selected Element")) {
                Chip(text: el.typeBadge, tint: Theme.elementTint(el).swiftUI, filled: true)
            }

            FieldRow(L("Nom", "Name"), width: 78) {
                CommitField(value: el.name, placeholder: L("Nom du calque", "Layer name")) { newName in
                    ctrl.perform { doc in
                        VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                            item.name = newName
                        }
                    }
                }
            }

            // Kind-specific controls
            switch el.kind {
            case .text(let t):
                textInspectorControls(el: el, payload: t)
            case .signature(let sig):
                signatureInspectorControls(el: el, payload: sig)
            case .shape(let s):
                shapeInspectorControls(el: el, payload: s)
            case .stamp(let st):
                stampInspectorControls(el: el, payload: st)
            case .path:
                EmptyView()
            }

            // Style & Colors
            SectionHeader(L("Style & Couleurs", "Style & Colors"))

            VStack(alignment: .leading, spacing: 5) {
                Text(L("Contour / Encre", "Stroke / Ink"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textDim.swiftUI)
                colorSwatchStrip(currentHex: el.style.strokeColorHex, allowNone: true) { newHex in
                    ctrl.perform { doc in
                        VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                            item.style.strokeColorHex = newHex
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(L("Remplissage / Texte", "Fill / Text"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textDim.swiftUI)
                colorSwatchStrip(currentHex: el.style.fillColorHex, allowNone: true) { newHex in
                    ctrl.perform { doc in
                        VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                            item.style.fillColorHex = newHex
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text(L("Trait", "Width"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .frame(width: 48, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { el.style.strokeWidth },
                        set: { v in
                            VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &ctrl.document) { item in
                                item.style.strokeWidth = v
                            }
                        }
                    ),
                    in: 0...10
                )
                .tint(Theme.accent.swiftUI)
                Text(String(format: "%.1f pt", el.style.strokeWidth))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .frame(width: 44, alignment: .trailing)
            }

            // Geometry, Rotation & Z-Order
            SectionHeader(L("Géométrie, Rotation & Ordre", "Geometry, Rotation & Order"))

            HStack(spacing: 6) {
                coordBadge(label: "X", value: Int(round(el.frame.x)))
                coordBadge(label: "Y", value: Int(round(el.frame.y)))
                coordBadge(label: "L", value: Int(round(el.frame.width)))
                coordBadge(label: "H", value: Int(round(el.frame.height)))
            }

            if case .signature = el.kind {
                proportionalSizeSlider(for: el)
            } else if case .stamp = el.kind {
                proportionalSizeSlider(for: el)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(L("Rotation", "Angle"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textDim.swiftUI)
                        .frame(width: 52, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { el.rotationDegrees },
                            set: { deg in
                                VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &ctrl.document) { item in
                                    item.rotationDegrees = deg
                                }
                            }
                        ),
                        in: -180...180
                    )
                    .tint(Theme.accent.swiftUI)
                    Text(String(format: "%+.0f°", el.rotationDegrees))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.text.swiftUI)
                        .frame(width: 42, alignment: .trailing)
                }

                HStack(spacing: 5) {
                    TextButton(title: "-15°", compact: true) {
                        ctrl.perform(L("Rotation -15°", "Rotated -15°")) { doc in
                            VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                var d = item.rotationDegrees - 15.0
                                if d < -180.0 { d += 360.0 }
                                item.rotationDegrees = d
                            }
                        }
                    }
                    TextButton(title: "0°", compact: true) {
                        ctrl.perform(L("Rotation réinitialisée (0°)", "Rotation reset (0°)")) { doc in
                            VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                item.rotationDegrees = 0.0
                            }
                        }
                    }
                    TextButton(title: "+15°", compact: true) {
                        ctrl.perform(L("Rotation +15°", "Rotated +15°")) { doc in
                            VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                var d = item.rotationDegrees + 15.0
                                if d > 180.0 { d -= 360.0 }
                                item.rotationDegrees = d
                            }
                        }
                    }
                    TextButton(title: "90°", symbol: "rotate.right", compact: true) {
                        ctrl.perform(L("Rotation +90°", "Rotated +90°")) { doc in
                            VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                var d = item.rotationDegrees + 90.0
                                if d > 180.0 { d -= 360.0 }
                                item.rotationDegrees = d
                            }
                        }
                    }
                    Spacer()
                }
            }

            HStack(spacing: 6) {
                TextButton(title: L("1er plan", "Front"), symbol: "square.3.layers.3d.top.filled", compact: true) {
                    ctrl.perform(L("Mis au premier plan", "Brought to front")) { doc in
                        VectorOperations.bringToFront(ids: [el.id], onPage: ctrl.currentPageIndex, in: &doc)
                    }
                }
                TextButton(title: L("Arrière", "Back"), symbol: "square.3.layers.3d.bottom.filled", compact: true) {
                    ctrl.perform(L("Mis à l'arrière-plan", "Sent to back")) { doc in
                        VectorOperations.sendToBack(ids: [el.id], onPage: ctrl.currentPageIndex, in: &doc)
                    }
                }
                TextButton(title: L("Dupliquer", "Duplicate"), symbol: "plus.square.on.square", compact: true) {
                    ctrl.duplicateSelectedElements()
                }
                Spacer(minLength: 0)
                IconButton(
                    symbol: "trash",
                    helpText: L("Supprimer la sélection (⌫)", "Delete selection (⌫)"),
                    tint: Theme.danger.swiftUI
                ) {
                    ctrl.deleteSelectedElements()
                }
            }
        }
    }

    private func textInspectorControls(el: VectorElement, payload: TextPayload) -> some View {
        let ctrl = model.controller
        return VStack(alignment: .leading, spacing: 8) {
            if payload.isPDFExtracted {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.tcp.swiftUI)
                    Text(el.hasModifiedPDFText
                        ? L("Texte PDF modifié (masquage vectoriel actif)", "Edited PDF text (vector mask active)")
                        : L("Texte extrait du flux PDF natif", "Text extracted from native PDF stream"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(el.hasModifiedPDFText ? Theme.alive.swiftUI : Theme.tcp.swiftUI)
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.tcp.swiftUI.opacity(0.08)))
            }

            CommitField(
                value: payload.text,
                placeholder: L("Contenu du texte…", "Text content…"),
                onCommit: { newText in
                    ctrl.perform(L("Texte modifié", "Text updated")) { doc in
                        VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                            if case .text(var t) = item.kind {
                                t.text = newText
                                item.kind = .text(t)
                                PDFCodec.updateTextFrameForEditedContent(&item)
                            }
                        }
                    }
                }
            )

            HStack(spacing: 6) {
                Text(L("Police", "Font"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .frame(width: 48, alignment: .leading)
                Picker(
                    "",
                    selection: Binding(
                        get: { payload.fontFamily },
                        set: { newFam in
                            ctrl.perform(L("Police modifiée", "Font updated")) { doc in
                                VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                    if case .text(var t) = item.kind {
                                        t.fontFamily = newFam
                                        t.postScriptFontName = nil
                                        item.kind = .text(t)
                                        PDFCodec.updateTextFrameForEditedContent(&item)
                                    }
                                }
                            }
                        }
                    )
                ) {
                    let baseChoices = ["Helvetica Neue", "Arial", "Verdana", "Trebuchet MS", "Avenir Next", "Gill Sans", "Times New Roman", "Georgia", "Courier New", payload.fontFamily] + PDFEmbeddedFontRegistry.shared.registeredFamilyNames
                    let choices = Array(Set(baseChoices.filter { !$0.isEmpty })).sorted()
                    ForEach(choices, id: \.self) { fam in
                        Text(fam).tag(fam)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 6) {
                Text(L("Corps", "Size"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim.swiftUI)
                Slider(
                    value: Binding(
                        get: { payload.fontSize },
                        set: { newSize in
                            VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &ctrl.document) { item in
                                if case .text(var t) = item.kind {
                                    t.fontSize = newSize
                                    item.kind = .text(t)
                                    PDFCodec.updateTextFrameForEditedContent(&item)
                                }
                            }
                        }
                    ),
                    in: 6...42
                )
                .tint(Theme.accent.swiftUI)
                Text(String(format: "%.1f pt", payload.fontSize))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 46, alignment: .trailing)
            }

            HStack(spacing: 6) {
                IconButton(
                    symbol: "bold",
                    helpText: L("Gras", "Bold"),
                    active: payload.isBold
                ) {
                    ctrl.perform { doc in
                        VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                            if case .text(var t) = item.kind {
                                t.isBold.toggle()
                                item.kind = .text(t)
                            }
                        }
                    }
                }
                IconButton(
                    symbol: "italic",
                    helpText: L("Italique", "Italic"),
                    active: payload.isItalic
                ) {
                    ctrl.perform { doc in
                        VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                            if case .text(var t) = item.kind {
                                t.isItalic.toggle()
                                item.kind = .text(t)
                            }
                        }
                    }
                }
                Divider().frame(height: 14)
                ForEach(TextAlignmentMode.allCases) { align in
                    IconButton(
                        symbol: align.symbol,
                        helpText: align.label,
                        active: payload.alignment == align
                    ) {
                        ctrl.perform { doc in
                            VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                if case .text(var t) = item.kind {
                                    t.alignment = align
                                    item.kind = .text(t)
                                }
                            }
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private func signatureInspectorControls(el: VectorElement, payload: SignaturePayload) -> some View {
        let ctrl = model.controller
        return VStack(alignment: .leading, spacing: 8) {
            if payload.assetData != nil {
                Toggle(
                    L("Détourer le fond blanc (mode encre)", "Remove white background (ink mode)"),
                    isOn: Binding(
                        get: { payload.removeWhiteBackground },
                        set: { v in
                            ctrl.perform(L("Fond de signature mis à jour", "Signature background updated")) { doc in
                                VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                    if case .signature(var s) = item.kind {
                                        s.removeWhiteBackground = v
                                        item.kind = .signature(s)
                                    }
                                }
                            }
                        }
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)
            } else {
                FieldRow(L("Signataire", "Signer"), width: 78) {
                    CommitField(value: payload.signerName, placeholder: L("Nom du signataire", "Signer name")) { newSigner in
                        ctrl.perform { doc in
                            VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                if case .signature(var s) = item.kind {
                                    s.signerName = newSigner
                                    item.kind = .signature(s)
                                }
                            }
                        }
                    }
                }
                FieldRow(L("Mention", "Caption"), width: 78) {
                    CommitField(value: payload.caption ?? "", placeholder: L("Mention (optionnel)", "Caption (optional)")) { newCaption in
                        ctrl.perform { doc in
                            VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                if case .signature(var s) = item.kind {
                                    s.caption = newCaption
                                    item.kind = .signature(s)
                                }
                            }
                        }
                    }
                }
                TextButton(
                    title: L("Garder dans mes signatures", "Save to Signature Library"),
                    symbol: "star",
                    compact: true
                ) {
                    ctrl.saveCustomSignature(from: el)
                }
            }
        }
    }

    private func shapeInspectorControls(el: VectorElement, payload: ShapePayload) -> some View {
        let ctrl = model.controller
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle(
                    L("Pointillés", "Dashed"),
                    isOn: Binding(
                        get: { el.style.dashed },
                        set: { v in
                            ctrl.perform { doc in
                                VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                    item.style.dashed = v
                                }
                            }
                        }
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)

                if payload.shapeType == .line || payload.shapeType == .arrow {
                    Toggle(
                        L("Flèche fin", "End Arrow"),
                        isOn: Binding(
                            get: { payload.endArrow },
                            set: { v in
                                ctrl.perform { doc in
                                    VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                        if case .shape(var s) = item.kind {
                                            s.endArrow = v
                                            item.kind = .shape(s)
                                        }
                                    }
                                }
                            }
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text.swiftUI)
                }
            }
        }
    }

    private func stampInspectorControls(el: VectorElement, payload: StampPayload) -> some View {
        let ctrl = model.controller
        return VStack(alignment: .leading, spacing: 8) {
            if payload.assetData != nil {
                Toggle(
                    L("Détourer le fond blanc (mode encre)", "Remove white background (ink mode)"),
                    isOn: Binding(
                        get: { payload.removeWhiteBackground },
                        set: { v in
                            ctrl.perform(L("Fond du tampon mis à jour", "Stamp background updated")) { doc in
                                VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                    if case .stamp(var st) = item.kind {
                                        st.removeWhiteBackground = v
                                        item.kind = .stamp(st)
                                    }
                                }
                            }
                        }
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.text.swiftUI)
            } else {
                FieldRow(L("Titre", "Title"), width: 78) {
                    CommitField(value: payload.title, placeholder: "BON POUR ACCORD") { newTitle in
                        ctrl.perform { doc in
                            VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                if case .stamp(var st) = item.kind {
                                    st.title = newTitle
                                    item.kind = .stamp(st)
                                }
                            }
                        }
                    }
                }
                FieldRow(L("Sous-titre", "Subtitle"), width: 78) {
                    CommitField(value: payload.subtitle, placeholder: L("Date ou mention", "Date or caption")) { newSub in
                        ctrl.perform { doc in
                            VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &doc) { item in
                                if case .stamp(var st) = item.kind {
                                    st.subtitle = newSub
                                    item.kind = .stamp(st)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 2. Signature Library Section

    private var signatureLibrarySection: some View {
        let ctrl = model.controller
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(L("Signatures", "Signatures")) {
                HStack(spacing: 4) {
                    IconButton(
                        symbol: "folder",
                        helpText: L("Ouvrir ~/Library/Application Support/SimpleVector/Signatures dans le Finder", "Open Signatures folder in Finder")
                    ) {
                        ctrl.openSignaturesFolderInFinder()
                    }
                    IconButton(
                        symbol: "arrow.clockwise",
                        helpText: L("Actualiser le dossier Signatures", "Reload Signatures folder")
                    ) {
                        ctrl.reloadSignaturesAndStampsFromDisk()
                    }
                    TextButton(
                        title: L("+ Fichier…", "+ File…"),
                        symbol: "plus",
                        compact: true
                    ) {
                        ctrl.importSignatureFileInteractive()
                    }
                    TextButton(
                        title: L("Signer", "Sign"),
                        symbol: "signature",
                        prominent: true,
                        compact: true
                    ) {
                        ctrl.stampActiveSignature()
                    }
                }
            }

            Text("~/Library/Application Support/SimpleVector/Signatures")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.textFaint.swiftUI)
                .lineLimit(1)
                .truncationMode(.middle)

            if ctrl.signatures.isEmpty {
                Text(L("Aucune signature enregistrée. Cliquer sur « + Fichier… » pour importer un PDF/PNG/JPG dans le dossier Signatures, ou tracer une signature à la main avec l'outil Signature (S).", "No saved signatures. Click \"+ File…\" to import a PDF/PNG/JPG into the Signatures folder, or draw a freehand signature with the Signature tool (S)."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textDim.swiftUI)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.lane.swiftUI))
            }

            ForEach(ctrl.signatures) { preset in
                let isSelected = preset.id == ctrl.activeSignaturePresetID
                Button {
                    ctrl.activeSignaturePresetID = preset.id
                } label: {
                    HStack(spacing: 10) {
                        SignatureMiniPreview(preset: preset)
                            .frame(width: 72, height: 28)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.text.swiftUI)
                                .lineLimit(1)
                            Text(preset.fileURL != nil ? L("Fichier \(preset.caption)", "File \(preset.caption)") : preset.caption)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textDim.swiftUI)
                                .lineLimit(1)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.accent.swiftUI)
                        }
                    }
                    .padding(7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Theme.laneSelected.swiftUI : Theme.lane.swiftUI)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(isSelected ? Theme.accent.swiftUI.opacity(0.6) : Color.clear, lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 3. Quick Stamps Section

    private var quickStampsSection: some View {
        let ctrl = model.controller
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(L("Tampons & Visas", "Stamps & Visas")) {
                HStack(spacing: 4) {
                    IconButton(
                        symbol: "folder",
                        helpText: L("Ouvrir ~/Library/Application Support/SimpleVector/Stamps dans le Finder", "Open Stamps folder in Finder")
                    ) {
                        ctrl.openStampsFolderInFinder()
                    }
                    IconButton(
                        symbol: "arrow.clockwise",
                        helpText: L("Actualiser le dossier Stamps", "Reload Stamps folder")
                    ) {
                        ctrl.reloadSignaturesAndStampsFromDisk()
                    }
                    TextButton(
                        title: L("+ Fichier…", "+ File…"),
                        symbol: "plus",
                        compact: true
                    ) {
                        ctrl.importStampFileInteractive()
                    }
                }
            }

            Text("~/Library/Application Support/SimpleVector/Stamps")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.textFaint.swiftUI)
                .lineLimit(1)
                .truncationMode(.middle)

            if !ctrl.customStamps.isEmpty {
                ForEach(ctrl.customStamps) { preset in
                    let isSelected = ctrl.activeCustomStampPresetID == preset.id
                    Button {
                        ctrl.activeCustomStampPresetID = preset.id
                        ctrl.stampCustomStamp(preset)
                    } label: {
                        HStack(spacing: 10) {
                            StampMiniPreview(preset: preset)
                                .frame(width: 56, height: 32)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Theme.text.swiftUI)
                                    .lineLimit(1)
                                Text(L("Fichier \(preset.assetExtension.uppercased()) · Cliquer pour apposer", "File \(preset.assetExtension.uppercased()) · Click to place"))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Theme.textDim.swiftUI)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "seal.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(isSelected ? Theme.accent.swiftUI : Theme.textDim.swiftUI)
                        }
                        .padding(7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Theme.laneSelected.swiftUI : Theme.lane.swiftUI)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(isSelected ? Theme.accent.swiftUI.opacity(0.6) : Color.clear, lineWidth: 1)
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach([VectorStampKind.approved, .signed, .stagePlot, .confidential, .check, .draft]) { kind in
                    let rgb = RGBAColor(hex: kind.defaultColorHex) ?? RGBAColor(r: 0.2, g: 0.7, b: 0.4)
                    Button {
                        ctrl.activeCustomStampPresetID = nil
                        ctrl.activeStampKind = kind
                        ctrl.stampApprovalBadge(kind: kind)
                    } label: {
                        Text(kind.defaultTitle)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder(Color(red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 0.45), lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 4. Page & Document Section

    private var pageAndDocumentSection: some View {
        let ctrl = model.controller
        let page = ctrl.currentPage
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(L("Page & Document Multipage", "Page & Multi-Page Document"))

            FieldRow(L("Document", "Document"), width: 78) {
                CommitField(value: ctrl.document.title, placeholder: L("Titre du document", "Document title")) { newTitle in
                    ctrl.document.title = newTitle
                }
            }

            FieldRow(L("Titre page", "Page title"), width: 78) {
                CommitField(value: page.title, placeholder: "Page 1") { newTitle in
                    ctrl.perform { doc in
                        doc.pages[ctrl.currentPageIndex].title = newTitle
                    }
                }
            }

            FieldRow(L("Dimensions", "Size"), width: 78) {
                Text(page.dimensionsLabel)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textDim.swiftUI)
            }

            HStack(spacing: 6) {
                ForEach([PageFormatPreset.a4Portrait, .a4Landscape, .stage16x9]) { preset in
                    TextButton(title: preset.rawValue, compact: true) {
                        let size = preset.sizePoints
                        ctrl.perform(L("Format de page changé en \(preset.rawValue)", "Page format changed to \(preset.rawValue)")) { doc in
                            doc.pages[ctrl.currentPageIndex].width = size.width
                            doc.pages[ctrl.currentPageIndex].height = size.height
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func colorSwatchStrip(currentHex: String?, allowNone: Bool, onSelect: @escaping (String?) -> Void) -> some View {
        HStack(spacing: 5) {
            if allowNone {
                Button {
                    onSelect(nil)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 18, height: 18)
                        Image(systemName: "slash.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(currentHex == nil ? Theme.accent.swiftUI : Theme.textFaint.swiftUI)
                    }
                }
                .buttonStyle(.plain)
                .help(L("Aucun / Transparent", "None / Transparent"))
            }

            ForEach(Self.colorSwatches, id: \.0) { hex, name in
                let rgb = RGBAColor(hex: hex) ?? RGBAColor(r: 0, g: 0, b: 0)
                let active = currentHex?.uppercased() == hex.uppercased()
                Button {
                    onSelect(hex)
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                        .frame(width: 18, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(active ? Theme.accent.swiftUI : Color.white.opacity(0.25), lineWidth: active ? 2.0 : 0.8)
                        )
                }
                .buttonStyle(.plain)
                .help("\(name) (\(hex))")
            }
        }
    }

    private func coordBadge(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textFaint.swiftUI)
            Text("\(value)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.text.swiftUI)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)))
    }

    private func proportionalSizeSlider(for el: VectorElement) -> some View {
        let ctrl = model.controller
        return HStack(spacing: 8) {
            Text(L("Taille", "Size"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textDim.swiftUI)
                .frame(width: 52, alignment: .leading)
            Slider(
                value: Binding(
                    get: { el.frame.width },
                    set: { newW in
                        VectorOperations.updateElement(id: el.id, onPage: ctrl.currentPageIndex, in: &ctrl.document) { item in
                            let aspect = max(0.05, item.frame.width / max(1.0, item.frame.height))
                            let w = max(24.0, newW)
                            let h = max(12.0, w / aspect)
                            let midX = item.frame.midX
                            let midY = item.frame.midY
                            item.frame = VectorRect(x: midX - w * 0.5, y: midY - h * 0.5, width: w, height: h)
                        }
                    }
                ),
                in: 36...420
            )
            .tint(Theme.accent.swiftUI)
            Text("\(Int(round(el.frame.width))) pt")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.text.swiftUI)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

private struct SignatureMiniPreview: View {
    let preset: SignaturePreset

    var body: some View {
        if let assetData = preset.assetData, !assetData.isEmpty,
           let nsImg = VectorSceneRenderCache.shared.assetImage(
               for: assetData,
               ext: preset.assetExtension,
               removeWhiteBackground: preset.removeWhiteBackground
           ) {
            Image(nsImage: nsImg)
                .resizable()
                .scaledToFit()
                .padding(2)
        } else {
            Canvas { ctx, size in
                let rgb = RGBAColor(hex: preset.colorHex) ?? RGBAColor(r: 0.12, g: 0.23, b: 0.54)
                var path = Path()
                for stroke in preset.strokes where !stroke.isEmpty {
                    path.move(to: CGPoint(x: stroke[0].x * size.width, y: stroke[0].y * size.height))
                    for pt in stroke.dropFirst() {
                        path.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
                    }
                }
                ctx.stroke(path, with: .color(Color(red: rgb.r, green: rgb.g, blue: rgb.b)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct StampMiniPreview: View {
    let preset: StampPreset

    var body: some View {
        if let nsImg = VectorSceneRenderCache.shared.assetImage(
            for: preset.assetData,
            ext: preset.assetExtension,
            removeWhiteBackground: preset.removeWhiteBackground
        ) {
            Image(nsImage: nsImg)
                .resizable()
                .scaledToFit()
                .padding(2)
        } else {
            Image(systemName: "seal")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent.swiftUI)
        }
    }
}
