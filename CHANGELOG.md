# Changelog

La version de SimpleVector vit à un seul endroit : `VERSION` dans `Scripts/bundle.sh` (G110).
Correctif : `x.y.Z` ; fonction : `x.Y.0` ; rupture : `X.0.0`.

## 0.2.3 — 2026-10-27

- **Signature `Developer ID Application` en Hardened Runtime, notarisation Apple (`notarytool` + `stapler`) et compatibilité macOS 14 Sonoma → macOS 26 Tahoe** (`Scripts/bundle.sh`, `Package.swift`, `SimpleUpdater`) :
  - **Résolution du rejet Gatekeeper sur les versions récentes de macOS** : `Scripts/bundle.sh` sélectionne désormais l'empreinte SHA-1 exacte du certificat `Developer ID Application: Adrien Mondot (KJ2CG4YTE4)` (évitant l'erreur `codesign: ambiguous` lorsqu'un certificat figure en double dans le trousseau et le repli sur `Apple Development` ou ad-hoc `-`), signe en Hardened Runtime (`--options runtime --timestamp`) et agrafe le ticket de notarisation Apple (`spctl -a` : `accepted, source=Notarized Developer ID`).
  - **Cible de déploiement `macOS 14.0+` (`LSMinimumSystemVersion = 14.0`)** : compatibilité native de macOS 14 Sonoma à macOS 15 Sequoia et macOS 26 Tahoe.
  - **Transition de Team ID dans `SimpleUpdater`** : autorise la mise à jour transparente des installations initiales (`A4Z547XTDF`) vers les versions signées et notarisées `Developer ID` (`KJ2CG4YTE4`).

## 0.2.2 — 2026-10-27

- **Redimensionnement strictement proportionnel des signatures et des tampons** (`CanvasViewportView`, `InspectorView`) :
  - **Poignées de coin sur le canevas** : les signatures (`.signature`) et les tampons (`.stamp`) conservent désormais systématiquement leur ratio largeur/hauteur d'origine lors du redimensionnement par les poignées d'angle, y compris lorsque l'élément est incliné/tourné (le coin opposé reste ancré dans le repère de la page).
  - **Curseur de taille proportionnelle dans l'inspecteur** : ajout d'un curseur **Taille** (`36 … 420 pt`) dans la section **Géométrie, Rotation & Ordre** pour agrandir ou réduire une signature ou un tampon de manière homothétique autour de son centre.

## 0.2.1 — 2026-10-27

- **Retrait total de toute signature ou mention pré-embarquée au nom d'Adrien Mondot / cie Adrien M** (`VectorDocument`, `VectorOperations`, `VectorController`, `InspectorView`, `SVGCodec`, `HeadlessCLI`) :
  - `SignaturePreset.defaults` est désormais vide (`[]`) et l'ancien cache `UserDefaults` (`net.cieadrienm.simplevector.signatures`) est purgé au démarrage : aucune fausse signature (« Adrien Mondot », « Paraphe AM ») n'est présente dans le binaire distribué. Les signatures proviennent exclusivement du dossier `~/Library/Application Support/SimpleVector/Signatures/` ou des tracés créés par l'utilisateur.
  - Les tampons génériques (`StampPayload`) affichent uniquement la date du jour (`dd/MM/yyyy`) en sous-titre par défaut, sans mention de compagnie pré-remplie.

## 0.2.0 — 2026-10-26

- **Dossiers dédiés `Signatures` et `Tampons` (PDF, PNG, JPG, TIFF, HEIC, WebP, SVG), détourage automatique du fond papier blanc et rotation libre (`-180° … +180°`)** (`VectorDocument`, `AssetImageCodec`, `VectorController`, `CanvasViewportView`, `InspectorView`, `PDFCodec`, `SVGCodec`) :
  - **Dossiers `~/Library/Application Support/SimpleVector/Signatures/` et `~/Library/Application Support/SimpleVector/Stamps/`** : créés et scannés automatiquement au lancement (ainsi qu'en un clic via le bouton d'actualisation `↻`). Tout fichier `.pdf`, `.png`, `.jpg`, `.jpeg`, `.tiff`, `.tif`, `.heic`, `.webp` ou `.svg` déposé dans ces dossiers apparaît immédiatement dans l'inspecteur avec sa miniature.
  - **Import direct (`+ Fichier…`) et raccourci Finder (`folder`)** : dans les sections **Signatures** et **Tampons & Visas** de l'inspecteur (ainsi que dans le menu `Édition Vectorielle & PDF`), un bouton `+ Fichier…` ouvre un sélecteur macOS (`NSOpenPanel`) qui copie les fichiers choisis dans le dossier correspondant, et une icône dossier ouvre directement `Signatures/` ou `Stamps/` dans le Finder.
  - **Détourage intelligent du fond blanc (`AssetImageCodec.makeWhitePaperTransparent`)** : lorsqu'une signature ou un tampon provient d'un scan ou d'une photo sur papier blanc (`.jpg`, `.png`, ou `.pdf` scanné), SimpleVector rend automatiquement le papier blanc transparent, préserve la couleur et la densité de l'encre et recadre les marges blanches superflues (avec une case à cocher **« Détourer le fond blanc (mode encre) »** dans l'inspecteur pour activer/désactiver ce traitement par élément ; lorsqu'il est désactivé sur un fichier `.pdf`, le tampon/signature est exporté en `100 %` vectoriel natif via `CGContext.drawPDFPage`).
  - **Rotation libre sur le canevas et dans l'inspecteur (`rotationDegrees`)** :
    - **Poignée de rotation interactive sur le canevas** : chaque élément sélectionné affiche une poignée circulaire au-dessus de son bord supérieur permettant de le tourner librement à la souris ou au trackpad à 60–120 Hz autour de son centre (maintenir `⇧` aimante par pas de `15°`, avec affichage en direct de l'angle en degrés).
    - **Curseur et boutons rapides dans l'inspecteur** : curseur continu `-180° … +180°` accompagné des boutons rapides `-15°`, `0°`, `+15°` et `90°`, exporté fidèlement en PDF et en SVG.

## 0.1.5 — 2026-10-26

- **Extraction et enregistrement direct des polices embarquées dans le PDF (`PDFEmbeddedFontRegistry`)** (`PDFCodec`, `CanvasViewportView`, `InspectorView`) :
  - **Pourquoi la police changeait auparavant** : PDFKit utilise les flux binaires `/FontFile`, `/FontFile2` (TrueType) et `/FontFile3` (CFF/OpenType) embarqués dans le PDF pour dessiner la page originale, mais ne les enregistre pas dans `CTFontManager` sur macOS. Lorsque `PDFSelection.attributedString` ou `CTFontCreateWithName` cherchait une police absente du système (`Poppins-Medium`, `LEMONMILK-Bold`, `DMSerifDisplay-Regular`, `Calibri`…), macOS la remplaçait silencieusement par `Helvetica`.
  - **Extraction binaire `CGPDFDocument` avant `PDFSelection`** : avant d'analyser le texte, `PDFEmbeddedFontRegistry.shared.registerFonts(fromPDFData:)` parcourt les dictionnaires `/Resources -> /Font` (et les `Form XObjects`) de toutes les pages, extrait les flux `/FontFile2`, `/FontFile3` et `/FontFile`, retire sur place les préfixes de sous-ensemble `ABCDEF+` dans la table TrueType `name`, fusionne la table `/ToUnicode` dans une sous-table `cmap` Format 4 lorsque nécessaire, et enregistre la police dans le processus via `CTFontManagerRegisterFontsForURL`.
  - **Auto-complétion de l'alphabet complet (`~/Library/Application Support/SimpleVector/Fonts/`)** : lorsqu'un PDF n'embarque qu'un sous-jeu partiel (*subset*) d'une police ouverte (`Poppins`, `DM Serif Display`, `Montserrat`, `Roboto`, `Open Sans`, `Lato`, `Inter`, etc., où certaines lettres non utilisées dans le document initial manquent au sous-jeu), `PDFEmbeddedFontRegistry` récupère et met en cache localement le fichier `.ttf` complet (`100 %` des glyphes et accents).
  - **Synthèse vectorielle d'accents sur les sous-jeux propriétaires hors-ligne (`adaptStringForSubsetFont`)** : si une police propriétaire embarquée en sous-jeu (p. ex. `LEMONMILK-Bold`) ne contient pas une voyelle précomposée accentuée (`É`) mais contient la lettre de base (`E`), SimpleVector trace le `E` avec la vraie police embarquée du PDF et dessine l'accent vectoriel correspondant au-dessus du glyphe au lieu de retomber sur `Helvetica`.

## 0.1.4 — 2026-10-26

- **Segmentation verticale universelle par bandes d'encre (`PDFPageBitmapAnalyzer.analyzeTextRegion`) et fidélité multi-logiciels (Canva, Illustrator, InDesign, Word, LibreOffice)** :
  - **Isolation de la bande d'encre propre à chaque ligne** : dans de nombreux PDF générés par Canva, Illustrator ou avec des polices sous-ensemblées (*subset fonts* telles que `LEMONMILK-Bold`), la boîte `FontBBox` déclarée par la police déborde largement au-dessus et en dessous des glyphes réels (`27,7 pt` de haut pour un titre en `16,9 pt`) et recouvre la première ligne du paragraphe suivant. L'analyseur `2x` segmente désormais le profil horizontal d'encre ligne de pixels par ligne de pixels (`rowInkCount`), fusionne les signes diacritiques (`É`, `À`, `Î`, points sur `i`/`j`, cédilles) à l'intérieur d'une même ligne, pénalise les bandes tronquées issues des lignes voisines et fend automatiquement au creux d'encre (*valley splitting*) deux lignes rapprochées. Le masque `tightInkRect` et la ligne de base `baselineY` restent ainsi strictement confinés à la ligne éditée sans jamais mordre sur la ligne du dessous ni décaler le texte vers le bas.
  - **Conservation du flux PDF original sans re-sérialisation `PDFPage.dataRepresentation`** (`PDFCodec.importPDF`) : préservation de l'origine exacte du `mediaBox` (y compris lorsque `minY != 0`) et des caractères accentués précomposés Unicode sans décomposition NFD susceptible de décaler les plages `NSRange`.
  - **Maintien de l'intégrité des lignes contenant des apostrophes et détection optique de graisse (`appearsBold`)** : empêche `selectionsByLine()` de scinder une même ligne autour d'une apostrophe et détecte l'épaisseur médiane des fûts dans le bitmap lorsque PDFKit substitue une police système non grasse à une police embarquée Titrage/Bold.
  - **Sélection au clic plus précise sur les lignes rapprochées** (`CanvasViewportView.hitTestElement`) : priorité aux boîtes d'encre contenant directement le point cliqué et arbitrage par distance au centre vertical de la ligne.

## 0.1.3 — 2026-10-26

- **Déplacement fluide du canevas au scroll trackpad / molette (60–120 Hz)** (`CanvasViewportView`, `CanvasScrollEventMonitor`) :
  - Prise en charge directe du défilement à deux doigts au trackpad et à la molette (`NSEvent.EventTypeMask.scrollWheel`) sur le canevas pour déplacer la page horizontalement et verticalement, ainsi que du zoom centré sous le curseur avec `⌘ + scroll` ou `⌥ + scroll` et du glisser sur une zone vide avec l'outil Sélection (`V`).
- **Alignement horizontal exact (`0,00 pt`) lors de l'édition d'un texte PDF** (`PDFCodec.buildExtractedTextElement`) :
  - Conservation de l'origine typographique `X` exacte de la ligne PDF (`selX = pdfBounds.minX - mediaBox.minX`) et de la ligne de base `selTopY + CTFontGetAscent(ctFont)` au lieu du bord d'encre `minInkX`, éliminant le double ajout de l'approche gauche du premier glyphe (*Left Side Bearing*, `~0,70–0,95 pt` vers la droite sur un `'N'`).

## 0.1.2 — 2026-10-26

- **Menu `Fichier > Ouvrir récent` (`Open Recent`)** (`SimpleVectorApp`, `AppModel`) : ajout du sous-menu listant jusqu'à 12 documents `.pdf` ou `.svg` récemment ouverts ou enregistrés, synchronisé avec `NSDocumentController.shared` et `UserDefaults`, avec action **Effacer le menu**.
- **Démarrage sur document A4 vierge sans fichier démo** (`VectorController`, `SimpleVectorApp`, `TopBarAndStatusBar`) : lancement direct sur une page A4 Portrait vierge (`Sans titre`) et retrait des entrées « Charger la démo » des menus et de la barre d'outils (le générateur synthétique reste strictement réservé aux tests automatisés `--self-test`).

## 0.1.1 — 2026-10-26

- **Fidélité typographique et masquage sans artefact lors de l'édition de texte PDF** (`PDFCodec`, `PDFPageBitmapAnalyzer`, `CanvasViewportView`, `InspectorView`) :
  - **Échantillonnage automatique de la couleur de fond réelle sous le texte (`maskColorHex`)** : analyse bitmap `2x` en sRGB de chaque page PDF lors de l'import pour prélever la couleur exacte de l'arrière-plan sous chaque ligne (encadré gris `#EBEBEB`, bandeau coloré ou papier blanc `#FFFFFF`), éliminant tout rectangle blanc parasite sous un texte modifié dans un encadré coloré ou grisé.
  - **Boîte de masquage ajustée au plus près de l'encre (`tightInkRect`)** : détection au demi-point près des pixels d'encre réels de la ligne originale (`insetBy(dx: -0.6, dy: -0.5)`) au lieu de la boîte de sélection brute `PDFSelection`, évitant de déborder sous la ligne ou sur les filets adjacents.
  - **Conservation de la police, du corps, de la couleur d'encre et de la ligne de base (`baselineOffset`) du PDF** : lecture du `CTFont` natif (`postScriptFontName`, `fontFamily`, `CTFontGetSize`, gras/italique) dans `PDFSelection.attributedString`, alignement sous-pixel de la ligne de base (`baselineY`) entre `CanvasViewportView` (`Font(ctFont)`) et l'export `CoreText`, et découpage automatique des lignes multi-colonnes (p. ex. référence à gauche et date à droite sur la même hauteur).
- **Fenêtre Réglages (`PreferencesView`)** : correction du dimensionnement (`500 × 500 pt`, alignement haut) pour afficher intégralement l'en-tête **Langue & Mises à jour** et le pied **Réseau & Confidentialité** sans rognage.

## 0.1.0 — 2026-10-26

- Première version native macOS (`macOS 15`, SwiftPM pur sans dépendance externe) dédiée à l'ouverture, l'édition, la signature et l'enregistrement de documents `.svg` et `.pdf` monopages ou multipages :
  - **Édition directe du texte intégré aux PDF** (`PDFCodec`, `CanvasViewportView`, `InspectorView`) : détection automatique de toutes les lignes de texte d'un PDF (`PDFSelection.selectionsByLine()`), édition en place avec barre flottante rapide et inspecteur, masquage vectoriel automatique du texte original uniquement sur les blocs modifiés ou déplacés (`activeMaskRects`), bouton de restauration du texte PDF d'origine et ré-export en vrai PDF vectoriel (`CoreGraphics` + `CoreText`).
  - **Signatures calligraphiques & manuscrites** : bibliothèque de signatures vectorielles persistantes (`Adrien Mondot · cie Adrien M`, `Paraphe AM`, `Visa Régie Générale`), apposition en un clic (`S` ou bouton `Signer`), dessin de signature manuscrite à la volée au trackpad ou à la souris avec lissage de Chaikin (`StrokeSmoother`), datation automatique et enregistrement de nouvelles signatures dans la bibliothèque.
  - **Tampons de validation & Création d'éléments vectoriels** : 6 tampons vectoriels prêts à l'emploi (`BON POUR ACCORD`, `SIGNÉ & VALIDÉ`, `RÉGIE PLATEAU`, `CONFIDENTIEL`, `✓ CONFORME`, `VERSION DE TRAVAIL`) et outils complets (`Sélection V`, `Texte T`, `Signature S`, `Tracé P`, `Cadre R`, `Ellipse O`, `Flèche L`, `Tampon K`).
  - **Mode multipage complet** : barre latérale des vignettes de pages avec ajout (`⇧⌘N`), duplication (`⇧⌘D`), rotation 90°, réordonnancement et suppression ; 3 modes d'affichage (`Page unique ⌘1`, `Défilement continu multipage ⌘2`, `Planche contact en grille ⌘3`).
  - **Import / Export universel** : ouverture et enregistrement en `.pdf` vectoriel multipage, `.svg` (monopage standard ou multipage `<inkscape:page>`) et `.png` haute définition (`144 DPI`).
  - **Fluidité 60–120 Hz ProMotion & ergonomie SimpleFamily** : cache géométrique par révision (`VectorSceneRenderCache`), élimination hors champ (*frustum culling*), transitions fluides de cadrage (`Z` Réinitialiser la vue, `⇧Z` / `F` Cadrer tout ou la sélection), barres latérales animées (`⌥⌘S`, `⌥⌘I`), pile Annuler / Rétablir (`⌘Z` / `⇧⌘Z`) à 80 niveaux.
  - **Pilotage OSC, API HTTP `/v1`, serveur MCP & CLI sans tête** : écoute OSC UDP sur `:9160` (retour `:9161`), serveur HTTP JSON sur `127.0.0.1:17960/v1`, binaire `simplevector-mcp` (9 outils MCP sur `stdio`) et options CLI `--info`, `--sign`, `--replace-text`, `--export`, `--snapshot`, `--self-test`.
