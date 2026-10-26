# SimpleVector — notes pour les agents

SimpleVector ouvre, édite, signe et enregistre les documents vectoriels `.svg` et `.pdf` en mode page unique ou multipage (édition directe des textes intégrés aux PDF avec masquage vectoriel automatique, signatures calligraphiques et manuscrites lissées, tampons de validation, formes vectorielles et export PDF/SVG/PNG). App de la famille Simple de la cie Adrien M. Adrien (spectacle vivant) est l'unique utilisateur ; il parle français.

## Lire d'abord
- `~/Programmation/SimpleFamily/GUIDELINES.md` — les règles communes de la famille (G1–G134).
- `DECISIONS.md` — D1–D6, le pourquoi de chaque choix. **Ajouter une entrée pour tout choix structurant.**
- `README.md` — fonctionnalités, ligne de commande, limites.

## Identité
- Bundle `net.cieadrienm.simplevector` ; ports HTTP `127.0.0.1:17960`, OSC entrée `0.0.0.0:9160`, OSC retour `127.0.0.1:9161` (G92, `x = 6`) ; dépôts `cieadrienm/SimpleVector` (GitHub) et `amcb/simplevector` (Gitea).

## Build et tests
    swift build / swift test
    .build/debug/SimpleVector --self-test
    .build/debug/SimpleVector --snapshot /tmp/simplevector.png [--view single|plot|multipage|grid|about|help|shortcuts|settings|osc|export]
    Scripts/bundle.sh [debug|release]

## Règles qui ont coûté cher
- **Ne jamais rastériser une page PDF lors d'une modification de texte ou d'une signature** (D1, D2) : `PDFCodec` conserve le flux `PDFPage.dataRepresentation` d'origine, extrait chaque ligne de texte avec ses coordonnées exactes (`PDFSelection.selectionsByLine()`) et n'applique un rectangle de masquage vectoriel (`activeMaskRects`) que sur les lignes effectivement modifiées ou déplacées avant de redessiner le texte de remplacement en `CoreText` vectoriel.
- **Ne jamais reconstruire les `Path` ni les aperçus `NSImage` des pages PDF dans la boucle de rendu 60–120 Hz** (D4, G46) : `VectorSceneRenderCache` met en cache les chemins par `(page.id, document.revision)` et les fonds PDF par `(page.id, pdfData.count)`.
- **Zéro `import AppKit` dans `SimpleVectorCore` et `SimpleVectorCoreTests`** (G30) : tout le décodage/encodage PDF et SVG repose sur `Foundation`, `PDFKit`, `CoreGraphics`, `CoreText` et `ImageIO`.

## Architecture en une minute
- `Sources/SimpleVectorCore/` — `VectorDocument.swift` (modèle de document multipage, pages, éléments `.text`, `.path`, `.shape`, `.signature`, `.stamp`, lisseur de Chaikin `StrokeSmoother`, `SignaturePreset`), `VectorOperations.swift` (opérations pures sur les pages et éléments + pile d'historique `VectorDocumentHistory`), `SVGCodec.swift` (parseur XML `XMLParser` SVG 1.1/2.0 et sérialiseur SVG simple ou multipage Inkscape), `PDFCodec.swift` (import PDF multipage avec extraction des lignes de texte éditables via `PDFKit`, masquage vectoriel des textes modifiés et export PDF vectoriel multipage `CGContext` + `CoreText`), `SyntheticDocument.swift`, `OSCAndHTTP.swift`, `Localization.swift`, `SimpleUpdater.swift`.
- `Sources/SimpleVectorMCPCore/` & `Sources/simplevector-mcp/` — serveur MCP stdio JSON-RPC 2.0 (9 outils) relayant vers HTTP `/v1` (`127.0.0.1:17960`).
- `Sources/SimpleVector/` — studio SwiftUI/AppKit (`Theme.swift`, `Components.swift`, `VectorController.swift`, `AppModel.swift` avec transitions caméra 60–120 Hz ProMotion `Z` / `⇧Z`, `Views/*`, `Snapshot.swift`, `SelfTest.swift`, `HeadlessCLI.swift`, `SimpleVectorApp.swift`).

## Invariants
- Tant qu'une ligne de texte extraite d'un PDF n'est ni modifiée ni déplacée (`!el.hasModifiedPDFText`), le glyphe vectoriel original du PDF est affiché directement sans masque ni doublon.
- Toute chaîne visible passe par `L("fr", "en")` avec un français impersonnel (ni « vous » ni « tu », G55) et les crédits mentionnent exclusivement `cie Adrien M` / `Compagnie Adrien M`.
