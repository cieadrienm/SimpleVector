# SimpleVector

**Éditeur vectoriel SVG & PDF multipage, édition de texte PDF et signature pour macOS.**  
Application native Swift / SwiftUI / PDFKit / CoreGraphics / CoreText, membre de la famille **Simple** ([cie Adrien M](https://www.adrien-m.net/software)).

---

## Fonctionnalités

- **Ouverture, édition et enregistrement natifs `.svg` et `.pdf`** :
  - Prise en charge transparente des fichiers **PDF** (contrats, fiches techniques, patchs de régie, bons de commande) et **SVG** (plans de feu, schémas d'implantation plateau, illustrations vectorielles), ainsi que du mélange de pages PDF et SVG dans un même document multipage.
- **Édition directe du texte des PDF existants** :
  - Extraction automatique de toutes les lignes de texte intégrées à chaque page PDF avec leur position, taille et police (`PDFSelection.selectionsByLine()`).
  - Clic direct sur n'importe quelle ligne du PDF avec l'outil **Sélection (`V`)** ou **Texte (`T`)** pour corriger un texte, un horaire, une cote ou un statut via la barre d'édition rapide ou l'inspecteur.
  - **Masquage vectoriel intelligent** : tant qu'une ligne PDF n'est pas touchée, les glyphes vectoriels d'origine du PDF sont conservés à l'identique ; dès qu'une ligne est modifiée ou déplacée, l'emplacement d'origine est proprement masqué et remplacé par un texte vectoriel `CoreText` net, avec possibilité de restaurer le texte PDF d'origine en un clic.
- **Signature vectorielle & Tampons de validation** :
  - **Bibliothèque de signatures calligraphiques** persistante (`Adrien Mondot`, `Paraphe AM`, `Visa Régie Générale`) avec apposition en un clic (`S` ou bouton **Signer**), nom du signataire, mention `cie Adrien M` et date du jour.
  - **Signature manuscrite directe** au trackpad ou à la souris avec lissage de courbes de Chaikin (`StrokeSmoother`) et enregistrement dans la bibliothèque.
  - **Tampons vectoriels** en un clic (`K`) : `BON POUR ACCORD`, `SIGNÉ & VALIDÉ`, `RÉGIE PLATEAU`, `CONFIDENTIEL`, `✓ CONFORME`, `VERSION DE TRAVAIL`.
- **Ajout et édition d'éléments vectoriels** :
  - 8 outils directs au clavier : **Sélection (`V`)**, **Texte (`T`)**, **Signature (`S`)**, **Tracé libre (`P`)**, **Cadre / Rectangle (`R`)**, **Ellipse (`O`)**, **Flèche / Cote (`L`)**, **Tampon (`K`)**.
  - Inspecteur complet : typographie (corps, gras, italique, alignement), couleurs d'encre et de remplissage, épaisseur de trait, pointillés, opacité, coordonnées exactes (`X, Y, L, H`), ordre d'empilement des calques et historique **Annuler / Rétablir (`⌘Z` / `⇧⌘Z`)**.
- **Mode multipage fluide** :
  - Trois vues complémentaires : **Page unique (`⌘1`)**, **Défilement continu multipage (`⌘2`)** et **Planche contact en grille (`⌘3`)** avec signature et sélection directe sur chaque page.
  - Gestion complète des pages dans la barre latérale : ajouter une page (`⇧⌘N`), dupliquer (`⇧⌘D`), pivoter de 90°, réordonner ou supprimer, et basculer entre les formats **A4 Portrait**, **A4 Paysage** et **16:9 Régie**.
- **Fluidité 60–120 Hz ProMotion** :
  - Cache géométrique par révision (`VectorSceneRenderCache`), élimination hors champ (*frustum culling*) et transitions de caméra cadencées jusqu'à 120 Hz (`Z` Réinitialiser la vue à 100 %, `⇧Z` / `F` Cadrer la sélection ou la page entière).

---

## Compilation & Installation

Prérequis : macOS 15+ et Swift 6.0+ (Xcode 16 ou Command Line Tools). Aucune dépendance externe.

```bash
# Compiler et exécuter la suite de tests
swift build
swift test

# Assembler, signer et installer SimpleVector.app dans /Applications
./Scripts/bundle.sh release

# Exécuter l'auto-test complet sans écran
./build/SimpleVector.app/Contents/MacOS/SimpleVector --self-test
```

---

## Ligne de commande

```bash
# Inspecter un document PDF ou SVG (JSON, CSV ou TXT)
SimpleVector --info contrat.pdf --format json

# Remplacer un texte dans un PDF, apposer une signature sur la dernière page et exporter en PDF
SimpleVector contrat.pdf --replace-text "En attente=VALIDÉ POUR EXÉCUTION" --sign "Adrien Mondot" -o contrat-signe.pdf

# Exporter un document SVG ou PDF en PNG haute résolution ou SVG multipage
SimpleVector plan-plateau.svg --export /tmp/plan-plateau.pdf --format pdf

# Capturer une image de contrôle hors écran (single, plot, multipage, grid, about, help, shortcuts, settings, osc)
SimpleVector --snapshot /tmp/preview.png --view single --lang fr
```

---

## Pilotage OSC, API HTTP & MCP

- **OSC (UDP)** : écoute sur `0.0.0.0:9160`, retour d'état sur `127.0.0.1:9161` (`/simplevector/page`, `/simplevector/nextPage`, `/simplevector/prevPage`, `/simplevector/sign`, `/simplevector/stamp`, `/simplevector/addPage`, `/simplevector/addText`, `/simplevector/replaceText`, `/simplevector/undo`, `/simplevector/redo`, `/simplevector/export`, `/simplevector/demo`).
- **HTTP `/v1` (JSON)** : serveur local sur `http://127.0.0.1:17960/v1` (`/v1/state`, `/v1/open`, `/v1/page`, `/v1/sign`, `/v1/stamp`, `/v1/text`, `/v1/export`, `/v1/svg`, `/v1/snapshot.png`).
- **Serveur MCP embarqué** : `SimpleVector.app/Contents/MacOS/simplevector-mcp` (9 outils MCP sur `stdio` JSON-RPC 2.0).

---

## Confidentialité

SimpleVector traite les documents PDF et SVG exclusivement en local sur le Mac et n'ouvre que les ports locaux OSC (`:9160`) et HTTP/MCP (`127.0.0.1:17960`). Aucune télémétrie, aucun compte, aucune connexion externe hors vérification quotidienne optionnelle des mises à jour sur `api.github.com/repos/cieadrienm/SimpleVector/releases/latest`.

---

## Crédits & Licence

- **Conception & développement** : Adrien Mondot · **cie Adrien M** — [adrien-m.net/software](https://www.adrien-m.net/software)
- **Licence** : GNU General Public License v3.0 or later ([LICENSE](LICENSE))
