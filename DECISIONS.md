# DECISIONS — SimpleVector

Journal des choix structurants : contexte, décision, ce qui a été écarté. Toutes les décisions initiales ont été prises le 26 octobre 2026 à partir de la demande d'Adrien (« SimpleVector serait une application des SimpleApps permettant d'ouvrir les svg et pdf et de les éditer et de les sauver. On peut éditer le texte des pdf qui ont du texte, signer, rajouter des éléments, en mode multipage aussi. Tout est très optimisé, simple fluide rapide et élégant. »).

---

## Modèle vectoriel, PDF éditable et SVG multipage

- **D1 — Modèle de document multipage unifié (`VectorDocument`) hybride PDF + SVG.**
  - **Contexte** : L'application doit ouvrir aussi bien un plan de feu `.svg` qu'un contrat ou une fiche technique `.pdf` multipage, permettre d'éditer les textes, de signer, d'ajouter des éléments ou des pages et d'exporter le résultat en `.pdf`, `.svg` ou `.png`.
  - **Décision** : `VectorDocument` contient une liste ordonnée de `VectorPage`. Chaque page possède ses dimensions en points (`595×842 pt` A4 portrait, `842×595 pt` A4 paysage, etc.), un flux PDF vectoriel optionnel par page (`pdfPageData: Data?`) et une pile d'éléments vectoriels typés (`VectorElementKind` : `.text`, `.path`, `.shape`, `.signature`, `.stamp`) en coordonnées page haut-gauche (`0…width`, `0…height`).
  - **Écarté** : Deux modèles séparés (un mode PDF non vectoriel type Aperçu et un mode SVG séparé) qui empêcheraient de combiner pages PDF et pages SVG ou de convertir un PDF annoté en SVG multipage.

- **D2 — Édition directe du texte intégré aux PDF par extraction `PDFSelection`, analyse bitmap `2x` (`PDFPageBitmapAnalyzer`) et masquage vectoriel à la demande (`activeMaskRects`).**
  - **Contexte** : Réécrire à la volée le flux d'opérateurs PostScript/PDF interne (`BT ... Tj ET`) d'un PDF existant se heurte aux sous-jeux de polices embarquées (subset fonts où seuls les glyphes présents dans le document initial existent). À l'inverse, masquer naïvement la boîte `PDFSelection.bounds` en blanc `#FFFFFF` et redessiner en `Helvetica Neue` crée un rectangle blanc visible lorsque le texte est posé sur un encadré grisé/coloré (p. ex. courrier Urssaf) et modifie la police et la ligne de base.
  - **Décision** : Lors de l'import (`PDFCodec.importPDF`), chaque page conserve son flux vectoriel `PDFPage.dataRepresentation` intact, découpe les lignes multi-colonnes (écart horizontal `> 1,65 × hauteur`), lit le `CTFont` exact (`postScriptFontName` sans préfixe de sous-jeu `ABCDEF+`, `fontFamily`, `CTFontGetSize`, gras/italique) dans `PDFSelection.attributedString`, et analyse un rendu `2x` sRGB de la page (`PDFPageBitmapAnalyzer`) pour mesurer : (1) la couleur de fond exacte sous le texte (`maskColorHex`, 78ᵉ centile de luminance de la boîte), (2) la couleur d'encre exacte (`originalTextColorHex`), (3) le rectangle d'encre serré (`tightInkRect`), et (4) la position exacte de la ligne de base (`baselineY`). Tant qu'une ligne n'est pas modifiée (`!el.hasModifiedPDFText`), le PDF original est affiché sans surcouche. Dès qu'elle est éditée, seul `tightInkRect` est masqué avec `maskColorHex` et le nouveau texte est tracé avec le même `CTFont` et sur la même ligne de base à l'écran (`CanvasViewportView`) comme à l'export (`PDFCodec.exportPDF`).
  - **Écarté** : Masque `#FFFFFF` fixe (crée un artefact blanc sur les fonds gris ou colorés) ; rastérisation bitmap des pages PDF exportées.

- **D3 — Signatures calligraphiques vectorielles lissées (`StrokeSmoother`) et bibliothèque persistante.**
  - **Contexte** : Signer ou parapher un contrat, un bon de commande ou une fiche technique de tournée doit se faire en un clic (`S` ou bouton `Signer`) ou au trackpad, avec un tracé vectoriel propre qui ne pixellise jamais.
  - **Décision** : Les signatures (`SignaturePayload`) et tracés libres sont stockés en coordonnées normalisées `[0…1] × [0…1]` dans le cadre de l'élément (redimensionnables sans déformation), lissés par raffinement de coins de Chaikin (`StrokeSmoother.smooth`), accompagnés du nom du signataire, de sa fonction (`cie Adrien M`) et de la date du jour, et sauvegardés dans `~/Library/Application Support/SimpleVector/signatures.json`.
  - **Écarté** : Signatures enregistrées sous forme d'images PNG transparentes (pixellisation au zoom et dans les PDF).

- **D4 — Rendu 60–120 Hz ProMotion avec cache de géométrie (`VectorSceneRenderCache`) et frustum culling (G42, G46).**
  - **Contexte** : Un document multipage contenant des dizaines de blocs PDF, de tracés SVG et de signatures doit défiler et zoomer jusqu'à `600 %` sans aucune allocation de `Path` ni de `PDFDocument` par frame.
  - **Décision** : `VectorSceneRenderCache` pré-construit une seule fois les `Path` SwiftUI en coordonnées page par `(page.id, document.revision)` et les images de fond PDF haute résolution par `(page.id, pdfData.count)`. Le canevas (`Canvas(rendersAsynchronously: true)`) élimine les éléments hors champ (`visiblePageRect`) et projette chaque chemin via une unique `CGAffineTransform` (`geom.pageToPaneTransform`). Les transitions de cadrage (`Z` Réinitialiser la vue, `⇧Z` / `F` Cadrer tout ou la sélection) sont interpolées en quartique ease-out au taux de rafraîchissement natif de l'écran (`NSScreen.maximumFramesPerSecond`, jusqu'à 120 Hz) et s'arrêtent immédiatement à convergence (0 % CPU au repos).
  - **Écarté** : Reconstruction de `PDFDocument(data:)` ou de `Path` dans la fermeture `Canvas` à chaque frame.

- **D5 — Sérialisation SVG multipage compatible Inkscape (`<inkscape:page>`) et import SVG 1.1/2.0 sans dépendance externe.**
  - **Contexte** : Le standard SVG 1.1 est historiquement monopage, mais les plans techniques et documents annotés dans SimpleVector peuvent comporter plusieurs pages.
  - **Décision** : `SVGCodec.exportSVG` génère un SVG standard pour une page unique, et pour un document multipage utilise des groupes `<g id="page-N" inkscape:groupmode="layer" data-page-width="..." data-page-height="...">` accompagnés des déclarations `<inkscape:page>` dans `<sodipodi:namedview>`, ce qui permet une ré-ouverture fidèle page par page dans SimpleVector tout en restant lisible dans Inkscape et les navigateurs web.
  - **Écarté** : Dépendance à `librsvg` ou `cairo` (contraire à G9 / zéro dépendance externe).

- **D6 — Ports de la famille Simple (`x = 6`, G92) : HTTP `/v1` sur `127.0.0.1:17960`, OSC entrée `0.0.0.0:9160`, retour OSC `127.0.0.1:9161`.**
  - **Contexte** : SimpleVector s'intègre à l'écosystème de régie de la cie Adrien M (API HTTP JSON `/v1`, serveur MCP `simplevector-mcp` embarqué dans `Contents/MacOS/` et pilotage OSC).
  - **Décision** : Attribution du créneau `x = 6` dans `SimpleFamily/GUIDELINES.md` (G92).

---

## Remis à plus tard

- Édition booléenne de chemins de Bézier (union, soustraction, intersection de formes).
- Signature cryptographique X.509 / PAdES par certificat matériel à puce (la signature vectorielle calligraphique et l'aplatissement PDF vectoriel couvrent tous les besoins de validation et de paraphage de la compagnie).

---

## Mesures

- **Binaire `SimpleVector` (release, arm64)** : **3,6 Mo** (contre > 1,5 Go pour Adobe Acrobat / Illustrator ou ~380 Mo pour Inkscape).
- **Binaire `simplevector-mcp` (release, arm64)** : **168 Ko**.
- **Bundle `SimpleVector.app` complet signé** : **4,3 Mo** (règle G41 : binaire < 5 Mo, `.app` < 10 Mo).
- **Exécution complète de la suite `swift test` (5 suites Core + App + MCP)** : **75 ms**.
- **Import d'un PDF multipage + extraction des lignes de texte éditables** : **< 18 ms**.
