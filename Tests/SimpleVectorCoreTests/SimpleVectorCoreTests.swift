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
