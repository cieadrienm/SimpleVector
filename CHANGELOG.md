# Changelog

La version de SimpleVector vit à un seul endroit : `VERSION` dans `Scripts/bundle.sh` (G110).
Correctif : `x.y.Z` ; fonction : `x.Y.0` ; rupture : `X.0.0`.

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
