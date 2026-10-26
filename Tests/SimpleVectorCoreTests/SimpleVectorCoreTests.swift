import Foundation
import Testing
@testable import SimpleVectorCore

@Suite("SimpleVectorCore Tests")
struct SimpleVectorCoreTests {

    @Test("PDF generation, import, editable text extraction, and masking")
    func testPDFTextExtractionAndMasking() throws {
        let rawPDF = try SyntheticDocument.generateSampleRawPDFData()
        #expect(rawPDF.count > 1000)

        var doc = try PDFCodec.importPDF(data: rawPDF, title: "Contrat Test")
        #expect(doc.pages.count == 2)
        #expect(doc.pdfTextElementCount >= 10)
        #expect(doc.modifiedPDFTextCount == 0)

        // Modify the first extracted PDF text block
        let firstTextID = try #require(doc.pages[0].elements.first?.id)
        VectorOperations.updateElement(id: firstTextID, onPage: 0, in: &doc) { el in
            if case .text(var t) = el.kind {
                t.text = "TEXTE REMPLACÉ VECTORIEL"
                el.kind = .text(t)
            }
        }
        #expect(doc.modifiedPDFTextCount == 1)
        #expect(doc.pages[0].activeMaskRects.count == 1)

        // Export back to multi-page vector PDF and verify re-import
        let exportedPDF = try PDFCodec.exportPDF(document: doc)
        let reimported = try PDFCodec.importPDF(data: exportedPDF, title: "Reimported")
        #expect(reimported.pages.count == 2)
    }

    @Test("PDF text editing preserves font, gray box background mask, and multi-column layout without white artifacts")
    func testPDFGrayBoxMaskAndFontPreservation() throws {
        // Create a single-page PDF with a gray box (#EBEBEB) on the left containing Verdana 9pt lines,
        // a right-column date on the same horizontal row, and a blue header.
        var pagePage = VectorPage(title: "Courrier Test", width: 595.28, height: 841.89)
        pagePage.elements.append(VectorElement(
            name: "Encadré gris",
            kind: .shape(ShapePayload(shapeType: .rectangle)),
            frame: VectorRect(x: 42, y: 180, width: 220, height: 110),
            style: VectorStyle(strokeColorHex: nil, fillColorHex: "#EBEBEB", strokeWidth: 0)
        ))
        pagePage.elements.append(VectorElement(
            name: "Siret",
            kind: .text(TextPayload(text: "N° Siret : 81210337200015", fontFamily: "Verdana", postScriptFontName: "Verdana", fontSize: 9.0)),
            frame: VectorRect(x: 52, y: 232, width: 170, height: 12),
            style: VectorStyle(strokeColorHex: nil, fillColorHex: "#111317", strokeWidth: 0)
        ))
        pagePage.elements.append(VectorElement(
            name: "Compte",
            kind: .text(TextPayload(text: "N° Compte : 748 7200283419", fontFamily: "Verdana", postScriptFontName: "Verdana", fontSize: 9.0)),
            frame: VectorRect(x: 52, y: 246, width: 175, height: 12),
            style: VectorStyle(strokeColorHex: nil, fillColorHex: "#111317", strokeWidth: 0)
        ))
        pagePage.elements.append(VectorElement(
            name: "Date droite",
            kind: .text(TextPayload(text: "Limoges, le 27 avril 2026", fontFamily: "Verdana", postScriptFontName: "Verdana", fontSize: 9.5)),
            frame: VectorRect(x: 410, y: 246, width: 145, height: 12),
            style: VectorStyle(strokeColorHex: nil, fillColorHex: "#111317", strokeWidth: 0)
        ))
        pagePage.elements.append(VectorElement(
            name: "Objet bleu",
            kind: .text(TextPayload(text: "Objet : revenus - demande de déclaration", fontFamily: "Verdana", postScriptFontName: "Verdana-Bold", fontSize: 10.5, isBold: true)),
            frame: VectorRect(x: 44, y: 312, width: 280, height: 14),
            style: VectorStyle(strokeColorHex: nil, fillColorHex: "#004687", strokeWidth: 0)
        ))

        let sourceDoc = VectorDocument(title: "Source", pages: [pagePage])
        let rawPDFData = try PDFCodec.exportPDF(document: sourceDoc)

        var imported = try PDFCodec.importPDF(data: rawPDFData, title: "Imported")
        #expect(imported.modifiedPDFTextCount == 0)

        let compteEl = try #require(imported.pages[0].elements.first {
            if case .text(let t) = $0.kind { return t.text.contains("748 7200283419") }
            return false
        })

        // Verify multi-column separation: "Limoges" must NOT be merged into "N° Compte"
        if case .text(let t) = compteEl.kind {
            #expect(!t.text.contains("Limoges"))
            #expect(t.fontFamily == "Verdana")
            #expect(abs(t.fontSize - 9.0) < 0.8)
            // Verify sampled mask color is gray (~#EBEBEB), NOT white (#FFFFFF)
            #expect(t.maskColorHex != "#FFFFFF")
            let maskRGB = try #require(RGBAColor(hex: t.maskColorHex))
            #expect(abs(maskRGB.r - 0.92) < 0.05)
            #expect(abs(maskRGB.g - 0.92) < 0.05)
            #expect(abs(maskRGB.b - 0.92) < 0.05)
        }

        // Edit "N° Compte : 748 7200283419" -> "N° Compte : 748 7200283419 essai"
        VectorOperations.updateElement(id: compteEl.id, onPage: 0, in: &imported) { el in
            if case .text(var t) = el.kind {
                t.text = "N° Compte : 748 7200283419 essai"
                el.kind = .text(t)
                PDFCodec.updateTextFrameForEditedContent(&el)
            }
        }
        #expect(imported.modifiedPDFTextCount == 1)
        #expect(imported.pages[0].activeMaskRects.count == 1)
        #expect(imported.pages[0].activeMaskRects[0].colorHex != "#FFFFFF")
    }

    @Test("SVG multi-page export and re-import round-trip")
    func testSVGRoundTrip() throws {
        let doc = SyntheticDocument.makeStageContractAndPlot()
        #expect(doc.pages.count == 3)

        let svg = SVGCodec.exportSVG(document: doc)
        #expect(svg.contains("<svg"))
        #expect(svg.contains("data-multipage=\"true\""))
        #expect(svg.contains("data-role=\"signature\""))

        let reimported = try SVGCodec.importSVG(string: svg, title: "SVG Roundtrip")
        #expect(reimported.pages.count == 3)
        #expect(reimported.signatureCount >= 1)
    }

    @Test("Multipage operations and Undo/Redo history")
    func testMultipageOperationsAndHistory() {
        var doc = VectorDocument(title: "Test", pages: [VectorPage(title: "Page 1")])
        var history = VectorDocumentHistory()

        history.record(doc)
        let newIdx = VectorOperations.addPage(to: &doc, preset: .a4Landscape)
        #expect(newIdx == 1)
        #expect(doc.pages.count == 2)

        if let prev = history.undo(current: doc) {
            doc = prev
        }
        #expect(doc.pages.count == 1)

        if let next = history.redo(current: doc) {
            doc = next
        }
        #expect(doc.pages.count == 2)
    }

    @Test("OSC 1.0 codec and SimpleUpdater version comparison")
    func testOSCAndUpdater() {
        let msg = OSCCodec.Message(address: "/simplevector/sign", arguments: [.string("Adrien Mondot"), .int(1)])
        let encoded = OSCCodec.encode(msg)
        let decoded = OSCCodec.decode(encoded)
        #expect(decoded == [msg])

        #expect(SimpleUpdater.isNewer(candidateVersion: "0.2.0", thanVersion: "0.1.0"))
        #expect(!SimpleUpdater.isNewer(candidateVersion: "0.1.0", thanVersion: "0.1.0"))
    }
}
