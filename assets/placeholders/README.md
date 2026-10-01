# Placeholders and the replacement contract

All placeholder art is built in code by `src/ReplicatedStorage/Shared/AssetRegistry.luau` from Roblox
primitives, in the cream / teal / coral palette of the concept images. Nothing in this folder is
loaded by the game.

## How a generated asset replaces a placeholder

1. `python3 assets/matte.py <Id>` makes the BiRefNet (high-quality) matte, then `assets/gen_batch.sh <Id>` generates `assets/generated/<Id>.glb` (TRELLIS.2 at 1024 geometry,
   QtMeshEditor `--game-preset roblox-meshpart` bake, 1024 px PBR).
2. `python3 assets/postprocess.py <Id>` -> `assets/processed/<Id>.glb` (Y-up, front -Z, pivot at the
   bottom centre, PNG textures embedded).
3. `python3 assets/combine.py assets/processed/Shoprise_assets.glb <Id> ...` packs several assets
   into one GLB so Studio imports them in one go.
4. Studio: *File > Import 3D* (keep "Upload to Roblox" on), pick the combined GLB. The result lands in
   Workspace as a Model named after the file with one `<Id>_Node` child per asset.
5. Run `assets/organize_import.lua` (Command bar or MCP execute_luau). It files each mesh into
   `ReplicatedStorage.Assets.<Id>` as a Model with `PrimaryPart`, scaled to `AssetRegistry.SIZES[Id]` and
   with the pivot at the bottom centre.
6. `lune run tools/extract_assets.luau build/Shoprise.rbxl` (after *File > Save* to the build file)
   writes `assets/roblox/Assets.rbxm`, which `default.project.json` maps back into ReplicatedStorage so
   `rojo build` keeps the meshes.
7. Play. `AssetRegistry.Spawn(Id)` prefers the imported model and tags it `AssetSource = "Imported"`.

## Asset ids and sizes (studs, X x Y x Z)

See `AssetRegistry.SIZES` (mirrors `assets/source/manifest.json`). Front faces -Z, pivot = bottom centre.

Deferred (character images 13, 30-34): CustomerKid, WorkerCashier, WorkerStocker, WorkerCook,
WorkerManager, CustomerAdult. Static T-posed meshes cannot drive walking NPCs; they need an R15 rig
pipeline. NPCs are part-built rigs with the worker's shirt colour until then.
