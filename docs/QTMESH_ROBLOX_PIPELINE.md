# QtMeshEditor → Roblox pipeline (Mall Makers)

Carried over from Data Core Clash (`../Data-Core-Clash/docs/QTMESH_ROBLOX_PIPELINE.md` has the full
findings log). Settings for this project, as requested: **TRELLIS.2, geometry res 1024, 1024 px textures,
QtMeshEditor `--game-preset roblox-meshpart` (keeps the preset's ≤ 20k triangle budget)**.

## Steps

```
assets/source/<image>.png (ChatGPT renders, white studio background)
  -> assets/cutout.py          flood-fills the border-connected white to alpha -> cutout/<id>.png
  -> assets/gen_batch.sh       per asset:
       trellis-cli --model trellis --res 1024 --tex-res 1024 --dump-post dumps/<id>.trellisraw
       raw2qtm3d.py             dump -> QTM3D container
       QTMESH_TRELLIS2_IMPORT=dumps/<id>.qtm3d QtMeshEditor generate3d cutout/<id>.png -o generated/<id>.glb
           --backend pixal3d --tex-res 1024 --game-preset roblox-meshpart --no-source
  -> assets/postprocess.py     Y-up, front -Z, pivot bottom-centre, PNG textures embedded -> processed/<id>.glb
  -> assets/combine.py         one GLB with one root node per asset -> processed/MallMakers_assets.glb
  -> Studio File > Import 3D   (Upload to Roblox on) -> Workspace.MallMakers_assets with <id>_Node children
  -> assets/organize_import.lua  -> ReplicatedStorage.Assets.<id> (Model, PrimaryPart MeshPart, scaled, pivot)
  -> File > Save to build/MallMakers.rbxl, then lune run tools/extract_assets.luau -> assets/roblox/Assets.rbxm
```

`gen_batch.sh` logs to `assets/logs/batch.log`; `[done] <id> rc=0 <seconds> game-ready: N -> M tris`.
If a generation makes no log progress for 45 minutes it is killed and retried at res 512 (logged in
`logs/res512_fallback.txt`). Deleting `generated/<id>.glb` re-generates that id on the next run.

## Timings observed (Apple M5, 24 GB, Oct 1 2026, machine also running Studio)

| Asset           | res  | generate + bake | tris   |
|-----------------|------|-----------------|--------|
| Storefront      | 1024 | 41 min          | 19,978 |
| Shelf           | 1024 | 3 h 40 min      | 20,000 |
| StockBox        | 1024 | 1 h 47 min      | 19,996 |
| CheckoutCounter | 1024 | 31 min          | 20,000 |
| ShutterDoor     | 1024 | 28 min          | 19,992 |

Boxy, full-volume shapes (shelf, box) are the slow ones at res 1024, as in Data Core Clash; thin or
hollow shapes finish in ~30 min. The verbose log keeps growing during those long runs, so the stall
detector does not fire; the fallback is there for true hangs.

## Studio import notes

- `AssetImportService` is not reachable from the MCP `execute_luau` context (service resolves to nil),
  so the import stays a manual *File > Import 3D* step; everything before and after it is scripted.
- The importer names nodes `<id>_Node`; `organize_import.lua` strips the suffix and files the meshes.
- Textured MeshParts ignore `Color`: owner accents go on separate sign parts, not on the meshes.
- Characters (6 T-pose images) are deferred: a static mesh cannot drive a walking Humanoid NPC without
  an R15 rig pipeline. Customers and workers are part-built rigs coloured per role until then.
