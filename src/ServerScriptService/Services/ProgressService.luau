--[[
	ProgressService — milestones, short-term objectives, next-mall unlock, and the state snapshot
	pushed to each client (cash, stores, ledgers, workers, projects, objectives).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Config.Economy)
local Malls = require(ReplicatedStorage.Config.Malls)
local Stores = require(ReplicatedStorage.Config.Stores)
local Workers = require(ReplicatedStorage.Config.Workers)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Format = require(ReplicatedStorage.Shared.Format)

local ProgressService = {}
local S
local dirty = {} -- player -> true
local lastPush = {} -- player -> os.clock()

-- Milestones -----------------------------------------------------------------------------

local function milestoneDone(player, profile, mallId, ms)
	local m = profile.Malls[tostring(mallId)]
	if ms.Id == "OwnAllLots" then
		for _, lot in ipairs(Malls[mallId].Lots) do
			if not m.Lots[lot.Id] then
				return false
			end
		end
		return true
	elseif ms.Id == "Workers2" then
		return #m.Workers >= (ms.Count or 2)
	elseif ms.Id == "ProjectDone" then
		return m.ProjectComplete == true or S.ProjectService.IsComplete(mallId) and (m.ProjectContribution or 0) > 0
	elseif ms.Id == "Revenue" then
		local total = 0
		for _, lot in pairs(m.Lots) do
			total += lot.Ledger.Revenue or 0
		end
		return total >= (ms.Amount or 0)
	end
	return false
end

function ProgressService.MilestoneState(player, mallId)
	local profile = S.DataService.GetProfile(player)
	local cfg = Malls[mallId].UnlockNext
	if not profile or not cfg then
		return nil
	end
	local list, allDone = {}, true
	for _, ms in ipairs(cfg.Milestones) do
		local done = milestoneDone(player, profile, mallId, ms)
		allDone = allDone and done
		table.insert(list, { Id = ms.Id, Text = ms.Text, Done = done })
	end
	return { Milestones = list, AllDone = allDone, OpeningCost = cfg.OpeningCost, Text = cfg.Text, NextMall = Malls[mallId + 1] and Malls[mallId + 1].Name, Unlocked = profile.UnlockedMalls[tostring(mallId + 1)] == true }
end

function ProgressService.UnlockNextMall(player, mallId)
	local profile = S.DataService.GetProfile(player)
	local state = ProgressService.MilestoneState(player, mallId)
	if not profile or not state then
		return false
	end
	if state.Unlocked then
		S.MessageService.Toast(player, "Already unlocked. Use the Mall Transit sign to travel.", "info")
		return false
	end
	if not state.AllDone then
		S.MessageService.Toast(player, "Finish the business milestones first (see the Mall tab).", "bad")
		return false
	end
	if not S.EconomyService.TrySpend(player, state.OpeningCost, "Opening") then
		return false
	end
	local nextId = mallId + 1
	profile.UnlockedMalls[tostring(nextId)] = true
	profile.Malls[tostring(nextId)].Opened = true
	S.FloorService.BuildMallFloor(player, nextId)
	S.MessageService.Broadcast(("%s opened a floor in %s!"):format(player.DisplayName, Malls[nextId].Name), "big")
	Remotes.Effect:FireClient(player, { Kind = "Celebrate" })
	S.MessageService.Tip(player, "Unlock2", "Your Neighborhood stores keep running. Hire a Manager downtown and assign them to earn passive income from them.")
	ProgressService.Push(player)
	return true
end

-- Objectives (short-term guidance) ------------------------------------------------------------

local function objectives(player, profile)
	local list = {}
	local mallId = profile.CurrentMall
	local m = profile.Malls[tostring(mallId)]
	local stats = profile.Stats
	local served = stats.CustomersServed or 0
	local function add(text, done)
		table.insert(list, { Text = text, Done = done })
	end
	if mallId == 1 then
		add("Take a box from the delivery point and restock a shelf", (m.Lots.A and m.Lots.A.Stock or 0) > 0 or served > 0)
		add("Serve a customer at the counter", served >= 1)
		add("Buy an upgrade in the Business panel", (function()
			for _, lot in pairs(m.Lots) do
				if next(lot.Upgrades) then
					return true
				end
			end
			return false
		end)())
		add("Find and hire your first worker", #m.Workers >= 1)
		add("Lease the Clothing Shop", m.Lots.B ~= nil)
		add("Lease the Food Kiosk", m.Lots.C ~= nil)
		add("Fund the elevator restoration", m.ProjectComplete or S.ProjectService.IsComplete(1) and (m.ProjectContribution or 0) > 0)
		add("Unlock Downtown Mall (Mall tab)", profile.UnlockedMalls["2"] == true)
	else
		add("Order a delivery at the loading dock", (m.Stockroom and m.Stockroom.Boxes or 0) > 0 or next(m.Lots) ~= nil)
		add("Lease the Electronics Shop", m.Lots.A ~= nil)
		add("Move boxes through the stockroom to a shelf", (function()
			for _, lot in pairs(m.Lots) do
				if (lot.Stock or 0) > 0 or (lot.Ledger.Revenue or 0) > 0 then
					return true
				end
			end
			return false
		end)())
		add("Lease the Arcade", m.Lots.B ~= nil)
		add("Recruit the technician and the manager", #m.Workers >= 2)
		add("Assign the manager to Neighborhood Mall", profile.Malls["1"].ManagerAssigned == true)
		add("Fund the loading dock expansion", m.ProjectComplete == true)
	end
	-- first undone is the current objective
	local current
	for _, o in ipairs(list) do
		if not o.Done then
			current = o.Text
			break
		end
	end
	return list, current
end

-- Tutorial phases (persistent in profile.Tutorial):
--   Learn  : order -> take -> restock -> serve the first customer
--   Selling: no guidance until the shelves run empty for the first time
--   Refill : order -> take -> restock again
--   Hire   : the first worker mission (lost delivery: find the box, return it, hire the stocker)
local ANNOUNCE = {
	Refill = "📦 Your shelves are empty! Follow the arrows to restock.",
	Hire = "🤝 Great work! Time to get help: a courier lost a box on this floor. Follow the arrows.",
	Done = "🎉 Tutorial complete! You know the basics: keep shelves full, serve customers and grow your mall.",
}

local function announce(player, tut, phase)
	tut.Announced = tut.Announced or {}
	if not tut.Announced[phase] then
		tut.Announced[phase] = true
		S.MessageService.Toast(player, ANNOUNCE[phase], phase == "Done" and "good" or "info")
	end
end

local function stockSteps(st, carrying)
	if carrying == "StockBox" then
		return "Restock"
	elseif st.Pallet.Boxes > 0 or (st.Pallet.Loose or 0) > 0 then
		return "TakeBox"
	elseif st.Pallet.Pending > 0 then
		return "WaitBox"
	end
	return "OrderBox"
end

local function tutorialState(player, profile)
	profile.Tutorial = profile.Tutorial or { Restocks = 0, Announced = {} }
	local tut = profile.Tutorial
	if tut.Done or profile.CurrentMall ~= 1 then
		return nil
	end
	local mallData = profile.Malls["1"]
	if mallData.Discovered.LostDelivery then
		tut.Done = true
		announce(player, tut, "Done")
		return nil
	end
	local floor = S.FloorService.GetFloor(player)
	local st = floor and S.StoreService.Get(1, floor, "A")
	if not st or not st.Pallet or not st.Counter then
		return nil
	end
	local carrying = player.Character and player.Character:GetAttribute("Carrying")
	local shelf = S.StoreService.ShelfNeedingStock(st)
	local targets = {
		Store = (st.Frame * CFrame.new(0, 0, S.MallService.LOT_D / 2 + 5)).Position,
		Pallet = st.Pallet.Part.Position,
		Shelf = shelf and shelf.Part.Position or nil,
		Counter = st.Counter.Part.Position,
	}
	local served = (st.Data.Ledger.Served or 0) >= 1
	local stock = S.StoreService.TotalStock(st)
	local phase, step
	if not served then
		phase = "Learn"
		step = (stock > 0 and carrying ~= "StockBox") and "Serve" or stockSteps(st, carrying)
	else
		if stock == 0 then
			tut.SawEmpty = true
		end
		if not tut.SawEmpty then
			return nil -- selling: let the player play
		elseif not tut.RefillDone then
			phase = "Refill"
			step = stockSteps(st, carrying)
			if step == "OrderBox" then
				step = "Reorder"
			end
			announce(player, tut, "Refill")
		else
			phase = "Hire"
			announce(player, tut, "Hire")
			local m = S.WorkerService.LostDeliveryTargets(player, 1, floor)
			if not m then
				return nil
			end
			targets.Box, targets.Courier, targets.Candidate = m.Box, m.Courier, m.Candidate
			if m.Candidate then
				step = "HireWorker"
			elseif carrying == "LostBox" then
				step = "ReturnBox"
			elseif carrying then
				step = "FreeHands"
			else
				step = "FindBox"
			end
		end
	end
	return { Phase = phase, Step = step, Targets = targets }
end

-- the owner restocked one of their shelves by hand
function ProgressService.OnOwnerRestock(player)
	local profile = S.DataService.GetProfile(player)
	if not profile or not profile.Tutorial then
		return
	end
	local tut = profile.Tutorial
	tut.Restocks = (tut.Restocks or 0) + 1
	if tut.SawEmpty then
		tut.RefillDone = true
	end
	ProgressService.Push(player)
end

function ProgressService.TutorialStep(player)
	local profile = S.DataService.GetProfile(player)
	local t = profile and tutorialState(player, profile)
	return t and t.Step or nil
end

-- Snapshot -----------------------------------------------------------------------------------

local function snapshot(player)
	local profile = S.DataService.GetProfile(player)
	if not profile then
		return nil
	end
	local floor = S.FloorService.GetFloor(player)
	local malls = {}
	for _, mall in ipairs(Malls) do
		local m = profile.Malls[tostring(mall.Id)]
		local lots = {}
		for _, lotCfg in ipairs(mall.Lots) do
			local lot = m.Lots[lotCfg.Id]
			local cfg = Stores[lotCfg.Store]
			local entry = { Id = lotCfg.Id, Store = lotCfg.Store, Name = cfg.Name, Icon = cfg.ProductIcon, Cost = lotCfg.Cost, Owned = lot ~= nil, Interaction = cfg.Interaction }
			if lot then
				entry.Stock = lot.Stock
				entry.Capacity = (cfg.Shelves + (lot.Upgrades.ExtraShelf and 1 or 0)) * cfg.ShelfCapacity
				entry.Satisfaction = lot.Satisfaction
				entry.Ledger = lot.Ledger
				entry.Profit = S.EconomyService.Profit(lot.Ledger)
				entry.Upgrades = {}
				for _, up in ipairs(cfg.Upgrades) do
					table.insert(entry.Upgrades, { Id = up.Id, Name = up.Name, Desc = up.Desc, Cost = math.floor(up.Cost * mall.PriceMultiplier + 0.5), Owned = lot.Upgrades[up.Id] == true })
				end
				entry.UnitCost = math.floor(cfg.UnitCost * mall.PriceMultiplier + 0.5)
				entry.UnitPrice = math.floor(cfg.UnitPrice * mall.PriceMultiplier + 0.5)
				entry.BoxCost = math.floor(cfg.BoxUnits * cfg.UnitCost * mall.PriceMultiplier + 0.5)
				entry.HasPallet = not mall.Logistics and cfg.BoxUnits > 0
				local st = floor and S.StoreService.Get(mall.Id, floor, lotCfg.Id)
				if st and st.Pallet then
					entry.PalletBoxes = st.Pallet.Boxes
					entry.PalletPending = st.Pallet.Pending
				end
			end
			table.insert(lots, entry)
		end
		local workers = {}
		for _, w in ipairs(m.Workers) do
			local lvl, info = S.WorkerService.Level(w)
			table.insert(workers, { Id = w.Id, Type = w.Type, Name = Workers[w.Type].Name, Wage = Workers[w.Type].Wage, Lot = w.Lot, Level = lvl, LevelName = info.Label, Tasks = w.Tasks or 0, Unpaid = w.Unpaid == true, Managing = w.Managing })
		end
		malls[tostring(mall.Id)] = {
			Id = mall.Id, Name = mall.Name, Unlocked = profile.UnlockedMalls[tostring(mall.Id)] == true,
			Lots = lots, Workers = workers, ManagerAssigned = m.ManagerAssigned == true,
			Project = S.ProjectService.GetProgress(mall.Id), MyContribution = m.ProjectContribution or 0, ProjectCompleteForMe = m.ProjectComplete == true,
			Unlock = ProgressService.MilestoneState(player, mall.Id),
			Stockroom = m.Stockroom and { Boxes = m.Stockroom.Boxes, Capacity = m.Stockroom.Capacity, UpgradeCost = mall.Logistics.StockroomUpgrade.Cost, UpgradeCapacity = mall.Logistics.StockroomUpgrade.Capacity } or nil,
			Logistics = mall.Logistics and { DeliveryBoxes = S.ProjectService.DeliveryBoxes(mall.Id), CostPerBox = mall.Logistics.DeliveryCostPerBox } or nil,
		}
	end
	local objs, current = objectives(player, profile)
	return {
		Cash = profile.Cash,
		CurrentMall = profile.CurrentMall,
		Floor = floor,
		Malls = malls,
		Objectives = objs,
		CurrentObjective = current,
		Stats = { Served = profile.Stats.CustomersServed, Revenue = profile.Stats.LifetimeRevenue, Assist = profile.Stats.AssistEarned, Baskets = profile.Stats.BasketsReturned },
		NoSave = profile.NoSave == true,
		DevMode = S.DataService.IsDevMode(),
		MockSave = S.DataService.IsMock(),
		Accent = profile.Cosmetic.Accent,
		Tutorial = tutorialState(player, profile),
		Achievements = S.AchievementService and S.AchievementService.List(player) or {},
		Shop = S.ShopService and S.ShopService.State(player) or nil,
	}
end

function ProgressService.Push(player)
	dirty[player] = true
end

function ProgressService.PushNow(player)
	local snap = snapshot(player)
	if snap then
		lastPush[player] = os.clock()
		dirty[player] = nil
		Remotes.State:FireClient(player, snap)
	end
end

function ProgressService.Evaluate(player)
	-- milestones are derived on read; just make sure the client sees them
	ProgressService.Push(player)
end

function ProgressService.SetAccent(player, index)
	return S.ShopService.SetAccent(player, index)
end

function ProgressService.Init(services)
	S = services
end

function ProgressService.Start()
	S.EconomyService.OnCashChanged:Connect(function(player)
		dirty[player] = true
	end)
	S.FloorService.OnFloorAssigned:Connect(function(player)
		ProgressService.PushNow(player)
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			for player in pairs(dirty) do
				if player.Parent then
					local ok, err = pcall(ProgressService.PushNow, player)
					if not ok then
						warn("[Shoprise] push: " .. tostring(err))
						dirty[player] = nil
					end
				else
					dirty[player] = nil
				end
			end
			-- periodic refresh so ledgers / project boards stay current
			for _, player in ipairs(Players:GetPlayers()) do
				if (os.clock() - (lastPush[player] or 0)) > 5 and S.DataService.GetProfile(player) then
					dirty[player] = true
				end
			end
		end
	end)
end

return ProgressService
