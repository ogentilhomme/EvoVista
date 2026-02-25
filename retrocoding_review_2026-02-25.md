# Retrocoding Review — 2026-02-25

## Objectif
Rendre la pipeline `3DRecon` plus fiable et plus simple à utiliser sur Linux:
- backend COLMAP modulable (local ou Docker),
- suppression des hardcodes projet,
- GUI plus robuste,
- logs lisibles et exploitables,
- ouverture des résultats en environnement propre malgré VS Code Snap.

## Problèmes rencontrés et causes
1. Hardcode `MyProject` dans les scripts COLMAP Docker.
Cause: `-w /workspace/data/MyProject` fixé en dur.

2. Faux positif sur la détection "COLMAP local CUDA".
Cause: détection trop permissive basée sur des heuristiques larges.

3. Crash en mode Docker via sous-scripts (`SCRIPT_DIR: unbound variable`).
Cause: fonction `run_colmap` exportée sans variables d’environnement associées.

4. Erreurs `symbol lookup error` sur `colmap gui` / `meshlab`.
Cause: pollution runtime liée au terminal VS Code Snap (libs `/snap/core20/...`).

## Modifications réalisées

### A. Exécution COLMAP centralisée
Fichiers:
- `/home/fabien/project/3DRecon/run.sh`
- `/home/fabien/project/3DRecon/src/1_feature_extraction.sh`
- `/home/fabien/project/3DRecon/src/2_feature_matching.sh`
- `/home/fabien/project/3DRecon/src/3_sparce_reconstruction.sh`
- `/home/fabien/project/3DRecon/src/4_dense_reconstruction.sh`

Changements:
- Backend unique via `run_colmap` (local/Docker) dans `run.sh`.
- Suppression de la duplication Docker dans `src/*.sh`.
- Passage des scripts `src/*.sh` à `run_colmap ...` uniquement.
- Export des variables nécessaires (`SCRIPT_DIR`, `COLMAP_BACKEND`, `COLMAP_IMAGE`, `COLMAP_GPU_FLAGS`).
- Trace shell rendue optionnelle (`DEBUG_TRACE=1`).

Résultat:
- Plus de hardcode `MyProject`.
- Même logique de lancement pour toutes les étapes.
- Bug `unbound variable` corrigé.

### B. Détection backend améliorée
Fichiers:
- `/home/fabien/project/3DRecon/run.sh`
- `/home/fabien/project/3DRecon/run_gui.py`

Changements:
- Détection locale CUDA basée sur `colmap version`.
- Gestion explicite:
  - `without CUDA` => local non CUDA
  - `with CUDA` / `CUDA enabled` => local CUDA
- Fallback Docker si local CUDA indisponible.

Résultat:
- Plus de faux “COLMAP local CUDA” quand la build locale est CPU-only.

### C. GUI renforcée
Fichier:
- `/home/fabien/project/3DRecon/run_gui.py`

Changements:
- Affichage du statut backend (`Local only`, `Docker only`, etc.).
- Sélecteur backend Local/Docker.
- Bouton `Re-detect`.
- Fallback terminal Linux en cascade:
  - `gnome-terminal`
  - `x-terminal-emulator`
  - `xterm`
- Détection des terminaux qui quittent immédiatement.

Résultat:
- Lancement plus robuste depuis l’UI.

### D. Logs lisibles + timer pipeline
Fichier:
- `/home/fabien/project/3DRecon/run.sh`

Changements:
- Timer par étape (`START/DONE/FAIL`).
- Résumé final:
  - durée par étape,
  - durée totale.
- Log brut horodaté:
  - `data/<project>/logs/pipeline_YYYYMMDD_HHMMSS.log`.
- Affichage terminal filtré (`PRETTY_LOG=1` par défaut):
  - garde progression utile (`Processed file x/y`, `Processing view x/y`, erreurs, elapsed time),
  - conserve le log complet sur disque.

Résultat:
- Console lisible, post-analyse facilitée.

### E. Ouverture des résultats en environnement propre
Fichiers:
- `/home/fabien/project/3DRecon/scripts/run_colmap_gui_clean.sh`
- `/home/fabien/project/3DRecon/scripts/open_results_clean.sh`

Changements:
- Scripts `env -i` pour contourner les conflits Snap.
- `open_results_clean.sh` ouvre:
  - COLMAP GUI avec import auto du `sparse/<scene_id>`,
  - MeshLab sur `dense/<scene_id>/fused.ply`.
- `house_mesh.ply` optionnel uniquement via `OPEN_MESH=1`.

Résultat:
- Ouverture fiable des résultats dans le contexte actuel.

### F. Auto-ouverture en fin de pipeline
Fichier:
- `/home/fabien/project/3DRecon/run.sh`

Changements:
- `AUTO_OPEN_RESULTS=1` par défaut.
- En fin de run, ouverture automatique via `scripts/open_results_clean.sh` (si session GUI disponible).
- Détection auto de la scène la plus récente (`dense` prioritaire, sinon `sparse`).

Résultat:
- Fin de calcul directement exploitable sans commandes manuelles.

### G. Documentation mise à jour
Fichier:
- `/home/fabien/project/3DRecon/README.md`

Changements:
- Ajout des commandes de vérification résultats.
- Ajout des scripts d’ouverture “clean env”.
- Clarification de ce qui doit être vu dans COLMAP (sparse) et MeshLab (fused).

## Commandes utiles (partenaire)
1. Lancer pipeline:
`./run.sh <project> [options]`

2. Forcer backend:
`COLMAP_BACKEND=docker ./run.sh <project> ...`
`COLMAP_BACKEND=local ./run.sh <project> ...`

3. Ouvrir résultats proprement:
`./scripts/open_results_clean.sh <project> <scene_id>`

4. Désactiver ouverture auto:
`AUTO_OPEN_RESULTS=0 ./run.sh <project> ...`

5. Désactiver pretty log:
`PRETTY_LOG=0 ./run.sh <project> ...`

## Validation technique
- `bash -n` OK sur scripts shell modifiés.
- `python3 -m py_compile run_gui.py` OK.
- Test Docker CUDA OK (`colmap/colmap:latest` avec `--gpus all`).

## Synthèse
La pipeline est maintenant:
- modulaire (local/Docker),
- plus robuste en exécution,
- plus lisible en terminal,
- opérationnelle malgré l’environnement VS Code Snap,
- mieux documentée pour transfert à un partenaire.
