import Foundation

/// Generates synthetic multi-page vector & PDF documents for `--self-test`, `--snapshot`, and the demo mode (G36).
public enum SyntheticDocument {

    /// Builds a genuine 2-page PDF in memory with real PDF text streams, vector lines, and boxes,
    /// then imports it through `PDFCodec.importPDF` and adds a third SVG stage plot page, a calligraphic signature,
    /// and a « BON POUR ACCORD » stamp so all features (PDF text editing, signing, multipage, SVG/PDF) are exercised.
    public static func makeStageContractAndPlot() -> VectorDocument {
        if let rawPDF = try? generateSampleRawPDFData(),
           var doc = try? PDFCodec.importPDF(data: rawPDF, title: "Fiche Technique & Contrat Plateau — cie Adrien M") {
            // Page 1: Add a signature and an approved stamp on top of the imported PDF contract page
            if !doc.pages.isEmpty {
                doc.pages[0].title = L("1 · Contrat & Validation (PDF)", "1 · Contract & Approval (PDF)")
                // Edit one of the extracted PDF text lines to demonstrate live PDF text editing & masking
                if let statusIdx = doc.pages[0].elements.firstIndex(where: {
                    if case .text(let t) = $0.kind {
                        return t.text.contains("Statut :") || t.text.contains("Status:")
                    }
                    return false
                }) {
                    if case .text(var t) = doc.pages[0].elements[statusIdx].kind {
                        t.text = L("Statut : VALIDÉ & SIGNÉ POUR EXÉCUTION PLATEAU", "Status: APPROVED & SIGNED FOR STAGE EXECUTION")
                        t.isBold = true
                        doc.pages[0].elements[statusIdx].kind = .text(t)
                        doc.pages[0].elements[statusIdx].style.fillColorHex = "#0F766E"
                    }
                }

                let sigPreset = SignaturePreset.defaults[0]
                let sigEl = VectorOperations.makeSignatureElement(
                    preset: sigPreset,
                    at: VectorPoint(x: 420, y: 695),
                    includeDate: true
                )
                doc.pages[0].elements.append(sigEl)

                let stampEl = VectorOperations.makeStampElement(
                    kind: .approved,
                    at: VectorPoint(x: 185, y: 695)
                )
                doc.pages[0].elements.append(stampEl)
            }

            if doc.pages.count > 1 {
                doc.pages[1].title = L("2 · Patch & Conduite Régie (PDF)", "2 · Patch & Stage Cue Sheet (PDF)")
                let paraphPreset = SignaturePreset.defaults[1]
                let paraphEl = VectorOperations.makeSignatureElement(
                    preset: paraphPreset,
                    at: VectorPoint(x: 465, y: 720),
                    includeDate: true
                )
                doc.pages[1].elements.append(paraphEl)
            }

            // Page 3: Pure SVG Stage Plot page (Landscape A4)
            let plotPage = makeStagePlotPage()
            doc.pages.append(plotPage)
            doc.revision = 1
            return doc
        }
        return VectorDocument(
            title: "Fiche Technique & Plan de Feu — cie Adrien M",
            sourceFormat: .pdf,
            pages: [makeStagePlotPage()]
        )
    }

    /// Generates raw multi-page PDF bytes with real embedded PDF text streams so `PDFCodec.importPDF` extracts real PDF text lines.
    public static func generateSampleRawPDFData() throws -> Data {
        var page1 = VectorPage(
            title: "Page 1",
            width: 595.28,
            height: 841.89,
            backgroundColorHex: "#FFFFFF"
        )
        // Header banner
        page1.elements.append(VectorElement(
            name: "Bandeau en-tête",
            kind: .shape(ShapePayload(shapeType: .roundedRectangle, cornerRadius: 6)),
            frame: VectorRect(x: 42, y: 38, width: 511, height: 64),
            style: VectorStyle(strokeColorHex: "#111317", fillColorHex: "#F4F6F9", strokeWidth: 1.4)
        ))
        page1.elements.append(VectorOperations.makeTextElement(
            text: "CIE ADRIEN M — FICHE DE VALIDATION TECHNIQUE",
            at: VectorPoint(x: 58, y: 50),
            fontSize: 16,
            colorHex: "#111317",
            isBold: true
        ))
        page1.elements.append(VectorOperations.makeTextElement(
            text: "Compagnie Adrien M · Direction technique & Régie plateau · adrien-m.net",
            at: VectorPoint(x: 58, y: 74),
            fontSize: 10.5,
            colorHex: "#4B5563",
            isBold: false
        ))

        let linesPage1: [(String, Double, Bool)] = [
            (L("1. IDENTIFICATION DU SPECTACLE & DU LIEU", "1. PRODUCTION & VENUE IDENTIFICATION"), 132, true),
            (L("Production : Spectacle vivant — tournée 2026 / cie Adrien M", "Production: Live performance — 2026 tour / cie Adrien M"), 158, false),
            (L("Plateau : Ouverture 14,0 m × Profondeur 12,0 m × Hauteur sous gril 8,5 m", "Stage: Opening 14.0 m × Depth 12.0 m × Grid height 8.5 m"), 180, false),
            (L("Statut : En attente de relecture et signature technique", "Status: Awaiting technical review and signature"), 202, false),
            (L("2. ÉQUIPEMENT VIDÉO, AUDIO & RÉSEAU DE RÉGIE", "2. VIDEO, AUDIO & SHOW CONTROL NETWORK"), 246, true),
            (L("Vidéoprojection : 4 × Laser 12 000 lm en PJLink Classe 2 (192.168.1.21–24)", "Projection: 4 × 12,000 lm Laser PJLink Class 2 (192.168.1.21–24)"), 272, false),
            (L("Diffusion sonore : Système multipoints + retour plateau (48 kHz / 24 bits)", "Sound system: Multi-channel PA + stage monitors (48 kHz / 24-bit)"), 294, false),
            (L("Synchronisation : OSC UDP (:9160) · eMotion · OSCScore · SimpleAudio", "Sync: OSC UDP (:9160) · eMotion · OSCScore · SimpleAudio"), 316, false),
            (L("3. NOTES MODIFIABLES DIRECTEMENT DANS LE PDF", "3. DIRECTLY EDITABLE PDF NOTES"), 360, true),
            (L("Cliquer sur n'importe quelle ligne de ce PDF avec l'outil Texte (T) ou Sélection (V)", "Click any line of this PDF with the Text (T) or Select (V) tool to edit it"), 386, false),
            (L("pour corriger une cote, un horaire, une adresse IP ou apposer une signature.", "to update a dimension, schedule, IP address, or place a signature."), 406, false),
        ]
        for (txt, y, bold) in linesPage1 {
            page1.elements.append(VectorOperations.makeTextElement(
                text: txt,
                at: VectorPoint(x: 48, y: y),
                fontSize: bold ? 12.5 : 11.0,
                colorHex: "#111317",
                isBold: bold
            ))
        }

        // Embedded technical mini diagram on Page 1
        page1.elements.append(VectorElement(
            name: "Cadre schéma plateau",
            kind: .shape(ShapePayload(shapeType: .roundedRectangle, cornerRadius: 6)),
            frame: VectorRect(x: 48, y: 445, width: 500, height: 170),
            style: VectorStyle(strokeColorHex: "#9CA3AF", fillColorHex: "#F9FAFB", strokeWidth: 1.2)
        ))
        page1.elements.append(VectorElement(
            name: "Tapis de danse",
            kind: .shape(ShapePayload(shapeType: .rectangle)),
            frame: VectorRect(x: 138, y: 470, width: 320, height: 118),
            style: VectorStyle(strokeColorHex: "#1E3A8A", fillColorHex: "#DBEAFE", strokeWidth: 1.6)
        ))
        page1.elements.append(VectorOperations.makeTextElement(
            text: L("AIRE DE JEU — 10,0 m × 8,0 m (Tapis blanc / gris)", "PERFORMANCE AREA — 10.0 m × 8.0 m (White / grey marley)"),
            at: VectorPoint(x: 168, y: 520),
            fontSize: 10.5,
            colorHex: "#1E3A8A",
            isBold: true
        ))

        // Signature box frame at bottom of Page 1
        page1.elements.append(VectorElement(
            name: "Cartouche signature",
            kind: .shape(ShapePayload(shapeType: .roundedRectangle, cornerRadius: 6)),
            frame: VectorRect(x: 48, y: 642, width: 500, height: 118),
            style: VectorStyle(strokeColorHex: "#D1D5DB", fillColorHex: "#FFFFFF", strokeWidth: 1.2, dashed: true)
        ))
        page1.elements.append(VectorOperations.makeTextElement(
            text: L("VISA & SIGNATURE DIRECTION TECHNIQUE (cie Adrien M) :", "TECHNICAL DIRECTOR VISA & SIGNATURE (cie Adrien M):"),
            at: VectorPoint(x: 62, y: 654),
            fontSize: 10.0,
            colorHex: "#4B5563",
            isBold: true
        ))

        // Page 2: Patch & Cue sheet
        var page2 = VectorPage(
            title: "Page 2",
            width: 595.28,
            height: 841.89,
            backgroundColorHex: "#FFFFFF"
        )
        let linesPage2: [(String, Double, Bool)] = [
            (L("ANNEXE — PATCH RÉSEAU & CONDUITE D'INSTALLATION", "APPENDIX — NETWORK PATCH & RIGGING SCHEDULE"), 52, true),
            (L("Ligne 1 : Pont Face — 2 × Vidéoprojecteurs Cour / Jardin (Optique 0.8:1)", "Line 1: Front Truss — 2 × Projectors Left / Right (0.8:1 Lens)"), 96, false),
            (L("Ligne 2 : Pont Contre — 1 × Vidéoprojecteur Cyclo + 2 × Caméras IR", "Line 2: Upstage Truss — 1 × Cyclo Projector + 2 × IR Cameras"), 120, false),
            (L("Ligne 3 : Régie Salle — Switch Gigabit VLAN 10 (Art-Net / PJLink / OSC)", "Line 3: FOH Control — Gigabit Switch VLAN 10 (Art-Net / PJLink / OSC)"), 144, false),
            (L("Horaire montage : 09h00 Accrochage · 14h00 Focus & Calibrage · 18h00 Filage", "Schedule: 09:00 Rigging · 14:00 Focus & Calibration · 18:00 Run-through"), 184, false),
            (L("Responsable régie : Adrien Mondot · cie Adrien M", "Stage lead: Adrien Mondot · cie Adrien M"), 220, true),
        ]
        for (txt, y, bold) in linesPage2 {
            page2.elements.append(VectorOperations.makeTextElement(
                text: txt,
                at: VectorPoint(x: 48, y: y),
                fontSize: bold ? 13.0 : 11.0,
                colorHex: "#111317",
                isBold: bold
            ))
        }

        let seedDoc = VectorDocument(
            title: "Contrat Technique cie Adrien M",
            sourceFormat: .pdf,
            pages: [page1, page2]
        )
        return try PDFCodec.exportPDF(document: seedDoc)
    }

    /// Builds a rich vector SVG stage plot page (Page 3 of the synthetic document).
    public static func makeStagePlotPage() -> VectorPage {
        var page = VectorPage(
            title: L("3 · Plan de Feu Plateau (SVG)", "3 · Stage Lighting & Video Plot (SVG)"),
            width: 841.89,
            height: 595.28,
            backgroundColorHex: "#FFFFFF"
        )

        // Outer border
        page.elements.append(VectorElement(
            name: L("Cadre de planche A4 Paysage", "A4 Landscape Title Block"),
            kind: .shape(ShapePayload(shapeType: .roundedRectangle, cornerRadius: 8)),
            frame: VectorRect(x: 28, y: 28, width: 785.89, height: 539.28),
            style: VectorStyle(strokeColorHex: "#111317", fillColorHex: "#F8FAFC", strokeWidth: 1.8)
        ))

        // Stage area rectangle
        page.elements.append(VectorElement(
            name: L("Plateau / Tapis de danse", "Stage / Marley Floor"),
            kind: .shape(ShapePayload(shapeType: .rectangle)),
            frame: VectorRect(x: 150, y: 92, width: 540, height: 340),
            style: VectorStyle(strokeColorHex: "#1E3A8A", fillColorHex: "#EFF6FF", strokeWidth: 2.0)
        ))

        // Cyclorama line at top
        page.elements.append(VectorElement(
            name: L("Cyclorama fond de scène", "Upstage Cyclorama"),
            kind: .shape(ShapePayload(shapeType: .roundedRectangle, cornerRadius: 3)),
            frame: VectorRect(x: 170, y: 108, width: 500, height: 14),
            style: VectorStyle(strokeColorHex: "#0F766E", fillColorHex: "#99F6E4", strokeWidth: 1.6)
        ))

        // 3 Projectors on front truss
        let vpX: [(String, String, Double)] = [
            (L("VP 1 — Jardin (Panasonic PT-RQ25K)", "VP 1 — Stage Left"), "VP 1", 210),
            (L("VP 2 — Centre (Panasonic PT-RQ25K)", "VP 2 — Center"), "VP 2", 396),
            (L("VP 3 — Cour (Panasonic PT-RQ25K)", "VP 3 — Stage Right"), "VP 3", 582),
        ]
        for (label, shortCode, x) in vpX {
            page.elements.append(VectorElement(
                name: label,
                kind: .shape(ShapePayload(shapeType: .roundedRectangle, cornerRadius: 4)),
                frame: VectorRect(x: x, y: 374, width: 50, height: 30),
                style: VectorStyle(strokeColorHex: "#B45309", fillColorHex: "#FFB454", strokeWidth: 1.8)
            ))
            page.elements.append(VectorOperations.makeTextElement(
                text: shortCode,
                at: VectorPoint(x: x + 11, y: 382),
                fontSize: 10.5,
                colorHex: "#111317",
                isBold: true
            ))
            page.elements.append(VectorElement(
                name: "\(label) — Faisceau",
                kind: .shape(ShapePayload(shapeType: .arrow, endArrow: true)),
                frame: VectorRect(x: x + 22, y: 140, width: 12, height: 228),
                style: VectorStyle(strokeColorHex: "#D97706", fillColorHex: nil, strokeWidth: 1.8, dashed: true)
            ))
        }

        // FOH Control booth at bottom
        page.elements.append(VectorElement(
            name: L("Régie Plateau (SimpleVector / SimplePJ / SimpleAudio)", "FOH Control Booth"),
            kind: .shape(ShapePayload(shapeType: .roundedRectangle, cornerRadius: 6)),
            frame: VectorRect(x: 240, y: 462, width: 360, height: 54),
            style: VectorStyle(strokeColorHex: "#111317", fillColorHex: "#E2E8F0", strokeWidth: 1.6)
        ))
        page.elements.append(VectorOperations.makeTextElement(
            text: L("RÉGIE PLATEAU — cie Adrien M (OSC :9160 · PJLink :4352)", "FOH CONTROL — cie Adrien M (OSC :9160 · PJLink :4352)"),
            at: VectorPoint(x: 266, y: 482),
            fontSize: 11.0,
            colorHex: "#111317",
            isBold: true
        ))

        // Stage stamp in corner
        page.elements.append(VectorOperations.makeStampElement(
            kind: .stagePlot,
            at: VectorPoint(x: 695, y: 495)
        ))

        return page
    }
}
