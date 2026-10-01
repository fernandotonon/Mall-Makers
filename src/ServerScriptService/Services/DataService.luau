--[[
	DataService — loads / saves player profiles with a session lock so two servers never overwrite
	each other, autosaves, and saves on leave / shutdown.

	Storage layout (DataStore "MallMakers_v1", key "Player_<userId>"):
	  { Data = <profile>, Session = { Id = string, Time = os.time(), Job = game.JobId } | nil }

	Dev mode: in Studio (or Economy.Save.DevMode) the store name is prefixed with "Dev_", so
	production saves are never touched while testing. If DataStores are unavailable (Studio without
	API access) the profile is kept in memory and flagged NoSave so nothing is ever overwritten.
]]
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Config.Economy)
local Malls = require(ReplicatedStorage.Config.Malls)
local Signal = require(ReplicatedStorage.Shared.Signal)

local DataService = {}
DataService.OnLoaded = Signal.new() -- (player, profile)
DataService.OnUnloaded = Signal.new() -- (player)

local S
local profiles = {} -- player -> profile
local sessions = {} -- player -> session id
local store = nil
local usingMock = false
local devMode = RunService:IsStudio() or Economy.Save.DevMode
local storeName = (devMode and Economy.Save.DevPrefix or "") .. Economy.Save.StoreName

local function newProfile()
	local p = {
		Version = 1,
		Cash = Economy.StartingCash,
		CurrentMall = 1,
		UnlockedMalls = { ["1"] = true },
		Malls = {},
		Milestones = {},
		Stats = { LifetimeRevenue = 0, CustomersServed = 0, AssistEarned = 0, BasketsReturned = 0, SelfServes = {} },
		TipsSeen = {},
		Cosmetic = { Accent = 1 },
		Created = os.time(),
	}
	for _, mall in ipairs(Malls) do
		p.Malls[tostring(mall.Id)] = DataService.NewMallState(mall)
	end
	return p
end

function DataService.NewMallState(mall)
	local m = { Lots = {}, Workers = {}, Discovered = {}, ProjectContribution = 0, ProjectComplete = false, ManagerAssigned = false, Opened = false }
	for _, lot in ipairs(mall.Lots) do
		if lot.Starter then
			m.Lots[lot.Id] = DataService.NewLotState(lot.Store)
		end
	end
	if mall.Logistics then
		m.Stockroom = { Capacity = mall.Logistics.StockroomCapacity, Boxes = 0 }
	end
	return m
end

function DataService.NewLotState(storeType)
	return {
		Store = storeType,
		Stock = 0,
		Upgrades = {},
		Ledger = { Revenue = 0, StockCost = 0, Wages = 0, Sales = 0, Served = 0 },
		Satisfaction = Economy.Satisfaction.Start,
		Machines = nil,
	}
end

-- fill in anything an old profile lacks (forward-compatible migrations)
local function migrate(p)
	local fresh = newProfile()
	for k, v in pairs(fresh) do
		if p[k] == nil then
			p[k] = v
		end
	end
	for id, m in pairs(fresh.Malls) do
		if p.Malls[id] == nil then
			p.Malls[id] = m
		else
			for k, v in pairs(m) do
				if p.Malls[id][k] == nil then
					p.Malls[id][k] = v
				end
			end
		end
	end
	for k, v in pairs(fresh.Stats) do
		if p.Stats[k] == nil then
			p.Stats[k] = v
		end
	end
	return p
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

-- In-memory stand-in with DataStore UpdateAsync semantics, used in Studio when DataStores are not
-- available (unpublished place). Lets the full load / lock / save path run in tests.
local MockStore = {}
MockStore.__index = MockStore
function MockStore.new()
	return setmetatable({ data = {} }, MockStore)
end
function MockStore:UpdateAsync(k, fn)
	local old = self.data[k] and HttpService:JSONDecode(self.data[k]) or nil
	local new = fn(old)
	if new ~= nil then
		self.data[k] = HttpService:JSONEncode(new)
	end
	return new
end
function MockStore:Peek(k)
	return self.data[k] and HttpService:JSONDecode(self.data[k]) or nil
end
DataService.MockStore = MockStore

local function tryLoad(player)
	local sessionId = HttpService:GenerateGUID(false)
	local result, blocked = nil, false
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			old = old or {}
			local lock = old.Session
			if lock and lock.Id and (os.time() - (lock.Time or 0)) < Economy.Save.SessionLockSeconds and lock.Job ~= game.JobId then
				blocked = true
				return nil -- do not write; another live server owns this profile
			end
			old.Data = old.Data or newProfile()
			old.Session = { Id = sessionId, Time = os.time(), Job = game.JobId }
			result = old.Data
			return old
		end)
	end)
	if not ok then
		return nil, "error", err
	end
	if blocked then
		return nil, "locked"
	end
	return result, sessionId
end

local function writeProfile(player, release)
	local profile = profiles[player]
	if not profile or profile.NoSave then
		return false
	end
	local sessionId = sessions[player]
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			old = old or {}
			if old.Session and old.Session.Id and old.Session.Id ~= sessionId then
				-- someone else took over the session; refuse to overwrite their data
				return nil
			end
			local copy = table.clone(profile)
			copy.NoSave = nil
			copy.LastSave = os.time()
			old.Data = copy
			old.Session = release and nil or { Id = sessionId, Time = os.time(), Job = game.JobId }
			return old
		end)
	end)
	if not ok then
		warn(("[MallMakers] save failed for %s: %s"):format(player.Name, tostring(err)))
		return false
	end
	return true
end

function DataService.GetProfile(player)
	return profiles[player]
end

function DataService.Save(player, release)
	return writeProfile(player, release == true)
end

-- test helper: install a profile for a (mock) player object without firing OnLoaded
function DataService.Attach(player, profile)
	profiles[player] = profile
end

function DataService.PeekStored(player)
	if store and store.Peek then
		return store:Peek(keyFor(player))
	end
	return nil
end

-- Loads (and session-locks) a profile. Returns profile | nil, status ("ok" | "locked" | "error" | "nostore")
function DataService.Load(player)
	local profile, sessionId, err
	if not store then
		return nil, "nostore"
	end
	for attempt = 1, Economy.Save.LoadRetries do
		profile, sessionId, err = tryLoad(player)
		if profile then
			sessions[player] = sessionId
			return profile, "ok"
		end
		if sessionId == "locked" then
			task.wait(attempt == Economy.Save.LoadRetries and 0 or 3)
		else
			warn(("[MallMakers] load attempt %d for %s failed: %s"):format(attempt, player.Name, tostring(err)))
			task.wait(2)
		end
	end
	return nil, sessionId == "locked" and "locked" or "error", err
end

function DataService.Unload(player)
	profiles[player] = nil
	sessions[player] = nil
end

local function onPlayerAdded(player)
	local profile, status, err = DataService.Load(player)
	if status == "locked" then
		player:Kick("Your progress is still being saved by another server. Please rejoin in a minute.")
		return
	end
	if not profile then
		-- DataStores unavailable (Studio without API access, or persistent errors): play in memory, never save
		profile = newProfile()
		profile.NoSave = true
		warn(("[MallMakers] %s is playing with an in-memory profile (no saving): %s"):format(player.Name, tostring(err)))
	end
	if not player.Parent then
		return
	end
	profile = migrate(profile)
	profiles[player] = profile
	DataService.OnLoaded:Fire(player, profile)
end

local function onPlayerRemoving(player)
	if profiles[player] then
		DataService.OnUnloaded:Fire(player)
		writeProfile(player, true)
		profiles[player] = nil
		sessions[player] = nil
	end
end

function DataService.Init(services)
	S = services
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(storeName)
	end)
	if not ok then
		if RunService:IsStudio() then
			warn("[MallMakers] DataStore unavailable in Studio, using an in-memory mock store for this session: " .. tostring(err))
			store = MockStore.new()
			usingMock = true
		else
			warn("[MallMakers] DataStore unavailable: " .. tostring(err))
			store = nil
		end
	end
	print(("[MallMakers] DataService store=%s devMode=%s"):format(storeName, tostring(devMode)))
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	task.spawn(function()
		while true do
			task.wait(Economy.Save.AutosaveSeconds)
			for player in pairs(profiles) do
				writeProfile(player, false)
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and (not store or usingMock) then
			return
		end
		for player in pairs(profiles) do
			writeProfile(player, true)
		end
	end)
end

function DataService.IsDevMode()
	return devMode
end

function DataService.IsMock()
	return usingMock
end

-- Studio tests only: direct access to the mock store (nil against a real DataStore)
function DataService.DebugStore()
	if usingMock then
		return store
	end
	return nil
end

-- Studio / debug helper: wipe the in-memory profile and rebuild the floor (dev only)
function DataService.ResetProfile(player)
	if not devMode then
		return false
	end
	profiles[player] = migrate(newProfile())
	return true
end

return DataService
