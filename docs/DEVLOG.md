# Development log — Shoprise

## 2026-10-02 — Generated meshes in the game

- Batch complete (30/30 TRELLIS.2 + BiRefNet matte; Shelf at res 512). postprocess.py + combine.py ->
  `assets/processed/Shoprise_assets.glb` (88 MB, gitignored); imported in Studio by the user;
  `organize_import.lua` (now works without requiring game modules) put them in ReplicatedStorage.Assets;
  `extract_assets.luau` -> `assets/roblox/Assets.rbxm` (30 assets, ~0.5 MB; meshes are uploaded
  rbxassetids owned by the user's account).
- Sizing: props keep their proportions (longest side = SIZES); building pieces that must fill their
  slot (Storefront, ShutterDoor, Railing, Elevator, Escalator, Shelf, Barricade) are fitted per axis.
  Shelf needed a 180° turn (`YAW_FIX` in organize_import.lua).
- `AssetRegistry.PREFER_PROCEDURAL = { Storefront = true }`: the generated storefront has a solid back
  wall that closes the store; the code-built one stays until the mesh gets an opening.
- Escalator glass balustrades are invisible (collision only) when the escalator mesh is used; the mesh rises toward -Z, so it is placed with a 180° turn. Its steps are flat for the first ~5 studs and stopped ~2 studs under the next floor, so at build time the server raycasts the mesh's top surface, stretches it to FLOOR_HEIGHT and builds the invisible walking surface from those samples (one thin slab per stud). Verified: surface matches the mesh within 0.01 stud; a character walks up in ~2 s.
- Known for the user's mesh pass: trash cans (and a few props) carry a flat square base plate; shelf
  product cartons sit inside the shelf mesh (positions come from the old procedural layout).

## 2026-10-02 — Self-checkout kiosk

- Convenience store upgrade "Self-checkout kiosk" ($550): an InfoKiosk beside the counter serves the
  first free queued customer (within the first two, so a cashier can work in parallel) every 6 s
  (`Stores.Convenience.SelfCheckoutSeconds`); sales by the kiosk count for the ledger but not for
  worker tasks or assist bonuses; inactive-floor simulation treats it as a seller. The idea: it frees
  the single Mall-1 cashier to be moved to the Clothing shop (Workers tab ▸ Move). A second cashier
  trial at the boutique was considered and dropped at the user's request.

## 2026-10-02 — Partial boxes

- A box is no longer consumed whole. Restocking puts only what fits on the shelf; the rest stays in
  the carried box ("Restocked 1 Groceries (7 left in the box)"), which can go to another shelf of the
  same store. Dropping the box beside its pallet puts the units back as a partial box ("+ 4 loose");
  Take box hands out the partial box first. Stockers fill the target shelf, carry leftovers to the next
  shelf with room, and return any remainder to the pallet. Verified in play with a sale trace.

## 2026-10-02 — Empty shelves and the first-store tutorial

- Menu: the expandable tab bar is gone. One Menu button opens the panel (Business tab) and hides
  itself; closing the panel brings it back. The panel fills the phone screen (IgnoreGuiInset, no
  UIScale on phones) and is 900x640 on desktop. The tutorial billboard is smaller on phones.

- Customers who find an empty shelf now walk to another shelf that has stock; if every shelf is empty
  they wait at the shelf (orange "🥛?" bubble) for up to their patience and take products as soon as a
  restock lands, on whichever shelf was filled. Verified: waiting customer -> restock on the other
  shelf -> walked over, took 3, queued, served, left.
- Tutorial arrow (`TutorialController`, server state in `ProgressService.tutorialState`): a bouncing
  arrow with a label guides the first store: "Your store is here" while far away, then order a box,
  box on its way, take the box, restock this shelf, serve customers here. It ends after the first sale.
  AlwaysOnTop billboards do not appear in Studio screen captures, so the arrow is a world billboard.

## 2026-10-01 (night) — Leaderboards and a lighter phone HUD

- `LeaderboardService`: three all-time boards (Richest, Top sellers, Most customers served) on the south
  wall of every floor, OrderedDataStores `Shoprise_LB_v1_<Id>` (Dev_ prefix in Studio), writes every
  90 s and on leave, refresh every 60 s; without DataStore access the boards list the server's players.
- HUD: cash pill top-centre with mall/floor under it, objective card flush top-right, IgnoreGuiInset
  on, phone UIScale now 0.7–1.0 from the viewport (an S20's 915x412 viewport gives 0.72) so the world
  stays visible; checked in the device simulator at 915x412.

## 2026-10-01 (evening) — Feedback pass: lingering customers, balloon clutter, collapsible menu

- Served customers lingered ~15 s at the counter: the queue walk waited on `Humanoid:MoveTo` (two
  8 s rounds) before the leave logic could run. `NpcService.MoveTo` now takes a `shouldStop` callback,
  checks it every 0.15 s, treats 2.5 studs as arrival and honours `MoveToFinished`; the queue loop
  passes "served or leaving" as the stop condition. Measured: leaving 0.27 s after the sale.
- Prompts only show when usable (`StoreService.RefreshPrompts`): Take box needs boxes on the pallet /
  dock / stockroom, Restock needs shelf space, Serve / Help / Prepare need a waiting customer. The
  pallet balloon hides when empty, empty counter balloons are gone, label distances were shortened.
- Bottom menu collapses to a single "Menu" button; the four tabs expand on tap and an X collapses them.
- Studio's Assistant now runs sandboxed in new windows (cannot reparent scripts or invoke the game's
  BindableFunction). New Studio-only runner: write a test module into `ServerStorage.MMTest`, set the
  `Run` attribute, read `Result`. Sync by rebuilding the .rbxl and reopening it.

## 2026-10-01 (later) — Published as Shoprise, drop action

- The user published the experience (first as "Mall Makers", renamed to **Shoprise** because the name
  was taken): universe 10768853423, place 96580292994685. Content was synced into the published place
  through the MCP and published from the File menu (System Events).
- Drop action: Q key or the Drop button (shown while carrying) puts the box/basket on the floor in front
  of the player with a "Pick up" prompt; stock boxes nobody picks up return to their pallet / stockroom /
  dock after 150 s; lost-delivery boxes stay until picked up. Tested: drop lands on the floor (y 0.1),
  pick-up restores the same carry data, expiry returns the box to the pallet.

## 2026-10-01 — Vertical slice: Mall 1 complete, compact Mall 2, pipeline running

**Built**
- Rojo project, config tables (Economy / Stores / Workers / Malls), shared modules, AssetRegistry with
  code-built placeholders for all 30 prop ids.
- 15 server services (see README) and 4 client controllers. Everything the design brief lists for
  Mall 1 plus a compact Mall 2 with the logistics mechanic, electronics and arcade, manager income.
- Asset pipeline copied from Data Core Clash and adapted (gen_batch.sh with res-512 fallback,
  postprocess with bottom-centre pivot, organize_import.lua, Lune extraction tool). Batch started
  01:23 with a flood-fill matte; 5 of 30 props generated by 09:00 (res 1024 is slow on boxy shapes).
  At ~09:45 the user asked for the high-quality matte: added `matte.py` (BiRefNet 1024, same model as
  QtMeshEditor `--matting best`), re-matted all 30 images and restarted the batch from scratch.

**Tested in Roblox Studio (Apple Silicon, built-in MCP; single player + server-side test modules)**
| Check | Result |
|---|---|
| Server boot, floor assignment, spawn on own floor, HUD/objective | pass |
| Order stock (cash and StockCost ledger), box delivery, carry, restock, shelf labels | pass |
| Customers enter, browse, take items, queue, get served, pay; revenue/sales/served ledgers | pass (after fixing a queue-state race that returned sold items) |
| Customers walked up the escalator (entrance was at its foot) | fixed: entrances moved beside the escalators |
| Business panel ledger; upgrade purchase via the Action remote (326 → 106) | pass |
| Lease Clothing + Food lots; interiors built; kiosk trial discovery appears | pass (after fixing a label offset bug) |
| Hire Stocker / Cashier; stocker restocks from the pallet, cashier serves (tasks counted) | pass |
| NPCs stay on the right floor after the entrance fix | pass |
| Project contribution → completion → elevator ride to floor 2 | pass |
| Clothing match minigame, food assemble minigame (any order), wrong answer → angry customer | pass |
| Milestones + unlock Downtown Mall, travel, Mall 2 floor built with dock/stockroom/discoveries | pass |
| Dock delivery (van), dock box refused at a shelf, stockroom store/take, shelf restock, capacity cap, stockroom upgrade | pass |
| Electronics match + demo bonus; arcade break after plays, repair minigame | pass |
| Technician + Manager hired; manager assigned to Mall 1 | pass |
| Inactive-floor simulation sells with a cashier while the owner is in Mall 2 | pass |
| Wage tick books wages and deducts cash; no unpaid workers with cash available | pass |
| Rate limiter burst (Lune unit test) and currency formatting | pass |
| Profile JSON-encodable (DataStore constraints) | pass |
| Save / session lock / release / reload with the Studio mock store: save round-trips cash, lots, upgrades, stock; a fresh lock from another job blocks loading (3 retries, 6 s) and our own save refuses to overwrite it; a stale lock (> 180 s) is taken over; release + reload restores everything | pass |
| iPhone 17 Pro device simulator (750x361): HUD cards, bottom bar between joystick and jump button, panel scrolls; no clipping | pass |

**Bugs found and fixed**
- Served customers had their items returned to the shelf: the queue walk loop overwrote the `Served`
  state after a yield. Now uses a `Served` flag and never downgrades state.
- Customers climbed to the next floor: spawn entrances sat at the escalator foot.
- Clothing store build crashed on a `StudsOffset` set on the TextLabel instead of its BillboardGui.
- Previous-mall income double-counted the manager's wage; now `stores × IncomePerMinutePerStore`
  (manager wage comes from the normal wage tick).
- Gotham fonts lack ✔ ✕ ◻; replaced with emoji / ASCII.
- matte.py's first rescue rule filled enclosed white holes (between chair legs, basket grid); now only
  non-white, non-border-connected pixels are rescued.

**Known limitations / needs Studio testing by a human**
- Multiplayer (visiting, assist bonuses, visitor restrictions, project co-funding) was verified by code
  review only; needs *Test > Clients and Servers* with 2+ players.
- Real DataStore saves need a published place; Studio runs the same code against an in-memory mock.
- Mouse-click simulation through the MCP did not reach GUI buttons; the panel actions were verified by
  firing the same remote. Touch layout not yet checked in the device simulator.
- Only 5 of 30 meshes were generated when this entry was written; the game runs on placeholders for the rest.
