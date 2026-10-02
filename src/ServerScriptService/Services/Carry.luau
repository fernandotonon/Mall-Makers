--[[
	Carry — one carried object per character (stock box, lost box, basket). The object is a visual
	model welded in front of the character; the authoritative state is the table below.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.AssetRegistry)

local Carry = {}
local carried = {} -- player -> { Kind, Data, Model }
-- Dropped items lie on the floor with a "Pick up" prompt. Stock boxes that nobody picks up again go
-- back to their source after DROP_TIMEOUT seconds (StoreService installs the handler); lost-delivery
-- boxes never expire; baskets just vanish (new ones respawn anyway).
local DROP_TIMEOUT = 150
Carry.OnExpire = nil -- function(kind, data) set by StoreService
Carry.OnDrop = nil -- function(player, kind, data, position) -> handled?  (StoreService: drop beside the pallet = put back)
local droppedFolder

local ASSET_FOR = { StockBox = "StockBox", LostBox = "StockBox", Basket = "Basket" }

local function torsoOf(character)
	return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
end

function Carry.Get(player)
	return carried[player]
end

function Carry.Give(player, kind, data)
	if carried[player] then
		return false, "You are already carrying something."
	end
	local character = player.Character
	local torso = character and torsoOf(character)
	if not torso then
		return false
	end
	local model = AssetRegistry.Spawn(ASSET_FOR[kind] or "StockBox")
	model.Name = "Carried_" .. kind
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
		end
	end
	local size = AssetRegistry.Size(ASSET_FOR[kind] or "StockBox")
	model:PivotTo(torso.CFrame * CFrame.new(0, -0.6, -1.1 - size.Z / 2))
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= primary then
			local w = Instance.new("WeldConstraint")
			w.Part0 = primary
			w.Part1 = d
			w.Parent = primary
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = primary
	weld.Parent = primary
	model.Parent = character
	carried[player] = { Kind = kind, Data = data, Model = model }
	character:SetAttribute("Carrying", kind)
	return true
end

function Carry.Take(player, kind)
	local c = carried[player]
	if not c or (kind and c.Kind ~= kind) then
		return nil
	end
	carried[player] = nil
	if c.Model then
		c.Model:Destroy()
	end
	if player.Character then
		player.Character:SetAttribute("Carrying", nil)
	end
	return c
end

local function ensureDropped()
	if not droppedFolder or not droppedFolder.Parent then
		droppedFolder = workspace:FindFirstChild("Dropped") or Instance.new("Folder")
		droppedFolder.Name = "Dropped"
		droppedFolder.Parent = workspace
	end
	return droppedFolder
end

-- Puts the carried object down in front of the character. Returns true when something was dropped.
function Carry.Drop(player)
	local c = Carry.Take(player)
	if not c then
		return false
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root then
		if Carry.OnExpire then
			Carry.OnExpire(c.Kind, c.Data)
		end
		return true
	end
	-- find the floor under a point just in front of the character (fall back to the computed feet height)
	local ahead = root.Position + root.CFrame.LookVector * 2.5
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { char }
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then table.insert(filter, npcs) end
	local dropped = workspace:FindFirstChild("Dropped")
	if dropped then table.insert(filter, dropped) end
	params.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(ahead + Vector3.new(0, 1, 0), Vector3.new(0, -12, 0), params)
	local pos
	if hit then
		pos = hit.Position
	else
		pos = ahead - Vector3.new(0, (hum and hum.HipHeight or 2) + root.Size.Y / 2, 0)
	end
	if Carry.OnDrop and Carry.OnDrop(player, c.Kind, c.Data, pos) then
		return true
	end
	local model = AssetRegistry.Place(ASSET_FOR[c.Kind] or "StockBox", CFrame.new(pos) * CFrame.Angles(0, math.random() * math.pi * 2, 0), ensureDropped(), 0)
	model.Name = "Dropped_" .. c.Kind
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = c.Kind == "Basket" and "Basket" or (c.Kind == "LostBox" and "Lost delivery" or "Stock box")
	prompt.MaxActivationDistance = 8
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	local alive = true
	prompt.Triggered:Connect(function(who)
		if not alive then
			return
		end
		local whoRoot = who.Character and who.Character:FindFirstChild("HumanoidRootPart")
		if not whoRoot or (whoRoot.Position - anchor.Position).Magnitude > 12 then
			return
		end
		if Carry.Give(who, c.Kind, c.Data) then
			alive = false
			model:Destroy()
		end
	end)
	if c.Kind ~= "LostBox" then
		task.delay(DROP_TIMEOUT, function()
			if alive then
				alive = false
				model:Destroy()
				if c.Kind == "StockBox" and Carry.OnExpire then
					Carry.OnExpire(c.Kind, c.Data)
				end
			end
		end)
	end
	return true
end

return Carry
