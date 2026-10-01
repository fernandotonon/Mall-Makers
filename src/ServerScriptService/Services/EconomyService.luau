--[[
	EconomyService — the only place cash changes. Also: leaderstats, store ledgers, wage ticks and
	previous-mall (managed) income. Every number comes from the Config tables.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Economy = require(ReplicatedStorage.Config.Economy)
local Malls = require(ReplicatedStorage.Config.Malls)
local Workers = require(ReplicatedStorage.Config.Workers)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Format = require(ReplicatedStorage.Shared.Format)

local EconomyService = {}
EconomyService.OnCashChanged = Signal.new() -- (player, newCash, delta, reason)

local S

local function profileOf(player)
	return S.DataService.GetProfile(player)
end

function EconomyService.GetCash(player)
	local p = profileOf(player)
	return p and p.Cash or 0
end

local function setCash(player, value, delta, reason, pos)
	local p = profileOf(player)
	if not p then
		return
	end
	p.Cash = math.max(0, math.floor(value + 0.5))
	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Cash") then
		ls.Cash.Value = p.Cash
	end
	if pos and delta ~= 0 then
		Remotes.Effect:FireClient(player, { Kind = "Money", Pos = pos, Amount = delta })
	end
	EconomyService.OnCashChanged:Fire(player, p.Cash, delta, reason)
end

function EconomyService.AddCash(player, amount, reason, pos)
	if amount <= 0 then
		return
	end
	setCash(player, EconomyService.GetCash(player) + amount, amount, reason, pos)
end

-- returns true when the amount was deducted
function EconomyService.TrySpend(player, amount, reason, pos)
	amount = math.floor(amount + 0.5)
	if amount < 0 then
		return false
	end
	local cash = EconomyService.GetCash(player)
	if cash < amount then
		S.MessageService.Toast(player, ("Not enough cash: need %s, you have %s"):format(Format.Cash(amount), Format.Cash(cash)), "bad")
		return false
	end
	setCash(player, cash - amount, -amount, reason, pos)
	return true
end

-- Ledger ------------------------------------------------------------------------

function EconomyService.GetLedger(player, mallId, lotId)
	local p = profileOf(player)
	local lot = p and p.Malls[tostring(mallId)] and p.Malls[tostring(mallId)].Lots[lotId]
	return lot and lot.Ledger
end

function EconomyService.Record(player, mallId, lotId, field, amount)
	local ledger = EconomyService.GetLedger(player, mallId, lotId)
	if ledger then
		ledger[field] = (ledger[field] or 0) + amount
	end
	if field == "Revenue" then
		local p = profileOf(player)
		if p then
			p.Stats.LifetimeRevenue += amount
		end
	end
end

function EconomyService.Profit(ledger)
	return (ledger.Revenue or 0) - (ledger.StockCost or 0) - (ledger.Wages or 0)
end

-- Wages -------------------------------------------------------------------------

local function payWages(player)
	local p = profileOf(player)
	if not p then
		return
	end
	local paused = 0
	for mallKey, mall in pairs(p.Malls) do
		for _, w in ipairs(mall.Workers) do
			local cfg = Workers[w.Type]
			local wage = cfg and cfg.Wage or 0
			if p.Cash >= wage then
				setCash(player, p.Cash - wage, -wage, "Wages")
				w.Unpaid = false
				if w.Lot and mall.Lots[w.Lot] then
					mall.Lots[w.Lot].Ledger.Wages += wage
				end
			else
				w.Unpaid = true
				paused += 1
			end
		end
	end
	if paused > 0 then
		S.MessageService.Toast(player, ("%d worker(s) are on break: you could not cover their wages. Earn cash (sell stock or return baskets) to resume them."):format(paused), "bad")
	end
end

-- Previous malls with a manager assigned earn a modest net income while the player is online.
local function managedIncome(player)
	local p = profileOf(player)
	if not p then
		return
	end
	local total = 0
	for _, mall in ipairs(Malls) do
		local m = p.Malls[tostring(mall.Id)]
		if m and m.ManagerAssigned and p.CurrentMall ~= mall.Id then
			local stores = 0
			for lotId, lot in pairs(m.Lots) do
				local hasWorker = false
				for _, w in ipairs(m.Workers) do
					if w.Lot == lotId and w.Type ~= "Manager" and not w.Unpaid then
						hasWorker = true
						break
					end
				end
				if hasWorker or not Economy.PreviousMall.RequiresWorkerPerStore then
					stores += 1
				end
			end
			local income = stores * Economy.PreviousMall.IncomePerMinutePerStore
			if income > 0 then
				total += income
				local anyLot = next(m.Lots)
				if anyLot then
					m.Lots[anyLot].Ledger.Revenue += income
				end
			end
		end
	end
	if total > 0 then
		EconomyService.AddCash(player, total, "ManagedMall")
		S.MessageService.Toast(player, ("Managed mall income: +%s"):format(Format.Cash(total)), "good")
	end
end

function EconomyService.Init(services)
	S = services
end

function EconomyService.Start()
	S.DataService.OnLoaded:Connect(function(player, profile)
		local ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		local cash = Instance.new("IntValue")
		cash.Name = "Cash"
		cash.Value = profile.Cash
		cash.Parent = ls
		ls.Parent = player
	end)
	task.spawn(function()
		while true do
			task.wait(Economy.Wages.PaySeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				if profileOf(player) then
					payWages(player)
					managedIncome(player)
				end
			end
		end
	end)
end

return EconomyService
