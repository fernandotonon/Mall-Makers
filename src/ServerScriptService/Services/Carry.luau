--[[
	Carry — one carried object per character (stock box, lost box, basket). The object is a visual
	model welded in front of the character; the authoritative state is the table below.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetRegistry = require(ReplicatedStorage.Shared.AssetRegistry)

local Carry = {}
local carried = {} -- player -> { Kind, Data, Model }

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

function Carry.Drop(player)
	Carry.Take(player)
end

return Carry
