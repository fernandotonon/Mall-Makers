# Shoprise (formerly Mall Makers; repo folder: Mall-Makers)

A cooperative Roblox entrepreneurship game. Up to four players each own a floor of an unfinished
shopping mall: serve customers, buy stock, reinvest in upgrades, discover and hire workers, lease new
stores, fund shared mall projects together, and open a floor in the next, bigger mall.

Loop: explore → serve customers → earn profit → buy stock and upgrades → recruit workers → open
stores → complete shared projects → unlock the next mall.

## Project layout

```
default.project.json              Rojo project (maps src/ and assets/roblox/Assets.rbxm into the DataModel)
src/
  ReplicatedStorage/
    Config/                       ALL balancing numbers (Economy, Stores, Workers, Malls)
    Shared/                       Remotes, Signal, Format (currency), RateLimiter, Constants, AssetRegistry
  ServerScriptService/
    Main.server.luau              Boots the services below; Studio-only MMDebug hook for tests
    Services/                     Data, Message, Economy, Mall, Npc, Floor, Store, Customer, Worker,
                                  Assist, Project, Transit, Recovery, Progress, Action (+ Carry helper)
  StarterPlayer/StarterPlayerScripts/
    ClientMain.client.luau        Boots controllers
    Controllers/                  HUD, Panel (business/stores/workers/mall/style), Minigame, Effects, UI helpers
assets/
  source/                         36 concept images + manifest.json (asset id -> image, size, preset)
  cutout/                         background-removed PNGs fed to TRELLIS (matte.py: BiRefNet high-quality matte)
  matte.py, gen_batch.sh, raw2qtm3d.py, postprocess.py, combine.py, organize_import.lua   asset pipeline
  roblox/Assets.rbxm              imported meshes (Rojo-mapped into ReplicatedStorage.Assets)
  placeholders/README.md          the placeholder replacement contract
tools/                            check.luau (syntax), test_ratelimiter.luau, studio_sync.luau, extract_assets.luau
docs/                             DEVLOG.md (what was built/tested), QTMESH_ROBLOX_PIPELINE.md
build/                            built .rbxl (git-ignored)
```

## Requirements

- Roblox Studio (tested with the Apple Silicon build, Oct 2026)
- [Rojo](https://rojo.space) 7.7 (`~/.local/bin/rojo` or via `aftman install`)
- [Lune](https://lune-org.github.io/docs) 0.10 for the syntax check / unit tests / asset extraction
- macOS with a non-English locale: Studio parses decimals with the system number format. Run
  `launchctl setenv LC_NUMERIC en_US.UTF-8` before opening Studio (a LaunchAgent already does this on
  the original dev machine; see the Data Core Clash README for details).

## Build and run

```sh
lune run tools/check.luau                 # syntax-check every .luau
rojo build -o build/Shoprise.rbxl       # one-shot place file
open build/Shoprise.rbxl                # opens in Roblox Studio
# or live sync: rojo serve, then Plugins > Rojo > Connect in Studio
```

Press **Play** in Studio. You spawn on your floor of the Neighborhood Mall with a convenience store,
$250 and the first objective in the top-right card. Use *Test > Clients and Servers* (2–4 players) to try
visiting, helping and shared projects.

### Iterating without reopening the place

`tools/studio_sync.luau` pulls every file in `build/files.txt` into the open place over HTTP:

```sh
find src -name '*.luau' | sort > build/files.txt
python3 -m http.server 8765 --bind 127.0.0.1 &      # serve the project root
# then run the contents of tools/studio_sync.luau in Studio's command bar (Edit mode)
```

In Play mode, write a test module (`return function(Services) ... end`) into the Source of
`ServerStorage.MMTest`, set its attribute `Run = true` and read the attribute `Result`; the game runs it
in its own context (works even when Studio's Assistant / command bar is sandboxed). The older
`MMDebug:Invoke("Run", moduleScript)` hook still exists for unsandboxed sessions.

## Published experience

- Experience "Shoprise": universe `10768853423`, start place `96580292994685`
  (https://www.roblox.com/games/96580292994685). Team Create is off for this place (it made Studio
  hang on close while applying script drafts).
- Re-publish after changes: `rojo build -o build/Shoprise.rbxl`, open it in Studio, then
  *File ▸ Publish to Roblox As ▸ Shoprise ▸ select the existing place ▸ Overwrite*.
- Icon and thumbnail files are in `assets/branding/` (`icon_512.png`, `thumbnail_1920x1080.png`);
  they are set on Creator Hub (experience ▸ Basic Settings ▸ Game Icon / Thumbnails), not in Studio.
- Access is private by default; switch it on Creator Hub (Audience ▸ Access) to let friends in.

## Saving

Progress is stored per player in the DataStore `Shoprise_v1` with a session lock (another live server
cannot overwrite the profile; a stale lock is taken over after 3 minutes). Autosave every 60 s, on
leave and on shutdown. **Dev mode**: in Studio, or with `Economy.Save.DevMode = true`, the store name
is prefixed with `Dev_` so production saves are never touched. When DataStores are unavailable
(unpublished place) Studio uses an in-memory mock store for the session and the HUD says so.

## Controls

| Action                        | Keyboard / mouse        | Gamepad       | Touch                    |
|-------------------------------|-------------------------|---------------|--------------------------|
| Interact (take box, restock, serve, help, repair, hire, contribute) | E (prompt)  | X     | Tap the prompt button    |
| Secondary prompt (order box / delivery, store box) | R          | Y             | Tap the prompt button    |
| Drop the carried box / basket | Q or Drop button        | –             | Drop button              |
| Open the tabs                 | Menu button (bottom)    | –             | Menu button              |
| Business panel                | B or Menu ▸ Business    | –             | Menu ▸ Business          |
| Mall tab (milestones, project, travel) | M or bottom bar | –           | Bottom bar               |
| Minigames (match / assemble / repair) | Click icons     | –             | Tap icons                |

All interactions are ProximityPrompts or big icon buttons: no typing, no aiming.

## Implemented

- **Floors and ownership**: up to 4 players per server, each assigned the lowest free floor on join
  (same index in every mall); floors are rebuilt from the profile and cleared on leave.
- **Mall 1, Neighborhood Mall**: Convenience store (carry boxes, restock shelves, serve at the counter),
  Clothing shop (match the customer's symbol at the display), Food kiosk (assemble 1–3 item orders).
  Locked lots show a shutter, price and lease prompt; leasing opens the store with its own interaction.
- **Customers**: part-built NPCs enter from the escalator side, browse / queue / request, react to empty
  shelves and long waits, pay and leave. Satisfaction (0–100) changes spawn rate and price (+25% at 100).
  Shopping rushes every 5 minutes. NPC counts are capped per store and per server.
- **Economy**: one cash currency; revenue, stock cost, wages and net profit per store in the Business
  panel; readable abbreviations ($1.2K, $2.5M). Stock boxes cost `BoxUnits × UnitCost` and arrive at the
  delivery point after a few seconds. Upgrades (extra shelf, bigger boxes, decor, second display…).
- **Workers**: discovered on your floor, not bought from a menu: return a courier's lost box (Stocker),
  restart the dark staff room's generator (Cashier), pass a 3-order trial at the kiosk (Cook); downtown:
  a technician's lost parts box and a powerless management office (Manager). Each shows wage and benefit
  before hiring. Cashiers serve, stockers carry boxes to shelves, cooks assemble, technicians repair and
  demo. Wages are paid every minute; unpaid workers pause until you have cash. Three efficiency levels
  from tasks done.
- **Cooperation**: anyone can take boxes, restock, serve, help, repair on any floor. Helpers get a
  separate assist bonus (capped per minute, per-object cooldown); the owner's income is untouched.
  Visitors cannot lease, upgrade, order stock, hire, or recruit on someone else's floor.
- **Shared projects**: project board on every floor; contributions are saved per player, server progress is
  the sum of the present contributors; completion is saved for every contributor (solo completion works).
  Mall 1: elevator restoration (teleporting elevator with floor buttons). Mall 2: loading dock expansion
  (bigger deliveries).
- **Tutorial arrow**: guides a new owner to the first store, the first box order, the first restock and
  the first sale (`TutorialController`, state from the server).
- **Leaderboards**: three all-time boards on the south wall of every floor (richest, top sellers, most
  customers served) backed by OrderedDataStores (`Economy.Leaderboards`).
- **Recovery**: stray baskets on every floor pay $5 each at the basket stand.
- **Progression**: objectives card, milestones (own all lots, 2 workers, project, $4,000 sales), opening
  project cost, then a floor in **Mall 2, Downtown Mall**.
- **Mall 2 logistics**: deliveries are generic boxes at the loading dock (van drives in) → carried into a
  capacity-limited stockroom (upgradeable) → carried to shelves. Electronics shop (match the gadget, hold
  a demo for a bonus) and Arcade (machines break, 3-icon repair sequence; customers pay per play).
- **Earlier-mall income**: assign a Manager to a mall you left; while online it earns
  `IncomePerMinutePerStore` per staffed store (≈ 10–20% of the next mall's first lease over 10 minutes).
  Stores on floors nobody is on are simulated economically instead of spawning NPCs.
- **Server authority**: cash, stock, sales, hiring, wages, ownership, unlocks and assist rewards are
  server-side. Every client action goes through one rate-limited remote; prompts re-check distance,
  ownership, carried object and prerequisites. Clients never send prices or earnings.
- **UI**: responsive (UIScale from viewport, larger bar on touch), code-built HUD, panel with five
  tabs, icon minigames, toasts and one-time contextual tips, money pops, celebrations, fades.

## Where to tune the economy

Everything lives in `src/ReplicatedStorage/Config/`:

- `Economy.luau`: starting cash, autosave/lock timings, wage interval, assist caps, basket reward, rush
  timing, customer caps/patience/satisfaction effects, inactive-floor simulation rate, previous-mall
  income, worker levels.
- `Stores.luau`: per store type: unit cost/price, box size, delivery time, shelves/capacity, upgrades,
  which workers fit, minigame symbols/ingredients/categories, arcade break chance.
- `Workers.luau`: wages, benefits, task durations, tips.
- `Malls.luau`: lots and lease prices, price multiplier per mall, projects (cost/step), discoveries and
  their positions, unlock milestones and opening cost, Mall 2 logistics (stockroom capacity, delivery size
  and cost).

## Asset pipeline (QtMeshEditor)

See `docs/QTMESH_ROBLOX_PIPELINE.md` and `assets/placeholders/README.md`. Short version:
`assets/matte.py` (BiRefNet matte) → `assets/gen_batch.sh` → `postprocess.py` → `combine.py` → Studio *Import 3D* → `organize_import.lua` →
`lune run tools/extract_assets.luau`. The game runs with code-built placeholders until a mesh exists for
an id; `AssetRegistry.Spawn(id)` swaps automatically.

## Roadmap (not in this prototype)

- Mall 3 (customer preferences, complementary neighbours, promotion events) and Mall 4 (delegation,
  festivals, peak staffing).
- Capped offline earnings for managed malls (the save already tracks `ManagerAssigned`; add a
  `LastSeen` timestamp and a capped catch-up on load).
- Character meshes for customers/workers (R15 rig pipeline), uploaded sounds, more cosmetics.
- Worker reassignment UI beyond the "Move" cycle button; per-store worker capacity.
- Monetization (intentionally absent).
