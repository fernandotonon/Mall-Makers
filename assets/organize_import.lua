-- Post-import organizer (run in Studio, Edit mode, e.g. through the MCP execute_luau tool).
-- Expects the 3D Importer result in Workspace named IMPORT_NAME (default "MallMakers_assets") with one child
-- MeshPart (or Model) per asset id. Moves each into ReplicatedStorage.Assets as Model{PrimaryPart=MeshPart},
-- scales it to AssetRegistry.SIZES[id] by the longest axis, and sets PivotOffset so the pivot is the
-- bottom centre (the AssetRegistry contract). Returns a report string.
local IMPORT_NAME = IMPORT_NAME or "MallMakers_assets"
local RS = game:GetService("ReplicatedStorage")
local AssetRegistry = require(RS.Shared.AssetRegistry)
local SIZES = AssetRegistry.SIZES
local assets = RS:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = RS
local import = workspace:FindFirstChild(IMPORT_NAME)
assert(import, "import model not found: " .. IMPORT_NAME)
local report = {}
local function meshOf(inst)
	if inst:IsA("MeshPart") then return inst end
	return inst:FindFirstChildWhichIsA("MeshPart", true)
end
for _, child in ipairs(import:GetChildren()) do
	local id = child.Name:gsub("_Node$", "")
	local mp = meshOf(child)
	if mp and SIZES[id] then
		local target = SIZES[id]
		local cur = mp.Size
		local s = math.max(target.X, target.Y, target.Z) / math.max(cur.X, cur.Y, cur.Z)
		mp.Size = cur * s
		mp.Name = id
		mp.Anchored = true
		mp.CanCollide = true
		mp.CollisionFidelity = (target.X * target.Z > 40) and Enum.CollisionFidelity.PreciseConvexDecomposition or Enum.CollisionFidelity.Box
		-- footprint orientation: if the target is longer along X but the mesh along Z, turn it 90 degrees
		local yaw = 0
		if ((target.X > target.Z) ~= (mp.Size.X > mp.Size.Z)) and math.abs(target.X - target.Z) > 0.5 then yaw = math.rad(90) end
		mp.PivotOffset = CFrame.new(0, -mp.Size.Y / 2, 0) * CFrame.Angles(0, yaw, 0)
		local existing = assets:FindFirstChild(id, true)
		if existing then existing:Destroy() end
		local m = Instance.new("Model")
		m.Name = id
		mp.Parent = m
		m.PrimaryPart = mp
		m:SetAttribute("AssetSource", "Imported")
		m.Parent = assets
		table.insert(report, ("%s: %s -> %s (x%.3f)%s"):format(id, tostring(cur), tostring(mp.Size), s, yaw ~= 0 and " rotated" or ""))
		if child.Parent then child:Destroy() end
	else
		table.insert(report, id .. ": " .. (mp and "unknown asset id" or "no MeshPart found"))
	end
end
import:Destroy()
game:GetService("ChangeHistoryService"):SetWaypoint("MallMakers organize import")
return table.concat(report, "\n")
