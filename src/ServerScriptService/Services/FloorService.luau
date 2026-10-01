--[[
	FloorService — assigns each player a floor index (shared across malls) when their profile loads,
	asks the other services to build that floor's content, tears it down on leave, and keeps track of
	who is physically on which floor (for customer simulation and interaction checks).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local Malls = require(ReplicatedStorage.Config.Malls)
local Signal = require(ReplicatedStorage.Shared.Signal)

local FloorService = {}
FloorService.OnFloorAssigned = Signal.new() -- (player, floor)
FloorService.OnFloorReleased = Signal.new() -- (player, floor)

local S
local floorOf = {} -- player -> index
local ownerOf = {} -- index -> player
local presence = {} -- [mallId][floor] -> { [player] = true }
local BUILDERS = { "StoreService", "WorkerService", "ProjectService", "RecoveryService" }

for _, mall in ipairs(Malls) do
	presence[mall.Id] = {}
	for f = 1, mall.Floors do
		presence[mall.Id][f] = {}
	end
end

function FloorService.GetFloor(player)
	return floorOf[player]
end

function FloorService.GetOwner(mallId, floor)
	local p = ownerOf[floor]
	if p and S.DataService.GetProfile(p) and S.DataService.GetProfile(p).UnlockedMalls[tostring(mallId)] then
		return p
	end
	return nil
end

function FloorService.PlayersOnFloor(mallId, floor)
	local list = {}
	for p in pairs(presence[mallId][floor]) do
		table.insert(list, p)
	end
	return list
end

function FloorService.IsFloorActive(mallId, floor)
	return next(presence[mallId][floor]) ~= nil
end

function FloorService.WhereIs(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	return S.MallService.LocateFloor(root.Position)
end

function FloorService.Teleport(player, cframe)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		char:PivotTo(cframe)
	end
end

function FloorService.TeleportHome(player)
	local profile = S.DataService.GetProfile(player)
	local floor = floorOf[player]
	if profile and floor then
		FloorService.Teleport(player, S.MallService.SpawnCFrame(profile.CurrentMall, floor))
	end
end

-- Builds the dynamic content of one mall floor for its owner (used on join and on mall unlock)
function FloorService.BuildMallFloor(player, mallId)
	local floor = floorOf[player]
	if not floor then
		return
	end
	for _, name in ipairs(BUILDERS) do
		local svc = S[name]
		if svc and svc.BuildFloor then
			local ok, err = pcall(svc.BuildFloor, player, mallId, floor)
			if not ok then
				warn(("[Shoprise] %s.BuildFloor failed: %s"):format(name, tostring(err)))
			end
		end
	end
end

local function setCollisionGroup(character)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end)
end

local function onLoaded(player, profile)
	local index
	for i = 1, Constants.MAX_PLAYERS do
		if not ownerOf[i] then
			index = i
			break
		end
	end
	if not index then
		player:Kick("This mall is full. Please try another server.")
		return
	end
	ownerOf[index] = player
	floorOf[player] = index
	for _, mall in ipairs(Malls) do
		if profile.UnlockedMalls[tostring(mall.Id)] then
			FloorService.BuildMallFloor(player, mall.Id)
		end
	end
	FloorService.OnFloorAssigned:Fire(player, index)
	if player.Character then
		FloorService.TeleportHome(player)
	end
	S.MessageService.Toast(player, ("Welcome to %s! You own floor %d."):format(Malls[profile.CurrentMall].Name, index), "good")
end

local function onUnloaded(player)
	local index = floorOf[player]
	if not index then
		return
	end
	FloorService.OnFloorReleased:Fire(player, index)
	for _, mall in ipairs(Malls) do
		local dyn = S.MallService.DynamicFolder(mall.Id, index)
		if dyn then
			dyn:ClearAllChildren()
		end
		presence[mall.Id][index][player] = nil
	end
	for _, mall in ipairs(Malls) do
		for f = 1, mall.Floors do
			presence[mall.Id][f][player] = nil
		end
	end
	ownerOf[index] = nil
	floorOf[player] = nil
end

function FloorService.Init(services)
	S = services
end

function FloorService.Start()
	S.DataService.OnLoaded:Connect(onLoaded)
	S.DataService.OnUnloaded:Connect(onUnloaded)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			setCollisionGroup(character)
			task.wait(0.2)
			FloorService.TeleportHome(player)
		end)
		if player.Character then
			setCollisionGroup(player.Character)
		end
	end)
	-- presence tracking
	task.spawn(function()
		while true do
			task.wait(1)
			for _, mall in ipairs(Malls) do
				for f = 1, mall.Floors do
					table.clear(presence[mall.Id][f])
				end
			end
			for _, player in ipairs(Players:GetPlayers()) do
				local mallId, floor = FloorService.WhereIs(player)
				if mallId then
					presence[mallId][floor][player] = true
				end
			end
		end
	end)
end

return FloorService
