--[[
	LeaderboardService — all-time boards (richest, top sellers, most customers served) shown on the
	south wall of every floor. Values live in OrderedDataStores; each player writes at most every
	WriteIntervalSeconds and on leave. Without DataStore access (Studio) the boards show the players in
	this server so the layout can still be checked.
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Config.Economy)
local Malls = require(ReplicatedStorage.Config.Malls)
local Format = require(ReplicatedStorage.Shared.Format)
local AssetRegistry = require(ReplicatedStorage.Shared.AssetRegistry)

local LeaderboardService = {}
local S
local CFG = Economy.Leaderboards
local stores = {} -- boardId -> OrderedDataStore | nil
local boards = {} -- boardId -> list of { Rows = {TextLabel...}, Title }
local nameCache = {} -- userId -> name
local lastWrite = {} -- player -> os.clock()
local usable = false

local function readPath(profile, path)
	local v = profile
	for seg in path:gmatch("[^.]+") do
		v = v and v[seg]
	end
	return tonumber(v) or 0
end

local function nameOf(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		nameCache[userId] = p.DisplayName
		return p.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = ok and name or ("user " .. userId)
	return nameCache[userId]
end

local function writePlayer(player)
	local profile = S.DataService.GetProfile(player)
	if not profile or profile.NoSave or not usable then
		return
	end
	for _, b in ipairs(CFG.Boards) do
		local store = stores[b.Id]
		if store then
			local value = math.max(0, math.floor(readPath(profile, b.Path)))
			pcall(store.SetAsync, store, tostring(player.UserId), value)
		end
	end
	lastWrite[player] = os.clock()
end

-- top rows for a board: { {Name, Value}, ... }
local function fetch(b)
	local rows = {}
	local store = stores[b.Id]
	if usable and store then
		local ok, pages = pcall(store.GetSortedAsync, store, false, CFG.TopN)
		if ok then
			for _, e in ipairs(pages:GetCurrentPage()) do
				table.insert(rows, { Name = nameOf(tonumber(e.key) or 0), Value = e.value })
			end
			return rows
		end
	end
	-- fallback: players in this server
	for _, p in ipairs(Players:GetPlayers()) do
		local profile = S.DataService.GetProfile(p)
		if profile then
			table.insert(rows, { Name = p.DisplayName, Value = readPath(profile, b.Path) })
		end
	end
	table.sort(rows, function(a, c)
		return a.Value > c.Value
	end)
	return rows
end

local function refresh()
	for _, b in ipairs(CFG.Boards) do
		local rows = fetch(b)
		for _, board in ipairs(boards[b.Id] or {}) do
			for i, label in ipairs(board.Rows) do
				local r = rows[i]
				label.Text = r and ("%d.  %s   %s"):format(i, r.Name, b.Id == "Served" and Format.Short(r.Value) or Format.Cash(r.Value)) or ("%d.  —"):format(i)
				label.TextColor3 = i == 1 and Color3.fromRGB(255, 215, 90) or Color3.new(1, 1, 1)
			end
		end
	end
end

local function buildBoard(mallId, floor, index, b)
	local parent = S.MallService.StaticFolder(mallId, floor)
	local o = S.MallService.FloorOrigin(mallId, floor)
	local x = 40 + (index - 1) * 9
	local part = Instance.new("Part")
	part.Name = "Leaderboard_" .. b.Id
	part.Size = Vector3.new(8, 9, 0.4)
	part.Anchored = true
	part.CanCollide = false
	part.Color = Color3.fromRGB(35, 40, 50)
	part.CFrame = CFrame.new(o.X + x, o.Y + 6.5, o.Z + S.MallService.HALF_Z - 0.8) -- Front (-Z) faces into the mall
	part.Parent = parent
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(400, 450)
	sg.Parent = part
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 46)
	title.Position = UDim2.fromOffset(8, 6)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = AssetRegistry.Colors.Coral
	title.Text = "🏆 " .. b.Title
	title.Parent = sg
	local rows = {}
	for i = 1, CFG.TopN do
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -24, 0, 36)
		l.Position = UDim2.fromOffset(12, 56 + (i - 1) * 38)
		l.BackgroundTransparency = 1
		l.TextScaled = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = Color3.new(1, 1, 1)
		l.Text = ("%d.  —"):format(i)
		l.Parent = sg
		rows[i] = l
	end
	boards[b.Id] = boards[b.Id] or {}
	table.insert(boards[b.Id], { Rows = rows })
end

function LeaderboardService.Init(services)
	S = services
	local prefix = S.DataService.IsDevMode() and Economy.Save.DevPrefix or ""
	for _, b in ipairs(CFG.Boards) do
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, prefix .. "Shoprise_LB_v1_" .. b.Id)
		stores[b.Id] = ok and store or nil
	end
	-- DataStores answer only in published places (or Studio with API access); probe once
	local probe = stores[CFG.Boards[1].Id]
	if probe then
		local ok = pcall(probe.GetSortedAsync, probe, false, 1)
		usable = ok
	end
	if not usable then
		warn("[Shoprise] leaderboards: OrderedDataStores unavailable here, showing this server's players only")
	end
end

function LeaderboardService.Start()
	for _, mall in ipairs(Malls) do
		for f = 1, mall.Floors do
			for i, b in ipairs(CFG.Boards) do
				buildBoard(mall.Id, f, i, b)
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		writePlayer(player)
		lastWrite[player] = nil
	end)
	task.spawn(function()
		while true do
			pcall(refresh)
			task.wait(CFG.RefreshSeconds)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(15)
			for _, p in ipairs(Players:GetPlayers()) do
				if (os.clock() - (lastWrite[p] or 0)) >= CFG.WriteIntervalSeconds then
					writePlayer(p)
				end
			end
		end
	end)
	-- refresh the server-player fallback quickly so the boards react during a session
	local pending = false
	S.EconomyService.OnCashChanged:Connect(function()
		if usable or pending then
			return
		end
		pending = true
		task.delay(5, function()
			pending = false
			pcall(refresh)
		end)
	end)
end

return LeaderboardService
