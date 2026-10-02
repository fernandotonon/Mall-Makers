--[[
	MallService — builds the static geometry of every mall (floors, walls, lot shells, escalators,
	elevator shells, decor) and answers "where is X" questions for the other services.

	Floor-local layout (origin = floor centre at floor level, +Z = south / corridor side):
	  x in [-85, 85], z in [-55, 55]
	  lots: 36 x 30 footprint along the north wall (z in [-50, -20]), fronts face +Z
	  atrium hole (floors >= 2): x in [-20, 20], z in [0, 30]; fountain on floor 1
	  escalators at x = +-40 from z = 40 (bottom) up to z = 13 on the next floor
	  elevator shell at (-35, 46), landing (-35, 36); spawn (0, 40); project board (-22, 46)
	  staff room x in [62, 78], z in [32, 48]; dock / stockroom (Mall 2) on the west side
]]
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Malls = require(ReplicatedStorage.Config.Malls)
local AssetRegistry = require(ReplicatedStorage.Shared.AssetRegistry)
local Constants = require(ReplicatedStorage.Shared.Constants)

local MallService = {}
local S

local H = Constants.FLOOR_HEIGHT
local HALF_X, HALF_Z = 85, 55
local WALL_H = H
MallService.HALF_X, MallService.HALF_Z = HALF_X, HALF_Z
MallService.CORRIDOR_Z = -12
MallService.LOT_W, MallService.LOT_D = 36, 30
MallService.ATRIUM = { x0 = -20, x1 = 20, z0 = 0, z1 = 30 }
MallService.ESCALATOR_X = { 40, -40 }
MallService.ESCALATOR_BOTTOM_Z, MallService.ESCALATOR_TOP_Z = 40, 13
MallService.ELEVATOR_POS = Vector3.new(-35, 0, 46)
MallService.ELEVATOR_LANDING = Vector3.new(-35, 0, 36)
MallService.SPAWN = Vector3.new(0, 0, 40)
MallService.BOARD_POS = Vector3.new(-22, 0, 46)
MallService.BASKET_STAND = Vector3.new(22, 0, 46)
MallService.STAFF_ROOM = { x0 = 62, x1 = 78, z0 = 32, z1 = 48 }

local C = AssetRegistry.Colors
local folders = {} -- [mallId][floor] = { Static = Folder, Dynamic = Folder }

local function part(parent, size, cf, color, material, name)
	local p = Instance.new("Part")
	p.Name = name or "Part"
	p.Size = size
	p.CFrame = cf
	p.Color = color or C.Cream
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Config access ----------------------------------------------------------------

function MallService.Config(mallId)
	return Malls[mallId]
end

function MallService.LotCfg(mallId, lotId)
	for _, lot in ipairs(Malls[mallId].Lots) do
		if lot.Id == lotId then
			return lot
		end
	end
	return nil
end

function MallService.FloorY(mallId, floor)
	return Malls[mallId].Origin.Y + (floor - 1) * H
end

function MallService.FloorOrigin(mallId, floor)
	local o = Malls[mallId].Origin
	return Vector3.new(o.X, MallService.FloorY(mallId, floor), o.Z)
end

function MallService.ToWorld(mallId, floor, localPos)
	return MallService.FloorOrigin(mallId, floor) + Vector3.new(localPos.X, localPos.Y, localPos.Z)
end

function MallService.LotCenter(mallId, floor, lotId)
	local lot = MallService.LotCfg(mallId, lotId)
	return MallService.ToWorld(mallId, floor, lot.Pos)
end

-- identity rotation: lot-local +Z points to the corridor
function MallService.LotCFrame(mallId, floor, lotId)
	return CFrame.new(MallService.LotCenter(mallId, floor, lotId))
end

function MallService.SpawnCFrame(mallId, floor)
	local p = MallService.ToWorld(mallId, floor, MallService.SPAWN)
	return CFrame.lookAt(p + Vector3.new(0, 3.5, 0), p + Vector3.new(0, 3.5, -10))
end

function MallService.ElevatorLanding(mallId, floor)
	return MallService.ToWorld(mallId, floor, MallService.ELEVATOR_LANDING)
end

function MallService.Entrances(mallId, floor)
	return {
		-- beside the escalators (not at their foot, or walkers would climb to the next floor)
		MallService.ToWorld(mallId, floor, Vector3.new(54, 0, 44)),
		MallService.ToWorld(mallId, floor, Vector3.new(-54, 0, 44)),
	}
end

function MallService.StaticFolder(mallId, floor)
	return folders[mallId][floor].Static
end

function MallService.DynamicFolder(mallId, floor)
	return folders[mallId][floor].Dynamic
end

-- Which mall / floor contains a world position (nil if outside every mall)
function MallService.LocateFloor(position)
	for _, mall in ipairs(Malls) do
		local o = mall.Origin
		local lx, lz = position.X - o.X, position.Z - o.Z
		if math.abs(lx) <= HALF_X + 10 and math.abs(lz) <= HALF_Z + 10 then
			local rel = position.Y - o.Y
			local floor = math.clamp(math.floor((rel + 4) / H) + 1, 1, mall.Floors)
			return mall.Id, floor
		end
	end
	return nil
end

-- Geometry ----------------------------------------------------------------------

-- rect = {x0,x1,z0,z1}; holes = list of rects; builds a 1-stud slab with its TOP at y
local function buildSlab(parent, rect, holes, y, color, material)
	local xs, zs = { rect[1], rect[2] }, { rect[3], rect[4] }
	for _, h in ipairs(holes) do
		table.insert(xs, math.clamp(h[1], rect[1], rect[2]))
		table.insert(xs, math.clamp(h[2], rect[1], rect[2]))
		table.insert(zs, math.clamp(h[3], rect[3], rect[4]))
		table.insert(zs, math.clamp(h[4], rect[3], rect[4]))
	end
	table.sort(xs)
	table.sort(zs)
	local function uniq(t)
		local out = {}
		for _, v in ipairs(t) do
			if out[#out] ~= v then
				table.insert(out, v)
			end
		end
		return out
	end
	xs, zs = uniq(xs), uniq(zs)
	local function inHole(cx, cz)
		for _, h in ipairs(holes) do
			if cx > h[1] and cx < h[2] and cz > h[3] and cz < h[4] then
				return true
			end
		end
		return false
	end
	for zi = 1, #zs - 1 do
		local z0, z1 = zs[zi], zs[zi + 1]
		local runStart = nil
		for xi = 1, #xs do
			local solid = xi < #xs and not inHole((xs[xi] + xs[xi + 1]) / 2, (z0 + z1) / 2)
			if solid and not runStart then
				runStart = xs[xi]
			elseif not solid and runStart then
				local x1 = xs[xi]
				part(parent, Vector3.new(x1 - runStart, 1, z1 - z0), CFrame.new((runStart + x1) / 2, y - 0.5, (z0 + z1) / 2), color, material, "Floor")
				runStart = nil
			end
		end
	end
end

local function buildRailings(parent, o, y)
	local a = MallService.ATRIUM
	-- along x edges
	for z = a.z0 + 4, a.z1 - 4, 8 do
		AssetRegistry.Place("Railing", CFrame.new(o.X + a.x0, y, o.Z + z), parent, 90)
		AssetRegistry.Place("Railing", CFrame.new(o.X + a.x1, y, o.Z + z), parent, 90)
	end
	for x = a.x0 + 4, a.x1 - 4, 8 do
		AssetRegistry.Place("Railing", CFrame.new(o.X + x, y, o.Z + a.z0), parent, 0)
		AssetRegistry.Place("Railing", CFrame.new(o.X + x, y, o.Z + a.z1), parent, 0)
	end
	for _, ex in ipairs(MallService.ESCALATOR_X) do
		for z = 17, 25, 8 do
			AssetRegistry.Place("Railing", CFrame.new(o.X + ex - 4, y, o.Z + z), parent, 90)
			AssetRegistry.Place("Railing", CFrame.new(o.X + ex + 4, y, o.Z + z), parent, 90)
		end
	end
end

local function buildEscalator(parent, o, y, ex)
	local bottomZ, topZ = MallService.ESCALATOR_BOTTOM_Z, MallService.ESCALATOR_TOP_Z
	local dz = bottomZ - topZ
	local len = math.sqrt(dz ^ 2 + H ^ 2)
	local ang = math.atan2(H, dz)
	local centre = CFrame.new(o.X + ex, y + H / 2, o.Z + (bottomZ + topZ) / 2) * CFrame.Angles(ang, 0, 0)
	local ramp = part(parent, Vector3.new(6, 0.6, len + 1), centre, C.Dark, Enum.Material.DiamondPlate, "EscalatorRamp")
	ramp.Transparency = 1
	ramp.CanQuery = false
	-- decorative asset centred on the ramp footprint (pivot = bottom centre of its bbox)
	-- the generated escalator mesh rises toward -Z: turn it so its low end is at bottomZ
	local m = AssetRegistry.Place("Escalator", CFrame.new(o.X + ex, y, o.Z + (bottomZ + topZ) / 2), parent, AssetRegistry.HasImported("Escalator") and 180 or 0)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	-- side balustrade walls so players cannot walk off the ramp sideways
	for _, sx in ipairs({ -3.2, 3.2 }) do
		local w = part(parent, Vector3.new(0.3, 3.5, len), centre * CFrame.new(sx, 1.8, 0), C.Teal, nil, "Balustrade")
		-- the imported escalator mesh has its own sides: keep the wall for collision only
		w.Transparency = AssetRegistry.HasImported("Escalator") and 1 or 0.5
	end
end

local function buildLotShell(parent, mall, lot, o, y)
	local w, d = MallService.LOT_W, MallService.LOT_D
	local cx, cz = o.X + lot.Pos.X, o.Z + lot.Pos.Z
	local color = C.Cream
	-- side walls
	part(parent, Vector3.new(0.6, 12, d), CFrame.new(cx - w / 2, y + 6, cz), color, nil, "LotWall")
	part(parent, Vector3.new(0.6, 12, d), CFrame.new(cx + w / 2, y + 6, cz), color, nil, "LotWall")
	-- front fill beside the storefront opening (storefront is 24 wide)
	local fill = (w - 24) / 2
	part(parent, Vector3.new(fill, 12, 0.6), CFrame.new(cx - w / 2 + fill / 2, y + 6, cz + d / 2), color, nil, "LotWall")
	part(parent, Vector3.new(fill, 12, 0.6), CFrame.new(cx + w / 2 - fill / 2, y + 6, cz + d / 2), color, nil, "LotWall")
	-- lintel above the storefront
	part(parent, Vector3.new(24, 2, 0.6), CFrame.new(cx, y + 13, cz + d / 2), color, nil, "LotWall")
	-- interior floor tint
	local f = part(parent, Vector3.new(w - 1, 0.1, d - 1), CFrame.new(cx, y + 0.05, cz), Color3.fromRGB(235, 228, 215), Enum.Material.SmoothPlastic, "LotFloor")
	f.CanCollide = false
	-- storefront facade: front faces +Z (corridor), so rotate 180
	AssetRegistry.Place("Storefront", CFrame.new(cx, y, cz + d / 2 - 1), parent, 180)
end

local function buildFloor(mall, floor)
	local mallId = mall.Id
	local o = mall.Origin
	local y = MallService.FloorY(mallId, floor)
	local root = folders[mallId].Root
	local floorFolder = Instance.new("Folder")
	floorFolder.Name = "Floor" .. floor
	floorFolder.Parent = root
	local static = Instance.new("Folder")
	static.Name = "Static"
	static.Parent = floorFolder
	local dynamic = Instance.new("Folder")
	dynamic.Name = "Dynamic"
	dynamic.Parent = floorFolder
	folders[mallId][floor] = { Static = static, Dynamic = dynamic }

	-- slab with holes
	local holes = {}
	if floor > 1 then
		local a = MallService.ATRIUM
		table.insert(holes, { o.X + a.x0, o.X + a.x1, o.Z + a.z0, o.Z + a.z1 })
		for _, ex in ipairs(MallService.ESCALATOR_X) do
			table.insert(holes, { o.X + ex - 3.5, o.X + ex + 3.5, o.Z + MallService.ESCALATOR_TOP_Z, o.Z + 27 })
		end
	end
	local floorColor = floor % 2 == 0 and Color3.fromRGB(226, 220, 208) or Color3.fromRGB(236, 230, 218)
	buildSlab(static, { o.X - HALF_X, o.X + HALF_X, o.Z - HALF_Z, o.Z + HALF_Z }, holes, y, floorColor, Enum.Material.SmoothPlastic)

	-- outer walls (top floor gets a low parapet + glass look)
	local wallColor = C.Cream
	part(static, Vector3.new(HALF_X * 2 + 1, WALL_H, 1), CFrame.new(o.X, y + WALL_H / 2, o.Z - HALF_Z), wallColor, nil, "Wall")
	part(static, Vector3.new(HALF_X * 2 + 1, WALL_H, 1), CFrame.new(o.X, y + WALL_H / 2, o.Z + HALF_Z), wallColor, nil, "Wall")
	part(static, Vector3.new(1, WALL_H, HALF_Z * 2 + 1), CFrame.new(o.X - HALF_X, y + WALL_H / 2, o.Z), wallColor, nil, "Wall")
	part(static, Vector3.new(1, WALL_H, HALF_Z * 2 + 1), CFrame.new(o.X + HALF_X, y + WALL_H / 2, o.Z), wallColor, nil, "Wall")
	-- accent stripe
	local stripe = part(static, Vector3.new(HALF_X * 2 + 1.2, 1.2, 0.2), CFrame.new(o.X, y + 9, o.Z - HALF_Z + 0.6), C.Teal, nil, "Stripe")
	stripe.CanCollide = false

	-- lots
	for _, lot in ipairs(mall.Lots) do
		buildLotShell(static, mall, lot, o, y)
	end
	-- wall segments between lots along z = -20
	local edges = { -HALF_X }
	for _, lot in ipairs(mall.Lots) do
		table.insert(edges, lot.Pos.X - MallService.LOT_W / 2)
		table.insert(edges, lot.Pos.X + MallService.LOT_W / 2)
	end
	table.insert(edges, HALF_X)
	for i = 1, #edges - 1, 2 do
		local x0, x1 = edges[i], edges[i + 1]
		if x1 - x0 > 0.5 then
			part(static, Vector3.new(x1 - x0, 12, 0.6), CFrame.new(o.X + (x0 + x1) / 2, y + 6, o.Z - 20), wallColor, nil, "Wall")
			local topFill = part(static, Vector3.new(x1 - x0, 0.3, 30), CFrame.new(o.X + (x0 + x1) / 2, y + 12, o.Z - 35), Color3.fromRGB(215, 210, 200), nil, "Roof")
			topFill.CanCollide = false
		end
	end

	-- escalators to the next floor
	if floor < mall.Floors then
		for _, ex in ipairs(MallService.ESCALATOR_X) do
			buildEscalator(static, o, y, ex)
		end
	end
	if floor > 1 then
		buildRailings(static, o, y)
	end

	-- elevator shell (doors face -Z, the landing is north of it)
	AssetRegistry.Place("Elevator", CFrame.new(o.X + MallService.ELEVATOR_POS.X, y, o.Z + MallService.ELEVATOR_POS.Z), static, 0)

	-- floor sign
	local signPart = part(static, Vector3.new(10, 3, 0.3), CFrame.new(o.X, y + 12.5, o.Z + HALF_Z - 0.8), C.Teal, nil, "FloorSign")
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(400, 120)
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBlack
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.Text = ("%s · Floor %d"):format(mall.Name, floor)
	tl.Parent = sg
	sg.Parent = signPart

	-- decor
	if floor == 1 then
		AssetRegistry.Place("Fountain", CFrame.new(o.X, y, o.Z + 15), static, 0)
	end
	for _, dx in ipairs({ -26, 26 }) do
		AssetRegistry.Place("PlanterTree", CFrame.new(o.X + dx, y, o.Z + 36), static, 0)
		AssetRegistry.Place("Bench", CFrame.new(o.X + dx, y, o.Z + 4), static, dx < 0 and 90 or -90)
	end
	AssetRegistry.Place("TrashCan", CFrame.new(o.X + 12, y, o.Z + 46), static, 0)
	AssetRegistry.Place("TrashCan", CFrame.new(o.X - 12, y, o.Z + 46), static, 0)
	for _, dx in ipairs({ -60, 60 }) do
		AssetRegistry.Place("CafeTable", CFrame.new(o.X + dx, y, o.Z + 8), static, 0)
		AssetRegistry.Place("Chair", CFrame.new(o.X + dx - 3, y, o.Z + 8), static, -90)
		AssetRegistry.Place("Chair", CFrame.new(o.X + dx + 3, y, o.Z + 8), static, 90)
	end

	-- staff room (worker discovery: RestorePower) — walls with a door gap toward the corridor
	local r = MallService.STAFF_ROOM
	part(static, Vector3.new(r.x1 - r.x0, 10, 0.6), CFrame.new(o.X + (r.x0 + r.x1) / 2, y + 5, o.Z + r.z0), C.Grey, nil, "StaffWall")
	part(static, Vector3.new(0.6, 10, (r.z1 - r.z0) * 0.35), CFrame.new(o.X + r.x0, y + 5, o.Z + r.z0 + (r.z1 - r.z0) * 0.175), C.Grey, nil, "StaffWall")
	part(static, Vector3.new(0.6, 10, (r.z1 - r.z0) * 0.35), CFrame.new(o.X + r.x0, y + 5, o.Z + r.z1 - (r.z1 - r.z0) * 0.175), C.Grey, nil, "StaffWall")
	local roof = part(static, Vector3.new(r.x1 - r.x0, 0.4, r.z1 - r.z0), CFrame.new(o.X + (r.x0 + r.x1) / 2, y + 10, o.Z + (r.z0 + r.z1) / 2), C.Grey, nil, "StaffRoof")
	roof.CanCollide = false

	-- Mall 2: loading dock platform + stockroom markings (the van, boxes and rack are dynamic)
	if mall.Logistics then
		local dp = mall.Logistics.DockPos
		local dock = part(static, Vector3.new(26, 1.2, 16), CFrame.new(o.X + dp.X, y + 0.6, o.Z + dp.Z), C.Grey, Enum.Material.Concrete, "DockPlatform")
		dock.CanCollide = true
		local stripe2 = part(static, Vector3.new(26, 0.2, 0.6), CFrame.new(o.X + dp.X, y + 1.25, o.Z + dp.Z - 8), C.Yellow, nil, "DockStripe")
		stripe2.CanCollide = false
		local sp = mall.Logistics.StockroomPos
		local mark = part(static, Vector3.new(16, 0.1, 14), CFrame.new(o.X + sp.X, y + 0.1, o.Z + sp.Z), Color3.fromRGB(200, 215, 230), nil, "StockroomFloor")
		mark.CanCollide = false
	end
end

local function buildMall(mall)
	local root = Instance.new("Folder")
	root.Name = "Mall" .. mall.Id
	root.Parent = Workspace:FindFirstChild("Malls")
	folders[mall.Id] = { Root = root }
	-- ground under the mall
	local o = mall.Origin
	part(root, Vector3.new(HALF_X * 2 + 40, 2, HALF_Z * 2 + 40), CFrame.new(o.X, o.Y - 2, o.Z), Color3.fromRGB(120, 170, 110), Enum.Material.Grass, "Ground")
	for floor = 1, mall.Floors do
		buildFloor(mall, floor)
	end
	-- roof over the top floor (leaves the atrium open to the sky)
	local topY = MallService.FloorY(mall.Id, mall.Floors) + H
	local a = MallService.ATRIUM
	buildSlab(root, { o.X - HALF_X, o.X + HALF_X, o.Z - HALF_Z, o.Z + HALF_Z }, { { o.X + a.x0 - 10, o.X + a.x1 + 10, o.Z + a.z0 - 10, o.Z + a.z1 + 10 } }, topY + 1, Color3.fromRGB(210, 205, 195), Enum.Material.Concrete)
	-- mall name on the outside
	local sign = part(root, Vector3.new(60, 8, 1), CFrame.new(o.X, topY + 6, o.Z + HALF_Z + 1), C.Coral, nil, "MallSign")
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(1200, 160)
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBlack
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.Text = mall.Name
	tl.Parent = sg
	sg.Parent = sign
end

function MallService.Init(services)
	S = services
	local mallsFolder = Workspace:FindFirstChild("Malls")
	if mallsFolder then
		mallsFolder:Destroy()
	end
	mallsFolder = Instance.new("Folder")
	mallsFolder.Name = "Malls"
	mallsFolder.Parent = Workspace
	for _, mall in ipairs(Malls) do
		buildMall(mall)
	end
	-- default spawn (players are moved to their own floor once their profile loads)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.CFrame = MallService.SpawnCFrame(1, 1) * CFrame.new(0, -3, 0)
	spawn.Parent = mallsFolder
	local base = Workspace:FindFirstChild("Baseplate")
	if base then
		base:Destroy()
	end
end

function MallService.Start() end

return MallService
