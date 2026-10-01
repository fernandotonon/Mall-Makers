--[[
	TransitService — the atrium elevator (teleport between floors once the project is funded) and
	travel between malls (own floor when unlocked, a friend's floor as a visitor otherwise).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Malls = require(ReplicatedStorage.Config.Malls)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AssetRegistry = require(ReplicatedStorage.Shared.AssetRegistry)

local TransitService = {}
local S
local elevatorEnabled = {} -- mallId -> bool
local signs = {} -- [mallId][floor] -> status label

local function fadeTeleport(player, cframe, text)
	Remotes.Effect:FireClient(player, { Kind = "Fade", Text = text })
	task.wait(0.45)
	S.FloorService.Teleport(player, cframe)
end

function TransitService.SetElevatorEnabled(mallId, enabled)
	elevatorEnabled[mallId] = enabled
	for _, label in pairs(signs[mallId] or {}) do
		label.Text = enabled and "ELEVATOR" or "OUT OF ORDER\nfund the project board"
		label.TextColor3 = enabled and Color3.fromRGB(120, 230, 150) or Color3.fromRGB(255, 120, 110)
	end
end

function TransitService.RideElevator(player, mallId, targetFloor)
	if not elevatorEnabled[mallId] then
		S.MessageService.Toast(player, "The elevator is out of order. Fund its restoration at the project board.", "bad")
		return false
	end
	local where, floor = S.FloorService.WhereIs(player)
	if where ~= mallId then
		return false
	end
	if floor == targetFloor then
		S.MessageService.Toast(player, "You are already on this floor.", "info")
		return false
	end
	local landing = S.MallService.ElevatorLanding(mallId, targetFloor)
	fadeTeleport(player, CFrame.lookAt(landing + Vector3.new(0, 3.5, 0), landing + Vector3.new(0, 3.5, -10)), ("Floor %d"):format(targetFloor))
	return true
end

function TransitService.Travel(player, targetMall)
	local profile = S.DataService.GetProfile(player)
	if not profile then
		return false
	end
	local mall = Malls[targetMall]
	if not mall then
		return false
	end
	local myFloor = S.FloorService.GetFloor(player)
	if profile.UnlockedMalls[tostring(targetMall)] then
		profile.CurrentMall = targetMall
		fadeTeleport(player, S.MallService.SpawnCFrame(targetMall, myFloor), mall.Name)
		S.MessageService.Toast(player, ("Welcome to %s, floor %d."):format(mall.Name, myFloor), "good")
		if targetMall > 1 then
			S.MessageService.Tip(player, "Mall2Arrive", "Deliveries here arrive at the loading dock. Store boxes in the stockroom, then carry them to your shops.")
		end
		if S.ProgressService then
			S.ProgressService.Push(player)
		end
		return true
	end
	-- visitor: go to a friend who owns a floor here
	for _, other in ipairs(Players:GetPlayers()) do
		local op = S.DataService.GetProfile(other)
		if other ~= player and op and op.UnlockedMalls[tostring(targetMall)] then
			local f = S.FloorService.GetFloor(other)
			if f then
				fadeTeleport(player, S.MallService.SpawnCFrame(targetMall, f), ("Visiting %s"):format(other.DisplayName))
				S.MessageService.Toast(player, ("You are visiting %s's floor in %s. Help out to earn assist bonuses!"):format(other.DisplayName, mall.Name), "good")
				return true
			end
		end
	end
	S.MessageService.Toast(player, ("Unlock %s first (Mall tab), or visit a friend who already has a floor there."):format(mall.Name), "bad")
	return false
end

local function buildElevatorButtons(mallId, floor)
	local mall = Malls[mallId]
	local parent = S.MallService.StaticFolder(mallId, floor)
	local base = S.MallService.ToWorld(mallId, floor, S.MallService.ELEVATOR_POS)
	-- status sign above the doors
	local sign = Instance.new("Part")
	sign.Size = Vector3.new(8, 1.6, 0.2)
	sign.Anchored = true
	sign.CanCollide = false
	sign.Color = Color3.fromRGB(35, 40, 50)
	sign.CFrame = CFrame.new(base + Vector3.new(0, 10.5, -2.3))
	sign.Parent = parent
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(400, 80)
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBold
	tl.Text = "ELEVATOR"
	tl.Parent = sg
	sg.Parent = sign
	signs[mallId] = signs[mallId] or {}
	signs[mallId][floor] = tl
	-- one button per floor on a panel beside the doors
	for k = 1, mall.Floors do
		local btn = Instance.new("Part")
		btn.Name = "ElevatorButton" .. k
		btn.Size = Vector3.new(1.2, 1.2, 0.3)
		btn.Anchored = true
		btn.CanCollide = false
		btn.Color = k == floor and Color3.fromRGB(120, 120, 130) or Color3.fromRGB(240, 120, 100)
		btn.CFrame = CFrame.new(base + Vector3.new(6.5, 2.5 + (mall.Floors - k) * 1.5, -2.2))
		btn.Parent = parent
		if k ~= floor then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = ("Floor %d"):format(k)
			prompt.ObjectText = "Elevator"
			prompt.MaxActivationDistance = 9
			prompt.HoldDuration = 0
			prompt.RequiresLineOfSight = false
			prompt.UIOffset = Vector2.new(0, (k - floor) * 5)
			prompt.Parent = btn
			prompt.Triggered:Connect(function(player)
				TransitService.RideElevator(player, mallId, k)
			end)
		end
	end
end

local function buildTransitSign(mallId, floor)
	local parent = S.MallService.StaticFolder(mallId, floor)
	local pos = S.MallService.ToWorld(mallId, floor, Vector3.new(10, 0, 50))
	local kiosk = AssetRegistry.Place("Barricade", CFrame.new(pos), parent, 0)
	local anchor = kiosk.PrimaryPart or kiosk:FindFirstChildWhichIsA("BasePart")
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(200, 50)
	bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.MaxDistance = 60
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
	tl.BackgroundTransparency = 0.2
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBold
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.Text = "🚌 Mall Transit"
	Instance.new("UICorner", tl).CornerRadius = UDim.new(0, 8)
	tl.Parent = bb
	bb.Parent = anchor
	local offset = 0
	for _, mall in ipairs(Malls) do
		if mall.Id ~= mallId then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Travel to " .. mall.Name
			prompt.ObjectText = "Mall Transit"
			prompt.MaxActivationDistance = 10
			prompt.HoldDuration = 0.5
			prompt.RequiresLineOfSight = false
			prompt.UIOffset = Vector2.new(0, offset)
			offset += 60
			prompt.Parent = anchor
			prompt.Triggered:Connect(function(player)
				TransitService.Travel(player, mall.Id)
			end)
		end
	end
end

function TransitService.Init(services)
	S = services
end

function TransitService.Start()
	for _, mall in ipairs(Malls) do
		elevatorEnabled[mall.Id] = mall.Project.Id ~= "Elevator" -- malls without an elevator project have a working elevator
		for f = 1, mall.Floors do
			buildElevatorButtons(mall.Id, f)
			buildTransitSign(mall.Id, f)
		end
		TransitService.SetElevatorEnabled(mall.Id, elevatorEnabled[mall.Id])
	end
end

return TransitService
