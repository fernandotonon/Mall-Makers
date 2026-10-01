--[[
	RecoveryService — the manual earning activity: stray shopping baskets appear on every floor;
	carry one back to the basket stand for a small reward. Always available, so nobody is ever stuck.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Config.Economy)
local Malls = require(ReplicatedStorage.Config.Malls)
local AssetRegistry = require(ReplicatedStorage.Shared.AssetRegistry)
local Format = require(ReplicatedStorage.Shared.Format)
local Carry = require(script.Parent.Carry)

local RecoveryService = {}
local S

local function randomCorridorPoint()
	if math.random() < 0.5 then
		return Vector3.new(math.random(-78, 78), 0, math.random(32, 48))
	end
	return Vector3.new(math.random(-78, 78), 0, math.random(-15, -3))
end

local function spawnBasket(mallId, floor)
	local parent = S.MallService.StaticFolder(mallId, floor)
	local pos = S.MallService.ToWorld(mallId, floor, randomCorridorPoint())
	local m = AssetRegistry.Place("Basket", CFrame.new(pos), parent, math.random(0, 359))
	m.Name = "StrayBasket"
	local anchor = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up basket"
	prompt.ObjectText = "Stray basket"
	prompt.MaxActivationDistance = 8
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		if Carry.Get(player) then
			S.MessageService.Toast(player, "Your hands are full.", "bad")
			return
		end
		if Carry.Give(player, "Basket") then
			m:Destroy()
			S.MessageService.Toast(player, ("Return it to the basket stand near the entrance for %s."):format(Format.Cash(Economy.Recovery.BasketReward)), "info")
			task.delay(Economy.Recovery.BasketRespawnSeconds, spawnBasket, mallId, floor)
		end
	end)
end

local function buildStand(mallId, floor)
	local parent = S.MallService.StaticFolder(mallId, floor)
	local pos = S.MallService.ToWorld(mallId, floor, S.MallService.BASKET_STAND)
	local stand = Instance.new("Part")
	stand.Name = "BasketStand"
	stand.Size = Vector3.new(4, 1, 3)
	stand.Anchored = true
	stand.Color = AssetRegistry.Colors.Teal
	stand.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0))
	stand.Parent = parent
	for i = 0, 2 do
		local b = AssetRegistry.Place("Basket", CFrame.new(pos + Vector3.new(0, 1 + i * 0.5, 0)), parent, 0)
		for _, d in ipairs(b:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
			end
		end
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(180, 40)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.MaxDistance = 60
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
	tl.BackgroundTransparency = 0.2
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBold
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.Text = ("🧺 Basket return · %s each"):format(Format.Cash(Economy.Recovery.BasketReward))
	Instance.new("UICorner", tl).CornerRadius = UDim.new(0, 8)
	tl.Parent = bb
	bb.Parent = stand
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Return basket"
	prompt.ObjectText = "Basket stand"
	prompt.MaxActivationDistance = 8
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand
	prompt.Triggered:Connect(function(player)
		if not Carry.Take(player, "Basket") then
			S.MessageService.Toast(player, "Bring a stray basket here to earn cash.", "info")
			return
		end
		S.EconomyService.AddCash(player, Economy.Recovery.BasketReward, "Basket", stand.Position)
		local profile = S.DataService.GetProfile(player)
		if profile then
			profile.Stats.BasketsReturned += 1
		end
		if S.ProgressService then
			S.ProgressService.Evaluate(player)
		end
	end)
end

function RecoveryService.BuildFloor(player, mallId, floor) end -- stands and baskets are static per floor

function RecoveryService.Init(services)
	S = services
end

function RecoveryService.Start()
	for _, mall in ipairs(Malls) do
		for f = 1, mall.Floors do
			buildStand(mall.Id, f)
			for _ = 1, Economy.Recovery.BasketsPerFloor do
				spawnBasket(mall.Id, f)
			end
		end
	end
end

return RecoveryService
