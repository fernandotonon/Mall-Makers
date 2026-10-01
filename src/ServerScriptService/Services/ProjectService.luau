--[[
	ProjectService — shared mall projects (Mall 1: elevator restoration, Mall 2: loading dock).
	Server progress = sum of the saved contributions of the players present (capped). When it reaches
	the cost the project completes for the server; every present contributor gets it saved as complete,
	so solo players keep their progress and co-op just gets there faster.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Malls = require(ReplicatedStorage.Config.Malls)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Format = require(ReplicatedStorage.Shared.Format)
local AssetRegistry = require(ReplicatedStorage.Shared.AssetRegistry)

local ProjectService = {}
local S
local complete = {} -- mallId -> bool (server session)
local boards = {} -- [mallId][floor] = { Gui, Label, Bar }

local function profilesIn(mallId)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local prof = S.DataService.GetProfile(p)
		if prof then
			table.insert(list, { Player = p, Mall = prof.Malls[tostring(mallId)] })
		end
	end
	return list
end

function ProjectService.GetProgress(mallId)
	local cfg = Malls[mallId].Project
	local total, contributors = 0, {}
	for _, e in ipairs(profilesIn(mallId)) do
		local c = e.Mall.ProjectContribution or 0
		if c > 0 then
			contributors[e.Player.DisplayName] = c
		end
		total += c
	end
	total = math.min(total, cfg.Cost)
	return { Progress = complete[mallId] and cfg.Cost or total, Cost = cfg.Cost, Contributors = contributors, Complete = complete[mallId] == true, Name = cfg.Name, Desc = cfg.Desc, Step = cfg.Step }
end

function ProjectService.IsComplete(mallId)
	return complete[mallId] == true
end

function ProjectService.IsCompleteFor(player, mallId)
	local prof = S.DataService.GetProfile(player)
	return prof and prof.Malls[tostring(mallId)].ProjectComplete == true
end

local function refreshBoards(mallId)
	local info = ProjectService.GetProgress(mallId)
	for _, b in pairs(boards[mallId] or {}) do
		b.Label.Text = ("%s\n%s / %s%s"):format(info.Name, Format.Cash(info.Progress), Format.Cash(info.Cost), info.Complete and "  ✔ DONE" or "")
		b.Bar.Size = UDim2.fromScale(math.clamp(info.Progress / info.Cost, 0, 1), 1)
		b.Prompt.Enabled = not info.Complete
	end
	Remotes.WorldState:FireAllClients({ Kind = "Project", MallId = mallId, Info = info })
end

local function finish(mallId)
	if complete[mallId] then
		return
	end
	complete[mallId] = true
	local cfg = Malls[mallId].Project
	for _, e in ipairs(profilesIn(mallId)) do
		if (e.Mall.ProjectContribution or 0) > 0 then
			e.Mall.ProjectComplete = true
		end
	end
	S.MessageService.Broadcast(cfg.CompleteText, "big")
	for _, p in ipairs(Players:GetPlayers()) do
		Remotes.Effect:FireClient(p, { Kind = "Celebrate" })
	end
	if S.TransitService and cfg.Id == "Elevator" then
		S.TransitService.SetElevatorEnabled(mallId, true)
	end
	refreshBoards(mallId)
	if S.ProgressService then
		for _, p in ipairs(Players:GetPlayers()) do
			S.ProgressService.Evaluate(p)
		end
	end
end

function ProjectService.Recompute(mallId)
	local cfg = Malls[mallId].Project
	local info = ProjectService.GetProgress(mallId)
	local anyDone = false
	for _, e in ipairs(profilesIn(mallId)) do
		if e.Mall.ProjectComplete then
			anyDone = true
		end
	end
	if anyDone or info.Progress >= cfg.Cost then
		finish(mallId)
	else
		refreshBoards(mallId)
	end
end

function ProjectService.Contribute(player, mallId, amount)
	local cfg = Malls[mallId].Project
	if complete[mallId] then
		S.MessageService.Toast(player, "This project is already complete.", "info")
		return false
	end
	local prof = S.DataService.GetProfile(player)
	if not prof or not prof.UnlockedMalls[tostring(mallId)] then
		S.MessageService.Toast(player, "Only players with a floor in this mall can fund its project.", "info")
		return false
	end
	amount = math.min(amount or cfg.Step, cfg.Cost - ProjectService.GetProgress(mallId).Progress)
	if amount <= 0 then
		return false
	end
	if not S.EconomyService.TrySpend(player, amount, "Project") then
		return false
	end
	local m = prof.Malls[tostring(mallId)]
	m.ProjectContribution = (m.ProjectContribution or 0) + amount
	S.MessageService.Toast(player, ("Contributed %s to %s"):format(Format.Cash(amount), cfg.Name), "good")
	S.MessageService.Tip(player, "Project", "Shared projects are funded together. Everyone who chips in keeps the result, and you can always finish one alone.")
	ProjectService.Recompute(mallId)
	if S.ProgressService then
		S.ProgressService.Evaluate(player)
	end
	return true
end

function ProjectService.DeliveryBoxes(mallId)
	local mall = Malls[mallId]
	if mall.Logistics then
		if complete[mallId] and mall.Project.DeliveryBoxes then
			return mall.Project.DeliveryBoxes
		end
		return mall.Logistics.DeliveryBoxes
	end
	return 0
end

-- A project board on every floor of every mall (static; anyone can contribute from any floor)
local function buildBoard(mallId, floor)
	local cfg = Malls[mallId].Project
	local pos = S.MallService.ToWorld(mallId, floor, S.MallService.BOARD_POS)
	local parent = S.MallService.StaticFolder(mallId, floor)
	local kiosk = AssetRegistry.Place("InfoKiosk", CFrame.new(pos), parent, 0)
	local anchor = kiosk.PrimaryPart or kiosk:FindFirstChildWhichIsA("BasePart")
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 90)
	bb.StudsOffset = Vector3.new(0, 9, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 90
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -12, 0.65, 0)
	label.Position = UDim2.fromOffset(6, 4)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = cfg.Name
	label.Parent = frame
	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -12, 0.2, 0)
	barBg.Position = UDim2.new(0, 6, 0.74, 0)
	barBg.BackgroundColor3 = Color3.fromRGB(80, 85, 95)
	barBg.BorderSizePixel = 0
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 6)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(0, 1)
	bar.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
	bar.BorderSizePixel = 0
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)
	bar.Parent = barBg
	barBg.Parent = frame
	frame.Parent = bb
	bb.Parent = anchor
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = ("Contribute %s"):format(Format.Cash(cfg.Step))
	prompt.ObjectText = cfg.Name
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration = 0.3
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		ProjectService.Contribute(player, mallId, cfg.Step)
	end)
	boards[mallId] = boards[mallId] or {}
	boards[mallId][floor] = { Label = label, Bar = bar, Prompt = prompt }
end

function ProjectService.BuildFloor(player, mallId, floor) end -- boards are static

function ProjectService.Init(services)
	S = services
end

function ProjectService.Start()
	for _, mall in ipairs(Malls) do
		for f = 1, mall.Floors do
			buildBoard(mall.Id, f)
		end
		refreshBoards(mall.Id)
	end
	S.FloorService.OnFloorAssigned:Connect(function(player)
		for _, mall in ipairs(Malls) do
			ProjectService.Recompute(mall.Id)
		end
	end)
	S.FloorService.OnFloorReleased:Connect(function()
		for _, mall in ipairs(Malls) do
			refreshBoards(mall.Id)
		end
	end)
end

return ProjectService
