import AppKit
import Foundation
import SimpleVectorCore

/// End-to-end self-test verifying PDF import & text extraction, PDF text editing & masking,
/// calligraphic signature & stamp placement, multipage operations, SVG round-trip, undo/redo,
/// OSC codec, and offscreen PNG snapshot rendering (`SimpleVector --self-test`).
@MainActor
enum SelfTest {
    static func runAndExit() -> Never {
        var failures: [String] = []
        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("  [OK] \(name)")
            } else {
                print("  [FAIL] \(name)")
                failures.append(name)
            }
        }

        print("=== SimpleVector \(AppVersion.current.description) Self-Test ===")

        // 1. Synthetic PDF generation & import with editable text extraction
        let rawPDFData = try? SyntheticDocument.generateSampleRawPDFData()
        check("Generate sample multi-page vector PDF in memory", (rawPDFData?.count ?? 0) > 1000)

        if let rawPDFData, let pdfDoc = try? PDFCodec.importPDF(data: rawPDFData, title: "Test PDF") {
            check("Import 2-page PDF document", pdfDoc.pages.count == 2)
            check("Extract editable PDF text lines (> 10 blocks)", pdfDoc.pdfTextElementCount >= 10)
        } else {
            check("Import 2-page PDF document", false)
        }

        // 2. Controller & PDF text editing + vector masking + Undo/Redo
        let model = AppModel(startServices: false, persistEnabled: false)
        let ctrl = model.controller
        check("Demo document has 3 pages (2 PDF + 1 SVG plot)", ctrl.document.pages.count == 3)
        check("Demo document has modified PDF text with active mask", ctrl.document.modifiedPDFTextCount >= 1 && !ctrl.currentPage.activeMaskRects.isEmpty)

        let beforeSigCount = ctrl.document.signatureCount
        ctrl.stampActiveSignature(at: VectorPoint(x: 300, y: 500))
        check("Stamp calligraphic signature increments signatureCount", ctrl.document.signatureCount == beforeSigCount + 1)

        ctrl.undo()
        check("Undo removes stamped signature", ctrl.document.signatureCount == beforeSigCount)

        ctrl.redo()
        check("Redo restores stamped signature", ctrl.document.signatureCount == beforeSigCount + 1)

        // 3. Multipage operations
        let initialPages = ctrl.document.pages.count
        ctrl.addBlankPage(preset: .a4Landscape)
        check("Add blank page in multipage mode", ctrl.document.pages.count == initialPages + 1)
        ctrl.deleteCurrentPage()
        check("Delete page restores page count", ctrl.document.pages.count == initialPages)

        // 4. SVG Export & Re-import round-trip
        let exportedSVG = SVGCodec.exportSVG(document: ctrl.document)
        check("Export multi-page SVG contains <svg> and signature paths", exportedSVG.contains("<svg") && exportedSVG.contains("data-role=\"signature\""))
        if let reimportedSVG = try? SVGCodec.importSVG(string: exportedSVG, title: "Roundtrip SVG") {
            check("Re-import multi-page SVG preserves all 3 pages", reimportedSVG.pages.count == 3)
            check("Re-import SVG preserves vector elements", reimportedSVG.totalElementsCount >= 10)
        } else {
            check("Re-import multi-page SVG preserves all 3 pages", false)
        }

        // 5. Multi-page PDF export with edited text & signatures
        if let exportedPDF = try? PDFCodec.exportPDF(document: ctrl.document),
           let reimportedPDF = try? PDFCodec.importPDF(data: exportedPDF, title: "Roundtrip PDF") {
            check("Export & re-import multi-page PDF preserves page count", reimportedPDF.pages.count == 3)
        } else {
            check("Export & re-import multi-page PDF preserves page count", false)
        }

        // 6. OSC Codec round-trip
        let oscMsg = OSCCodec.Message(address: "/simplevector/sign", arguments: [.string("Adrien Mondot")])
        let decoded = OSCCodec.decode(OSCCodec.encode(oscMsg))
        check("OSC 1.0 encode/decode round-trip", decoded.first == oscMsg)

        // 7. Offscreen window snapshot
        let png = Snapshot.renderOffscreenPNG(model: model, size: CGSize(width: 960, height: 600))
        check("Offscreen window PNG snapshot (> 15 KB)", (png?.count ?? 0) > 15_000)

        if failures.isEmpty {
            print("=== ALL TESTS PASSED ===")
            exit(0)
        } else {
            fputs("=== FAILED (\(failures.count)): \(failures.joined(separator: ", ")) ===\n", stderr)
            exit(1)
        }
    }
}
