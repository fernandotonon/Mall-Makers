--[[
	AssetRegistry — single replacement point for placeholder art.

	AssetRegistry.Spawn(id) returns a Model whose pivot is the BOTTOM CENTER of the asset and whose
	front faces -Z. Resolution order:
	  1. ReplicatedStorage.Assets.<id> (anywhere below) — a Model/MeshPart imported from QtMeshEditor
	  2. the primitive placeholder builder below

	Contract for imported assets (assets/organize_import.lua writes it):
	  - Model with a PrimaryPart (the MeshPart), PrimaryPart.PivotOffset puts the pivot at the bottom
	  - size in studs roughly matches SIZES[id]
	  - attribute AssetSource = "Imported"
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetRegistry = {}

-- X, Y, Z in studs; mirrors assets/source/manifest.json
AssetRegistry.SIZES = {
	Storefront = Vector3.new(24, 14, 4),
	Elevator = Vector3.new(10, 12, 4),
	CafeTable = Vector3.new(4, 3, 4),
	Escalator = Vector3.new(6, 16, 26),
	Chair = Vector3.new(2, 3, 2),
	Bench = Vector3.new(6, 3, 2),
	Fountain = Vector3.new(14, 8, 14),
	PlanterTree = Vector3.new(6, 9, 6),
	Railing = Vector3.new(8, 3, 0.6),
	TrashCan = Vector3.new(2, 3, 2),
	ShutterDoor = Vector3.new(12, 12, 1.5),
	CheckoutCounter = Vector3.new(8, 3.5, 3),
	Shelf = Vector3.new(8, 7, 3),
	StockBox = Vector3.new(2, 2, 2),
	MilkCarton = Vector3.new(0.8, 1.4, 0.8),
	Basket = Vector3.new(2, 1.6, 1.6),
	ClothesRack = Vector3.new(6, 6, 2),
	ClothesTable = Vector3.new(6, 3, 3),
	FoodKiosk = Vector3.new(12, 9, 8),
	Griddle = Vector3.new(5, 4, 3),
	BurgerTray = Vector3.new(2, 0.8, 1.5),
	DrinkDispenser = Vector3.new(3.5, 4, 2.5),
	HandTruck = Vector3.new(2, 4, 2),
	StockroomRack = Vector3.new(10, 9, 4),
	DeliveryVan = Vector3.new(8, 7, 16),
	ArcadeCabinet = Vector3.new(3, 7, 3),
	ElectronicsCounter = Vector3.new(6, 4, 4),
	Generator = Vector3.new(4, 3.5, 3),
	Barricade = Vector3.new(8, 3.5, 2),
	InfoKiosk = Vector3.new(4, 7, 2),
}

local C = {
	Cream = Color3.fromRGB(245, 236, 220),
	Teal = Color3.fromRGB(64, 150, 150),
	Coral = Color3.fromRGB(240, 120, 100),
	Grey = Color3.fromRGB(90, 92, 100),
	Dark = Color3.fromRGB(45, 48, 55),
	Wood = Color3.fromRGB(200, 140, 80),
	Card = Color3.fromRGB(190, 140, 90),
	Green = Color3.fromRGB(90, 180, 90),
	Steel = Color3.fromRGB(170, 175, 185),
	Red = Color3.fromRGB(220, 60, 60),
	Yellow = Color3.fromRGB(250, 210, 80),
}
AssetRegistry.Colors = C

local function part(model, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color or C.Cream
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

-- origin = bottom center; helper for "box at (x, yBottom, z) with size"
local function box(model, x, yBottom, z, size, color, material)
	return part(model, size, CFrame.new(x, yBottom + size.Y / 2, z), color, material)
end

local function newModel(id)
	local m = Instance.new("Model")
	m.Name = id
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = m
	m.PrimaryPart = root
	m:SetAttribute("AssetSource", "Placeholder")
	return m
end

local B = {} -- builders

B.Storefront = function(m)
	local s = AssetRegistry.SIZES.Storefront
	box(m, -s.X / 2 + 2, 0, 0, Vector3.new(4, s.Y, s.Z), C.Cream) -- left pillar
	box(m, s.X / 2 - 2, 0, 0, Vector3.new(4, s.Y, s.Z), C.Cream) -- right pillar
	box(m, 0, s.Y - 4, 0, Vector3.new(s.X, 4, s.Z), C.Cream) -- header
	box(m, 0, s.Y - 3.4, -s.Z / 2 - 0.1, Vector3.new(s.X - 6, 2.8, 0.2), C.Teal) -- sign board
	box(m, -s.X / 2 + 2, 2, -s.Z / 2 - 0.1, Vector3.new(2, s.Y - 7, 0.2), C.Coral)
	box(m, s.X / 2 - 2, 2, -s.Z / 2 - 0.1, Vector3.new(2, s.Y - 7, 0.2), C.Coral)
	box(m, 0, 0, 0, Vector3.new(s.X, 1, s.Z), C.Teal) -- base trim (walk-over)
end

B.Elevator = function(m)
	local s = AssetRegistry.SIZES.Elevator
	box(m, 0, 0, 0, Vector3.new(s.X, s.Y, s.Z), C.Cream)
	box(m, 0, 0, -s.Z / 2 - 0.1, Vector3.new(5, 9, 0.3), C.Steel, Enum.Material.Metal) -- doors
	box(m, 0, 4, -s.Z / 2 - 0.3, Vector3.new(0.15, 9, 0.2), C.Dark)
	box(m, 3.6, 4, -s.Z / 2 - 0.2, Vector3.new(0.8, 1.2, 0.2), C.Coral) -- button panel
	box(m, 0, s.Y - 2, 0, Vector3.new(s.X, 2, s.Z), C.Teal)
end

B.CafeTable = function(m)
	part(m, Vector3.new(0.6, 2.2, 0.6), CFrame.new(0, 1.1, 0), C.Teal)
	part(m, Vector3.new(0.3, 4, 4), CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Cream, nil, Enum.PartType.Cylinder)
	part(m, Vector3.new(0.3, 2.4, 2.4), CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Coral, nil, Enum.PartType.Cylinder)
end

B.Escalator = function(m)
	local s = AssetRegistry.SIZES.Escalator
	-- a sloped tread plus two balustrades; the game adds its own walkable ramp
	local len = math.sqrt(s.Y ^ 2 + s.Z ^ 2)
	local ang = math.atan2(s.Y, s.Z)
	local centre = CFrame.new(0, s.Y / 2, 0) * CFrame.Angles(ang, 0, 0) -- rises toward -Z, bbox-centred
	part(m, Vector3.new(s.X - 1, 0.6, len), centre, C.Dark, Enum.Material.DiamondPlate).CanCollide = false
	part(m, Vector3.new(0.4, 3, len), centre * CFrame.new(-s.X / 2 + 0.3, 1.7, 0), C.Teal).CanCollide = false
	part(m, Vector3.new(0.4, 3, len), centre * CFrame.new(s.X / 2 - 0.3, 1.7, 0), C.Teal).CanCollide = false
end

B.Chair = function(m)
	box(m, 0, 0, 0, Vector3.new(1.8, 1.6, 1.8), C.Teal)
	box(m, 0, 1.6, 0, Vector3.new(1.8, 0.3, 1.8), C.Cream)
	box(m, 0, 1.6, 0.75, Vector3.new(1.8, 1.4, 0.3), C.Coral)
end

B.Bench = function(m)
	box(m, -2.4, 0, 0, Vector3.new(0.6, 1.4, 1.8), C.Teal)
	box(m, 2.4, 0, 0, Vector3.new(0.6, 1.4, 1.8), C.Teal)
	box(m, 0, 1.4, 0, Vector3.new(6, 0.3, 1.8), C.Wood, Enum.Material.Wood)
	box(m, 0, 1.7, 0.75, Vector3.new(6, 1.3, 0.3), C.Wood, Enum.Material.Wood)
end

B.Fountain = function(m)
	part(m, Vector3.new(2.5, 14, 14), CFrame.new(0, 1.25, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Cream, nil, Enum.PartType.Cylinder)
	local water = part(m, Vector3.new(0.4, 12, 12), CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 200, 210), Enum.Material.Glass, Enum.PartType.Cylinder)
	water.Transparency = 0.3
	part(m, Vector3.new(3, 2, 2), CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Teal, nil, Enum.PartType.Cylinder)
	part(m, Vector3.new(0.6, 6, 6), CFrame.new(0, 5.6, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Cream, nil, Enum.PartType.Cylinder)
	part(m, Vector3.new(2, 1.2, 1.2), CFrame.new(0, 6.9, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Coral, nil, Enum.PartType.Cylinder)
end

B.PlanterTree = function(m)
	box(m, 0, 0, 0, Vector3.new(5, 2.5, 5), C.Cream)
	box(m, 0, 1, 0, Vector3.new(5.1, 0.5, 5.1), C.Teal)
	box(m, 0, 2.5, 0, Vector3.new(0.8, 3, 0.8), Color3.fromRGB(120, 80, 50), Enum.Material.Wood)
	part(m, Vector3.new(5.5, 4.5, 5.5), CFrame.new(0, 6.6, 0), C.Green, Enum.Material.Grass, Enum.PartType.Ball).CanCollide = false
end

B.Railing = function(m)
	box(m, -3.7, 0, 0, Vector3.new(0.5, 3, 0.5), C.Cream)
	box(m, 3.7, 0, 0, Vector3.new(0.5, 3, 0.5), C.Cream)
	box(m, 0, 1.2, 0, Vector3.new(8, 0.3, 0.3), C.Teal)
	box(m, 0, 2.5, 0, Vector3.new(8, 0.4, 0.4), C.Teal)
end

B.TrashCan = function(m)
	part(m, Vector3.new(2.4, 1.8, 1.8), CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Teal, nil, Enum.PartType.Cylinder)
	part(m, Vector3.new(0.6, 2, 2), CFrame.new(0, 2.7, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Cream, nil, Enum.PartType.Cylinder)
end

B.ShutterDoor = function(m)
	local s = AssetRegistry.SIZES.ShutterDoor
	box(m, 0, 0, 0, Vector3.new(s.X, s.Y, s.Z), C.Teal, Enum.Material.Metal)
	for i = 1, 6 do
		box(m, 0, (i - 1) * 1.9 + 0.9, -s.Z / 2 - 0.05, Vector3.new(s.X - 1, 0.25, 0.1), C.Dark)
	end
	box(m, 0, s.Y - 1, 0, Vector3.new(s.X + 1, 1, s.Z + 0.4), C.Cream)
end

B.CheckoutCounter = function(m)
	local s = AssetRegistry.SIZES.CheckoutCounter
	box(m, 0, 0, 0, Vector3.new(s.X, 3, s.Z), C.Cream)
	box(m, 0, 1.2, -s.Z / 2 - 0.05, Vector3.new(s.X, 0.6, 0.1), C.Coral)
	box(m, 0, 3, 0, Vector3.new(s.X, 0.3, s.Z), C.Teal)
	box(m, 2.8, 3.3, 0.4, Vector3.new(1.2, 1.4, 1), C.Dark) -- register
end

B.Shelf = function(m)
	local s = AssetRegistry.SIZES.Shelf
	box(m, 0, 0, 0, Vector3.new(s.X, 0.6, s.Z), C.Teal)
	box(m, 0, 0, 1.2, Vector3.new(s.X, s.Y, 0.4), C.Cream) -- back panel
	for i = 1, 3 do
		box(m, 0, i * 2 - 0.4, 0, Vector3.new(s.X, 0.3, s.Z), C.Teal)
	end
end

B.StockBox = function(m)
	box(m, 0, 0, 0, Vector3.new(2, 2, 2), C.Card, Enum.Material.Fabric)
	box(m, 0, 1.95, 0, Vector3.new(0.6, 0.12, 2.05), C.Cream)
end

B.MilkCarton = function(m)
	box(m, 0, 0, 0, Vector3.new(0.8, 1.1, 0.8), C.Red)
	part(m, Vector3.new(0.8, 0.4, 0.8), CFrame.new(0, 1.2, 0), C.Cream, nil, Enum.PartType.Wedge)
end

B.Basket = function(m)
	box(m, 0, 0, 0, Vector3.new(2, 1.2, 1.6), C.Teal)
	box(m, 0, 1.2, 0, Vector3.new(1.6, 0.4, 0.2), C.Cream)
end

B.ClothesRack = function(m)
	box(m, 0, 0, 0, Vector3.new(6, 0.4, 2), C.Teal)
	box(m, -2.8, 0.4, 0, Vector3.new(0.4, 5.4, 0.4), C.Cream)
	box(m, 2.8, 0.4, 0, Vector3.new(0.4, 5.4, 0.4), C.Cream)
	box(m, 0, 5.6, 0, Vector3.new(6, 0.3, 0.3), C.Cream)
	local cols = { C.Coral, C.Teal, C.Yellow }
	for i, col in ipairs(cols) do
		box(m, (i - 2) * 1.7, 2.6, 0, Vector3.new(1.4, 2.6, 0.5), col, Enum.Material.Fabric)
	end
end

B.ClothesTable = function(m)
	box(m, -2.5, 0, 0, Vector3.new(0.5, 2.2, 2.6), C.Teal)
	box(m, 2.5, 0, 0, Vector3.new(0.5, 2.2, 2.6), C.Teal)
	box(m, 0, 2.2, 0, Vector3.new(6, 0.3, 3), C.Cream)
	box(m, -1.6, 2.5, 0, Vector3.new(1.4, 0.6, 1.4), C.Coral, Enum.Material.Fabric)
	box(m, 0, 2.5, 0, Vector3.new(1.4, 0.6, 1.4), C.Teal, Enum.Material.Fabric)
	box(m, 1.6, 2.5, 0, Vector3.new(1.4, 0.6, 1.4), C.Yellow, Enum.Material.Fabric)
end

B.FoodKiosk = function(m)
	local s = AssetRegistry.SIZES.FoodKiosk
	box(m, 0, 0, 0, Vector3.new(s.X, 3.2, s.Z), C.Cream) -- counter ring
	box(m, 0, 1.5, -s.Z / 2 - 0.05, Vector3.new(s.X, 0.7, 0.1), C.Coral)
	for _, x in ipairs({ -s.X / 2 + 0.6, s.X / 2 - 0.6 }) do
		for _, z in ipairs({ -s.Z / 2 + 0.6, s.Z / 2 - 0.6 }) do
			box(m, x, 3.2, z, Vector3.new(0.6, 4.8, 0.6), C.Teal)
		end
	end
	box(m, 0, 8, 0, Vector3.new(s.X + 1, 1, s.Z + 1), C.Coral)
end

B.Griddle = function(m)
	box(m, 0, 0, 0, Vector3.new(5, 3, 3), C.Cream)
	box(m, 0, 3, 0, Vector3.new(5, 0.5, 3), C.Dark, Enum.Material.Metal)
	box(m, 0, 3.5, 1.3, Vector3.new(5, 0.5, 0.3), C.Grey, Enum.Material.Metal)
	for i = -1, 1 do
		box(m, i * 1.4, 1.6, -1.55, Vector3.new(0.6, 0.6, 0.15), C.Coral)
	end
end

B.BurgerTray = function(m)
	box(m, 0, 0, 0, Vector3.new(2, 0.15, 1.5), C.Cream)
	part(m, Vector3.new(0.9, 0.7, 0.9), CFrame.new(-0.4, 0.5, 0), C.Wood, nil, Enum.PartType.Ball)
	box(m, 0.5, 0.15, 0, Vector3.new(0.5, 0.7, 0.5), C.Red)
end

B.DrinkDispenser = function(m)
	box(m, 0, 0, 0, Vector3.new(3.5, 1.8, 2.5), C.Cream)
	box(m, -0.9, 1.8, 0, Vector3.new(1.5, 2.2, 1.8), C.Teal, Enum.Material.Glass)
	box(m, 0.9, 1.8, 0, Vector3.new(1.5, 2.2, 1.8), C.Coral, Enum.Material.Glass)
end

B.HandTruck = function(m)
	box(m, 0, 0, 0, Vector3.new(2, 0.2, 1.6), C.Cream)
	box(m, 0, 0.2, 0.7, Vector3.new(2, 3.8, 0.3), C.Teal)
	part(m, Vector3.new(0.4, 1, 1), CFrame.new(-1, 0.5, 0.9) * CFrame.Angles(0, 0, math.rad(90)), C.Dark, nil, Enum.PartType.Cylinder)
	part(m, Vector3.new(0.4, 1, 1), CFrame.new(1, 0.5, 0.9) * CFrame.Angles(0, 0, math.rad(90)), C.Dark, nil, Enum.PartType.Cylinder)
end

B.StockroomRack = function(m)
	local s = AssetRegistry.SIZES.StockroomRack
	for _, x in ipairs({ -s.X / 2 + 0.3, s.X / 2 - 0.3 }) do
		for _, z in ipairs({ -s.Z / 2 + 0.3, s.Z / 2 - 0.3 }) do
			box(m, x, 0, z, Vector3.new(0.6, s.Y, 0.6), C.Cream)
		end
	end
	for i = 0, 2 do
		box(m, 0, i * 3 + 0.3, 0, Vector3.new(s.X, 0.4, s.Z), C.Teal)
	end
end

B.DeliveryVan = function(m)
	box(m, 0, 1.2, 1.5, Vector3.new(8, 5.5, 12), C.Teal)
	box(m, 0, 1.2, -5.5, Vector3.new(8, 3.5, 3), C.Cream)
	box(m, 0, 3.6, -3.9, Vector3.new(7.6, 2.2, 0.3), C.Dark, Enum.Material.Glass)
	for _, x in ipairs({ -3.5, 3.5 }) do
		for _, z in ipairs({ -4.5, 4 }) do
			part(m, Vector3.new(1, 2.4, 2.4), CFrame.new(x, 1.2, z) * CFrame.Angles(0, 0, math.rad(90)), C.Dark, Enum.Material.Rubber, Enum.PartType.Cylinder)
		end
	end
end

B.ArcadeCabinet = function(m)
	box(m, 0, 0, 0, Vector3.new(3, 7, 3), C.Teal)
	box(m, 0, 3.6, -1.55, Vector3.new(2.4, 2, 0.1), C.Dark, Enum.Material.Glass) -- screen
	box(m, 0, 2.6, -1.55, Vector3.new(2.4, 0.6, 0.2), C.Coral) -- panel
	box(m, 0, 6.2, -1.55, Vector3.new(3, 0.8, 0.1), C.Coral)
end

B.ElectronicsCounter = function(m)
	box(m, 0, 0, 0, Vector3.new(6, 3.2, 4), C.Cream)
	box(m, 0, 1.3, -2.05, Vector3.new(6, 0.6, 0.1), C.Coral)
	box(m, 0, 3.2, 0, Vector3.new(6, 0.3, 4), C.Teal)
	box(m, 0, 3.5, 0, Vector3.new(2, 0.15, 1.5), C.Dark) -- laptop
	part(m, Vector3.new(2, 1.3, 0.1), CFrame.new(0, 4.2, 0.7) * CFrame.Angles(math.rad(-15), 0, 0), C.Dark)
end

B.Generator = function(m)
	box(m, 0, 0, 0, Vector3.new(4, 3, 3), C.Cream)
	box(m, 0, 3, 0, Vector3.new(4.2, 0.5, 3.2), C.Teal)
	box(m, -1.2, 1.4, -1.55, Vector3.new(0.6, 0.6, 0.1), C.Coral) -- switch
	box(m, 1, 0.6, -1.55, Vector3.new(1.4, 1.4, 0.1), C.Dark)
end

B.Barricade = function(m)
	box(m, -3, 0, 0, Vector3.new(1.4, 2, 1.6), C.Grey)
	box(m, 3, 0, 0, Vector3.new(1.4, 2, 1.6), C.Grey)
	local b = box(m, 0, 2, 0, Vector3.new(8, 1.4, 0.6), Color3.fromRGB(240, 130, 50))
	for i = -3, 3, 2 do
		box(m, i, 2.1, -0.35, Vector3.new(0.6, 1.2, 0.1), C.Cream)
	end
	b.Name = "Bar"
end

B.InfoKiosk = function(m)
	box(m, 0, 0, 0, Vector3.new(3, 3.5, 1.6), C.Teal)
	box(m, 0, 3.5, 0, Vector3.new(4, 3, 0.6), C.Cream)
	local screen = box(m, 0, 3.8, -0.35, Vector3.new(3.4, 2.4, 0.1), C.Dark, Enum.Material.Glass)
	screen.Name = "Screen"
	part(m, Vector3.new(0.3, 1.2, 1.2), CFrame.new(0, 7, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Coral, nil, Enum.PartType.Cylinder)
end

-- Public -------------------------------------------------------------------------

local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")

-- Imported meshes that are not usable yet: the code-built version is used instead.
-- Storefront: the generated facade has a solid back wall that closes the store entrance.
AssetRegistry.PREFER_PROCEDURAL = { Storefront = true }

local function findImported(id)
	if AssetRegistry.PREFER_PROCEDURAL[id] then
		return nil
	end
	if not assetsFolder then
		assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
		if not assetsFolder then
			return nil
		end
	end
	local inst = assetsFolder:FindFirstChild(id, true)
	if inst and (inst:IsA("Model") or inst:IsA("MeshPart")) then
		return inst
	end
	return nil
end

function AssetRegistry.HasImported(id)
	return findImported(id) ~= nil
end

function AssetRegistry.Spawn(id)
	local imported = findImported(id)
	if imported then
		local clone = imported:Clone()
		if clone:IsA("MeshPart") then
			local m = Instance.new("Model")
			m.Name = id
			clone.Parent = m
			m.PrimaryPart = clone
			clone = m
		end
		clone:SetAttribute("AssetSource", "Imported")
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		return clone
	end
	local builder = B[id]
	assert(builder, "AssetRegistry: unknown asset id " .. tostring(id))
	local m = newModel(id)
	builder(m)
	return m
end

function AssetRegistry.Size(id)
	return AssetRegistry.SIZES[id] or Vector3.new(2, 2, 2)
end

-- Place an asset: cf is the bottom-center pivot; yaw in degrees (0 = front faces -Z)
function AssetRegistry.Place(id, cf, parent, yawDeg)
	local m = AssetRegistry.Spawn(id)
	if yawDeg and yawDeg ~= 0 then
		cf = cf * CFrame.Angles(0, math.rad(yawDeg), 0)
	end
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

return AssetRegistry
