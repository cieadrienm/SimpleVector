# SimpleVector — Décisions d'architecture (.project-map)

Voir `DECISIONS.md` à la racine du dépôt pour le journal détaillé (D1–D6) :
- **D1** : Modèle de document multipage unifié (`VectorDocument`) hybride PDF + SVG.
- **D2** : Édition directe du texte intégré aux PDF par extraction `PDFSelection.selectionsByLine()` et masquage vectoriel à la demande (`activeMaskRects`).
- **D3** : Signatures calligraphiques vectorielles lissées (`StrokeSmoother`) et bibliothèque persistante.
- **D4** : Rendu 60–120 Hz ProMotion avec cache de géométrie (`VectorSceneRenderCache`) et frustum culling.
- **D5** : Sérialisation SVG multipage compatible Inkscape (`<inkscape:page>`) et import SVG 1.1/2.0 sans dépendance externe.
- **D6** : Ports de la famille Simple (`x = 6`, G92) : HTTP `/v1` sur `127.0.0.1:17960`, OSC entrée `0.0.0.0:9160`, retour OSC `127.0.0.1:9161`.
