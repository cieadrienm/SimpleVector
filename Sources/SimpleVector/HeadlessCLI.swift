import Foundation
import SimpleVectorCore

/// Command-line interface for headless inspection, PDF/SVG text editing, signing, and conversion (G90).
@MainActor
enum HeadlessCLI {
    static func printHelpAndExit() -> Never {
        let help = L(
            """
            \(AppVersion.current.cliLine) — Éditeur vectoriel SVG & PDF multipage (cie Adrien M)

            Usage :
              SimpleVector [options] [fichier.svg | fichier.pdf]

            Options communes :
              --version, -v                 Affiche la version et quitte
              --help, -h                    Affiche cette aide et quitte
              --self-test                   Exécute les auto-tests de bout en bout (SVG, PDF, texte, signature, multipage)
              --snapshot <png> [--view <v>] Rend la fenêtre hors écran en PNG (single, multipage, grid, plot, about, help, shortcuts, settings, osc)
              --lang fr|en                  Force la langue d'interface pour cette exécution

            Options métier :
              --info <fichier> [--format txt|csv|json]
                                            Inspecte les pages, dimensions et textes éditables d'un fichier SVG ou PDF
              --convert <entrée> --output <sortie.pdf|svg|png> [--sign <nom>] [--stamp <approved|signed|stagePlot>]
                                            Convertit, signe ou annote un document SVG/PDF en ligne de commande
            """,
            """
            \(AppVersion.current.cliLine) — Multi-page SVG & PDF vector editor (cie Adrien M)

            Usage:
              SimpleVector [options] [file.svg | file.pdf]

            Common flags:
              --version, -v                 Print version and exit
              --help, -h                    Print this help and exit
              --self-test                   Run end-to-end self-tests (SVG, PDF, text, signature, multi-page)
              --snapshot <png> [--view <v>] Render offscreen window to PNG (single, multipage, grid, plot, about, help, shortcuts, settings, osc)
              --lang fr|en                  Force UI language for this run

            Domain flags:
              --info <file> [--format txt|csv|json]
                                            Inspect pages, dimensions, and editable text blocks of an SVG or PDF file
              --convert <input> --output <output.pdf|svg|png> [--sign <name>] [--stamp <approved|signed|stagePlot>]
                                            Convert, sign, or stamp an SVG/PDF document from the command line
            """
        )
        print(help)
        exit(0)
    }

    static func runInfoAndExit(arguments: [String]) -> Never {
        let format = value(after: "--format", in: arguments)?.lowercased() ?? "txt"
        let fileArg = arguments.first { !$0.hasPrefix("-") }
        let ctrl = VectorController(startServices: false, persistEnabled: false)
        if let fileArg {
            let url = URL(fileURLWithPath: (fileArg as NSString).expandingTildeInPath)
            do {
                try ctrl.openFile(at: url)
            } catch {
                fputs("error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        let doc = ctrl.document
        switch format {
        case "json":
            let dict: [String: Any] = [
                "title": doc.title,
                "sourceFormat": doc.sourceFormat.rawValue,
                "pageCount": doc.pages.count,
                "totalElementsCount": doc.totalElementsCount,
                "pdfTextElementCount": doc.pdfTextElementCount,
                "signatureCount": doc.signatureCount,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
        case "csv":
            print("page,title,width_pt,height_pt,elements,pdf_stream")
            for (idx, p) in doc.pages.enumerated() {
                print("\(idx + 1),\"\(p.title)\",\(Int(round(p.width))),\(Int(round(p.height))),\(p.elements.count),\(p.pdfPageData != nil)")
            }
        default:
            print("\(doc.title) (\(doc.sourceFormat.rawValue)) — \(doc.pages.count) pages · \(doc.totalElementsCount) éléments · \(doc.pdfTextElementCount) textes PDF")
            for (idx, p) in doc.pages.enumerated() {
                print("  Page \(idx + 1): \(p.title) — \(p.dimensionsLabel) — \(p.elements.count) éléments")
            }
        }
        exit(0)
    }

    static func runConvertAndExit(arguments: [String]) -> Never {
        guard let inputPath = arguments.first(where: { !$0.hasPrefix("-") }),
              let outputPath = value(after: "--output", in: arguments) else {
            fputs("error: --convert requires <input> and --output <output.pdf|svg|png>\n", stderr)
            exit(1)
        }
        let ctrl = VectorController(startServices: false, persistEnabled: false)
        do {
            if inputPath != "demo" {
                let inURL = URL(fileURLWithPath: (inputPath as NSString).expandingTildeInPath)
                try ctrl.openFile(at: inURL)
            }
            if let rIdx = arguments.firstIndex(of: "--replace-text"), rIdx + 2 < arguments.count {
                let match = arguments[rIdx + 1]
                let replacement = arguments[rIdx + 2]
                ctrl.perform { doc in
                    var foundExact = false
                    for pIdx in doc.pages.indices {
                        for el in doc.pages[pIdx].elements {
                            if case .text(let t) = el.kind, t.text.trimmingCharacters(in: .whitespacesAndNewlines) == match {
                                foundExact = true
                                VectorOperations.updateElement(id: el.id, onPage: pIdx, in: &doc) { target in
                                    if case .text(var tp) = target.kind {
                                        tp.text = replacement
                                        target.kind = .text(tp)
                                        PDFCodec.updateTextFrameForEditedContent(&target)
                                    }
                                }
                            }
                        }
                    }
                    guard !foundExact else { return }
                    for pIdx in doc.pages.indices {
                        for el in doc.pages[pIdx].elements {
                            if case .text(let t) = el.kind, t.text.localizedCaseInsensitiveContains(match) {
                                VectorOperations.updateElement(id: el.id, onPage: pIdx, in: &doc) { target in
                                    if case .text(var tp) = target.kind {
                                        tp.text = replacement
                                        target.kind = .text(tp)
                                        PDFCodec.updateTextFrameForEditedContent(&target)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if let signer = value(after: "--sign", in: arguments) {
                let preset = SignaturePreset(
                    title: signer,
                    signerName: signer,
                    caption: "cie Adrien M",
                    colorHex: "#1E3A8A",
                    strokes: SignaturePreset.calligraphicStrokes(seed: signer.count)
                )
                let el = VectorOperations.makeSignatureElement(
                    preset: preset,
                    at: VectorPoint(x: ctrl.currentPage.width * 0.68, y: ctrl.currentPage.height * 0.82)
                )
                ctrl.perform { doc in
                    VectorOperations.addElement(el, toPage: ctrl.currentPageIndex, in: &doc)
                }
            }
            if let stampRaw = value(after: "--stamp", in: arguments),
               let kind = VectorStampKind(rawValue: stampRaw) {
                ctrl.stampApprovalBadge(kind: kind)
            }
            let outURL = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            try ctrl.saveFile(to: outURL)
            print("Saved to \(outURL.path)")
            exit(0)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }
}
