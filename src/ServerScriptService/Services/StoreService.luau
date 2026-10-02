--[[
	StoreService — lots, stores, stock, shelves, counters, displays, machines, minigames and the
	Mall 2 logistics layer (dock -> stockroom -> shelves). Server-authoritative: every prompt and
	remote answer re-checks ownership, distance, prerequisites and the carried object.

	Runtime store object (one per owned lot on an assigned floor):
	  Key, Owner, MallId, Floor, LotId, Type, Cfg, Mall, Data (profile lot), MallData (profile mall),
	  Folder, Frame (lot CFrame; local +Z = corridor), Shelves, Counter, Pallet, Displays, Machines,
	  Stations, Queue (customers at the counter), Customers (set)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Config.Economy)
local Stores = require(ReplicatedStorage.Config.Stores)
local Malls = require(ReplicatedStorage.Config.Malls)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Format = require(ReplicatedStorage.Shared.Format)
local Constants = require(ReplicatedStorage.Shared.Constants)
local AssetRegistry = require(ReplicatedStorage.Shared.AssetRegistry)
local Carry = require(script.Parent.Carry)

local StoreService = {}
local S
local stores = {} -- key -> store
local lockedLots = {} -- key -> model
local logistics = {} -- "mallId:floor" -> { Owner, MallId, Floor, Dock = {...}, Stockroom = {...} }
local minigames = {} -- token -> record
local ICON = Constants.ICONS

local function key(mallId, floor, lotId)
	return ("%d:%d:%s"):format(mallId, floor, lotId)
end

local function near(player, position, dist)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - position).Magnitude <= (dist or Constants.INTERACT_DISTANCE)
end

local function prompt(parent, action, object, opts)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object or ""
	p.MaxActivationDistance = (opts and opts.Distance) or 9
	p.HoldDuration = (opts and opts.Hold) or 0
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = (opts and opts.Key) or Enum.KeyCode.E
	p.GamepadKeyCode = (opts and opts.Gamepad) or Enum.KeyCode.ButtonX
	if opts and opts.Offset then
		p.UIOffset = opts.Offset
	end
	p.Parent = parent
	return p
end

local function anchorOf(model)
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function label(parent, text, offsetY, size)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = size or UDim2.fromOffset(140, 36)
	bb.StudsOffset = Vector3.new(0, offsetY or 4, 0)
	bb.MaxDistance = 32
	local tl = Instance.new("TextLabel")
	tl.Name = "Text"
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
	tl.BackgroundTransparency = 0.25
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBold
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.Text = text
	Instance.new("UICorner", tl).CornerRadius = UDim.new(0, 8)
	tl.Parent = bb
	bb.Parent = parent
	return tl
end

local function push(player)
	if S.ProgressService then
		S.ProgressService.Push(player)
	end
end

local function evaluate(player)
	if S.ProgressService then
		S.ProgressService.Evaluate(player)
	end
end

-- Prompt / label visibility: a prompt only shows when it can do something right now, so the
-- store is not covered in balloons. Called from a slow loop and after state changes.
local function refreshPrompts(st)
	if st.Pallet then
		st.Pallet.TakePrompt.Enabled = st.Pallet.Boxes > 0 or (st.Pallet.Loose or 0) > 0
		st.Pallet.Label.Parent.Enabled = (st.Pallet.Boxes + st.Pallet.Pending + (st.Pallet.Loose or 0)) > 0
	end
	for _, sh in ipairs(st.Shelves) do
		sh.Prompt.Enabled = sh.Stock < st.Cfg.ShelfCapacity
	end
	if st.Counter and st.Counter.Prompt then
		local c = st.Queue[1]
		local active = c ~= nil and (c.State == "Queued" or c.State == "Waiting") and not c.Busy
		if st.Cfg.Interaction == "Restock" then
			local c2 = st.Queue[2]
			st.Counter.Prompt.Enabled = active or (c2 ~= nil and c2.State == "Queued" and not c2.Busy)
		elseif st.Cfg.Interaction ~= "Match" then
			st.Counter.Prompt.Enabled = active and c.State == "Waiting"
		end
	end
	for _, d in ipairs(st.Displays) do
		d.Prompt.Enabled = d.Customer ~= nil and d.Customer.State == "Waiting" and not d.Customer.Busy
	end
end
StoreService.RefreshPrompts = refreshPrompts

-- Accessors -------------------------------------------------------------------------

function StoreService.Get(mallId, floor, lotId)
	return stores[key(mallId, floor, lotId)]
end

function StoreService.StoresOf(player)
	local list = {}
	for _, st in pairs(stores) do
		if st.Owner == player then
			table.insert(list, st)
		end
	end
	return list
end

function StoreService.ActiveStoresOn(mallId, floor)
	local list = {}
	for _, st in pairs(stores) do
		if st.MallId == mallId and st.Floor == floor then
			table.insert(list, st)
		end
	end
	return list
end

function StoreService.Logistics(mallId, floor)
	return logistics[("%d:%d"):format(mallId, floor)]
end

function StoreService.HasUpgrade(st, id)
	return st.Data.Upgrades[id] == true
end

function StoreService.ShelfCount(st)
	return st.Cfg.Shelves + (StoreService.HasUpgrade(st, "ExtraShelf") and 1 or 0)
end

function StoreService.BoxUnits(st)
	if StoreService.HasUpgrade(st, "BiggerBoxes") then
		return 12
	end
	return st.Cfg.BoxUnits
end

function StoreService.Patience(st)
	return Economy.Customers.PatienceSeconds + (StoreService.HasUpgrade(st, "Decor") and 10 or 0)
end

function StoreService.TotalStock(st)
	local n = 0
	for _, sh in ipairs(st.Shelves) do
		n += sh.Stock
	end
	return n
end

local function syncStock(st)
	st.Data.Stock = StoreService.TotalStock(st)
	for _, sh in ipairs(st.Shelves) do
		sh.Label.Text = ("%s %d/%d"):format(st.Cfg.ProductIcon, sh.Stock, st.Cfg.ShelfCapacity)
		sh.Label.TextColor3 = sh.Stock == 0 and Color3.fromRGB(255, 120, 110) or Color3.new(1, 1, 1)
		-- product visuals: a few cartons/boxes proportional to the stock
		local shown = math.ceil(sh.Stock / st.Cfg.ShelfCapacity * #sh.Visuals)
		for i, v in ipairs(sh.Visuals) do
			v.Transparency = i <= shown and 0 or 1
		end
	end
	if st.Shelves[1] and st.Shelves[1].Prompt then
		refreshPrompts(st)
	end
end

StoreService.SyncStock = syncStock

local function salePrice(st, units, bonus)
	local sat = st.Data.Satisfaction or Economy.Satisfaction.Start
	local mult = 1 + (sat / 100) * Economy.Satisfaction.PriceBonusAt100 + (StoreService.HasUpgrade(st, "Decor") and 0.05 or 0)
	return math.floor(units * st.Cfg.UnitPrice * st.Mall.PriceMultiplier * mult + (bonus or 0) + 0.5)
end

function StoreService.AdjustSatisfaction(st, delta)
	st.Data.Satisfaction = math.clamp((st.Data.Satisfaction or Economy.Satisfaction.Start) + delta, Economy.Satisfaction.Min, Economy.Satisfaction.Max)
end

-- A sale happened in st, served by `by` (Player | worker table | nil for simulation).
function StoreService.CompleteSale(st, customer, by, units, bonus, actionKey)
	local amount = salePrice(st, units, bonus)
	local owner = st.Owner
	local pos = st.Counter and st.Counter.Part.Position or st.Frame.Position
	S.EconomyService.AddCash(owner, amount, "Sale", pos)
	S.EconomyService.Record(owner, st.MallId, st.LotId, "Revenue", amount)
	S.EconomyService.Record(owner, st.MallId, st.LotId, "Sales", units)
	S.EconomyService.Record(owner, st.MallId, st.LotId, "Served", 1)
	StoreService.AdjustSatisfaction(st, Economy.Customers.ServedSatisfactionGain)
	local profile = S.DataService.GetProfile(owner)
	if profile then
		profile.Stats.CustomersServed += 1
		if typeof(by) == "Instance" and by == owner then
			profile.Stats.SelfServes[st.Type] = (profile.Stats.SelfServes[st.Type] or 0) + 1
			S.MessageService.Tip(owner, "FirstSale", ("Sold for %s. Stock cost you %s per unit, the rest is profit. Check the Business panel."):format(Format.Cash(amount), Format.Cash(st.Cfg.UnitCost * st.Mall.PriceMultiplier)))
		end
	end
	if typeof(by) == "Instance" and by:IsA("Player") and by ~= owner then
		S.AssistService.Reward(by, owner, actionKey or (st.Key .. ":serve"), pos)
	elseif type(by) == "table" and by.Type then
		S.WorkerService.CountTask(by)
	end
	if customer then
		customer.Served = true
		customer.Paid = amount
	end
	evaluate(owner)
	push(owner)
	return amount
end

function StoreService.CustomerLeftAngry(st, reason)
	StoreService.AdjustSatisfaction(st, -(reason == "empty" and Economy.Customers.EmptyShelfSatisfactionHit or Economy.Customers.LeaveAngrySatisfactionHit))
	push(st.Owner)
end

-- Stock boxes --------------------------------------------------------------------------

local function boxVisual(parent, cf)
	local m = AssetRegistry.Place("StockBox", cf, parent, 0)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	return m
end

local function refreshPallet(st)
	local p = st.Pallet
	if not p then
		return
	end
	for _, m in ipairs(p.Visuals) do
		m:Destroy()
	end
	table.clear(p.Visuals)
	for i = 1, p.Boxes do
		local col, row = (i - 1) % 2, (i - 1) // 2
		table.insert(p.Visuals, boxVisual(st.Folder, p.Part.CFrame * CFrame.new(-1.1 + col * 2.2, 0.25, 0) * CFrame.new(0, row * 2.05, 0)))
	end
	local loose = p.Loose or 0
	p.Label.Text = ("%s Boxes: %d%s%s"):format(ICON.Box, p.Boxes, loose > 0 and (" + %d loose"):format(loose) or "", p.Pending > 0 and (" (+%d arriving)"):format(p.Pending) or "")
	if st.Pallet.TakePrompt then
		refreshPrompts(st)
	end
end

-- order one box of this store's product for its pallet (Mall 1 style delivery)
function StoreService.OrderStock(player, st)
	if st.Owner ~= player then
		S.MessageService.Toast(player, "Only the owner can buy stock for this store.", "bad")
		return false
	end
	if not st.Pallet then
		S.MessageService.Toast(player, "This mall delivers to the loading dock. Order there.", "info")
		return false
	end
	local p = st.Pallet
	if p.Boxes + p.Pending >= st.Cfg.MaxPendingBoxes then
		S.MessageService.Toast(player, "The delivery point is full. Restock a shelf first.", "bad")
		return false
	end
	local cost = math.floor(StoreService.BoxUnits(st) * st.Cfg.UnitCost * st.Mall.PriceMultiplier + 0.5)
	if not S.EconomyService.TrySpend(player, cost, "Stock", p.Part.Position) then
		return false
	end
	S.EconomyService.Record(player, st.MallId, st.LotId, "StockCost", cost)
	p.Pending += 1
	refreshPallet(st)
	S.MessageService.Tip(player, "OrderStock", "Stock is a cost: each box you buy is money out until the units are sold. Keep shelves filled, not overfilled.")
	task.delay(st.Cfg.DeliverySeconds, function()
		if stores[st.Key] ~= st then
			return
		end
		p.Pending = math.max(0, p.Pending - 1)
		p.Boxes += 1
		refreshPallet(st)
		push(st.Owner)
	end)
	push(player)
	return true
end

-- Takes a box from the pallet: a partly used box (loose units) first, else a full one.
-- Returns false, or true plus the number of units in the box taken.
function StoreService.TakeBoxFromPallet(player, st)
	local p = st.Pallet
	local loose = p and (p.Loose or 0) or 0
	if not p or (p.Boxes <= 0 and loose <= 0) then
		if player then
			S.MessageService.Toast(player, "No boxes here. Order stock first.", "info")
		end
		return false
	end
	local units = loose > 0 and loose or StoreService.BoxUnits(st)
	if player then
		if Carry.Get(player) then
			S.MessageService.Toast(player, "Your hands are full.", "bad")
			return false
		end
		if not Carry.Give(player, "StockBox", { Source = "Pallet", Store = st.Key, Type = st.Type, Units = units }) then
			return false
		end
		S.MessageService.Tip(player, "CarryBox", "Carry the box to a shelf and press Restock. Units that do not fit stay in the box.")
	end
	if loose > 0 then
		p.Loose = 0
	else
		p.Boxes -= 1
	end
	refreshPallet(st)
	if player then
		push(st.Owner)
	end
	return true, units
end

-- Puts leftover units back on the pallet as a partial box (merges with an existing one; a full
-- box's worth becomes a whole box).
function StoreService.ReturnUnitsToPallet(st, units)
	local p = st.Pallet
	if not p or units <= 0 then
		return
	end
	local full = StoreService.BoxUnits(st)
	local total = (p.Loose or 0) + units
	p.Boxes += total // full
	p.Loose = total % full
	refreshPallet(st)
end

function StoreService.PalletHasBox(st)
	return st.Pallet ~= nil and (st.Pallet.Boxes > 0 or (st.Pallet.Loose or 0) > 0)
end

function StoreService.ShelfNeedingStock(st)
	local best
	for _, sh in ipairs(st.Shelves) do
		if sh.Stock < st.Cfg.ShelfCapacity and (not best or sh.Stock < best.Stock) then
			best = sh
		end
	end
	return best
end

-- Put `units` on a shelf. by = Player | worker | nil
function StoreService.RestockShelf(st, shelf, units, by)
	local space = st.Cfg.ShelfCapacity - shelf.Stock
	local added = math.min(space, units)
	shelf.Stock += added
	syncStock(st)
	local owner = st.Owner
	local left = units - added
	if typeof(by) == "Instance" and by:IsA("Player") then
		S.MessageService.Toast(by, left > 0 and ("Restocked %d %s (%d left in the box)"):format(added, st.Cfg.Product, left) or ("Restocked %d %s"):format(added, st.Cfg.Product), "good")
		if by ~= owner then
			S.AssistService.Reward(by, owner, st.Key .. ":restock:" .. shelf.Index, shelf.Part.Position)
		else
			S.MessageService.Tip(by, "Restock", "Full shelves sell; empty shelves lose customers. Hire a stocker to automate this.")
		end
	elseif type(by) == "table" then
		S.WorkerService.CountTask(by)
	end
	evaluate(owner)
	push(owner)
	return added, left
end

function StoreService.RestockFromCarry(player, st, shelf)
	local c = Carry.Get(player)
	if not c or c.Kind ~= "StockBox" then
		S.MessageService.Toast(player, "Carry a stock box here first (take one from the delivery point).", "info")
		return
	end
	if not near(player, shelf.Part.Position) then
		return
	end
	if shelf.Stock >= st.Cfg.ShelfCapacity then
		S.MessageService.Toast(player, "This shelf is full.", "info")
		return
	end
	if st.Mall.Logistics then
		if c.Data.Source ~= "Stockroom" then
			S.MessageService.Toast(player, "Boxes from the dock must go through the stockroom first.", "bad")
			return
		end
	elseif c.Data.Store ~= st.Key then
		S.MessageService.Toast(player, "That box belongs to another store.", "bad")
		return
	end
	if c.Data.Opened and c.Data.Store ~= st.Key then
		S.MessageService.Toast(player, "That opened box holds another store's product.", "bad")
		return
	end
	local units = c.Data.Units or StoreService.BoxUnits(st)
	if st.Mall.Logistics and not c.Data.Opened then
		units = StoreService.BoxUnits(st) -- generic supplies become this store's product; cost was booked at the dock
	end
	local _, left = StoreService.RestockShelf(st, shelf, units, player)
	if left > 0 then
		-- keep carrying the partly used box: it now belongs to this store
		c.Data.Units = left
		c.Data.Opened = true
		c.Data.Store = st.Key
		c.Data.Type = st.Type
		c.Data.Source = st.Mall.Logistics and "Stockroom" or "Pallet"
	else
		Carry.Take(player, "StockBox")
	end
end

-- Customers at the counter --------------------------------------------------------------

function StoreService.JoinQueue(st, customer)
	table.insert(st.Queue, customer)
	refreshPrompts(st)
	return #st.Queue
end

function StoreService.LeaveQueue(st, customer)
	local i = table.find(st.Queue, customer)
	if i then
		table.remove(st.Queue, i)
	end
	refreshPrompts(st)
end

function StoreService.QueueIndex(st, customer)
	return table.find(st.Queue, customer)
end

function StoreService.QueueSpot(st, index)
	local c = st.Counter
	return c.Spot + c.QueueDir * (index - 1) * 2.6
end

function StoreService.NextQueued(st)
	for i = 1, math.min(2, #st.Queue) do
		local c = st.Queue[i]
		if c and c.State == "Queued" and not c.Busy then
			return c
		end
	end
	return nil
end

-- Self-checkout kiosk: takes the first free queued customer (within the first two, so it works
-- alongside a cashier) and completes the sale after SelfCheckoutSeconds. Called from the store tick.
function StoreService.KioskTick(st)
	local k = st.Kiosk
	if not k or k.Current or os.clock() < k.NextAt then
		return
	end
	for i = 1, math.min(2, #st.Queue) do
		local c = st.Queue[i]
		if c and c.State == "Queued" and not c.Busy then
			c.Busy = k
			k.Current = c
			S.NpcService.SetBubble(c.Npc, "🧾")
			task.delay(st.Cfg.SelfCheckoutSeconds or 6, function()
				k.Current = nil
				k.NextAt = os.clock() + 1
				if stores[st.Key] ~= st or c.State ~= "Queued" or c.Busy ~= k then
					if c.Busy == k then
						c.Busy = nil
					end
					return
				end
				StoreService.CompleteSale(st, c, "Kiosk", c.Items or 1, 0)
				c.State = "Served"
				c.Busy = nil
				StoreService.LeaveQueue(st, c)
			end)
			return
		end
	end
end

-- serve the first queued customer (counter stores: Convenience; also used by cashiers)
function StoreService.ServeQueued(st, by)
	local c = StoreService.NextQueued(st)
	if not c then
		return false
	end
	c.Busy = by
	StoreService.CompleteSale(st, c, by, c.Items or 1, 0, st.Key .. ":serve")
	c.State = "Served"
	StoreService.LeaveQueue(st, c)
	return true
end

-- Requests (Clothing displays, Food kiosk, Electronics) ----------------------------------

function StoreService.RandomRequest(st)
	local cfg = st.Cfg
	if cfg.Interaction == "Match" then
		return { Symbol = cfg.Symbols[math.random(#cfg.Symbols)] }
	elseif cfg.Interaction == "Assemble" then
		local n = math.random(cfg.ItemsPerCustomer[1], cfg.ItemsPerCustomer[2])
		local order = {}
		for _ = 1, n do
			table.insert(order, cfg.Ingredients[math.random(#cfg.Ingredients)])
		end
		return { Order = order }
	elseif cfg.Interaction == "MatchDemo" then
		return { Category = cfg.Categories[math.random(#cfg.Categories)] }
	end
	return {}
end

function StoreService.RequestText(st, req)
	if req.Symbol then
		return ICON[req.Symbol] .. "?"
	elseif req.Order then
		local s = ""
		for _, it in ipairs(req.Order) do
			s ..= ICON[it]
		end
		return s
	elseif req.Category then
		return ICON[req.Category] .. "?"
	end
	return "?"
end

function StoreService.FreeDisplay(st)
	for _, d in ipairs(st.Displays) do
		if not d.Customer then
			return d
		end
	end
	return nil
end

-- the waiting customer with a request that nobody is handling
function StoreService.NextRequest(st)
	for _, d in ipairs(st.Displays) do
		local c = d.Customer
		if c and c.State == "Waiting" and not c.Busy then
			return c, d
		end
	end
	local c = st.Queue[1]
	if c and c.State == "Waiting" and not c.Busy then
		return c
	end
	return nil
end

local function unitsFor(st, customer)
	if customer.Request and customer.Request.Order then
		return #customer.Request.Order
	end
	return customer.Items or 1
end

-- complete a request correctly (worker or correct player answer)
function StoreService.ResolveRequest(st, customer, by, bonus, actionKey)
	if customer.State ~= "Waiting" then
		return false
	end
	local units = unitsFor(st, customer)
	if st.Cfg.ShelfCapacity > 0 then
		-- consume stock
		local need = units
		for _, sh in ipairs(st.Shelves) do
			local take = math.min(sh.Stock, need)
			sh.Stock -= take
			need -= take
		end
		syncStock(st)
	end
	StoreService.CompleteSale(st, customer, by, units, bonus, actionKey)
	customer.State = "Served"
	if customer.Display then
		customer.Display.Customer = nil
	end
	StoreService.LeaveQueue(st, customer)
	return true
end

function StoreService.FailRequest(st, customer)
	if customer.State ~= "Waiting" then
		return
	end
	customer.State = "Leaving"
	customer.Angry = true
	if customer.Display then
		customer.Display.Customer = nil
	end
	StoreService.LeaveQueue(st, customer)
	StoreService.CustomerLeftAngry(st, "wrong")
end

-- Minigames --------------------------------------------------------------------------

local function openMinigame(player, st, customer, kind, payload)
	local token = HttpService:GenerateGUID(false)
	local rec = { Token = token, Player = player, Store = st, Customer = customer, Kind = kind, Expires = os.clock() + (payload.TimeLimit or 15), Expect = payload.Expect, Machine = payload.Machine }
	minigames[token] = rec
	StoreService.LastMinigame = rec -- Studio tests peek at this
	if customer then
		customer.Busy = player
	end
	if payload.Machine then
		payload.Machine.Busy = player
	end
	payload.Expect = nil
	payload.Machine = nil
	payload.Token = token
	payload.Kind = kind
	Remotes.Minigame:FireClient(player, payload)
	task.delay((rec.Expires - os.clock()) + 0.5, function()
		if minigames[token] == rec then
			minigames[token] = nil
			if customer and customer.Busy == player then
				customer.Busy = nil
			end
			if rec.Machine and rec.Machine.Busy == player then
				rec.Machine.Busy = nil
			end
			Remotes.Minigame:FireClient(player, { Token = token, Close = true })
		end
	end)
	return token
end

function StoreService.HelpCustomer(player, st, customer)
	if not customer or customer.State ~= "Waiting" then
		S.MessageService.Toast(player, "No customer is waiting right now.", "info")
		return
	end
	if customer.Busy then
		return
	end
	local req = customer.Request
	local cfg = st.Cfg
	if cfg.Interaction == "Match" then
		openMinigame(player, st, customer, "Match", {
			Prompt = "Which outfit does the customer want?",
			Hint = StoreService.RequestText(st, req),
			Options = cfg.Symbols,
			Expect = req.Symbol,
			TimeLimit = 12,
		})
	elseif cfg.Interaction == "Assemble" then
		openMinigame(player, st, customer, "Assemble", {
			Prompt = "Assemble the order, then serve it",
			Hint = StoreService.RequestText(st, req),
			Options = cfg.Ingredients,
			Expect = req.Order,
			TimeLimit = 18,
		})
	elseif cfg.Interaction == "MatchDemo" then
		openMinigame(player, st, customer, "Match", {
			Prompt = "Which product is the customer looking for?",
			Hint = StoreService.RequestText(st, req),
			Options = cfg.Categories,
			Expect = req.Category,
			TimeLimit = 12,
		})
	end
end

local function sameMultiset(a, b)
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		return false
	end
	local count = {}
	for _, v in ipairs(a) do
		count[v] = (count[v] or 0) + 1
	end
	for _, v in ipairs(b) do
		if not count[v] or count[v] == 0 then
			return false
		end
		count[v] -= 1
	end
	return true
end

function StoreService.AnswerMinigame(player, token, answer)
	local rec = minigames[token]
	if not rec or rec.Player ~= player then
		return
	end
	minigames[token] = nil
	local st, customer = rec.Store, rec.Customer
	if stores[st.Key] ~= st then
		return
	end
	local anchorPos = (customer and customer.Npc and customer.Npc.PrimaryPart and customer.Npc.PrimaryPart.Position) or (rec.Machine and rec.Machine.Part.Position) or st.Frame.Position
	local ok = os.clock() <= rec.Expires and near(player, anchorPos, Constants.INTERACT_DISTANCE + 6)
	local correct = false
	if ok then
		if rec.Kind == "Match" then
			correct = answer == rec.Expect
		elseif rec.Kind == "Assemble" then
			correct = sameMultiset(answer, rec.Expect)
		elseif rec.Kind == "Repair" then
			correct = type(answer) == "table" and table.concat(answer, ",") == table.concat(rec.Expect, ",")
		end
	end
	Remotes.Minigame:FireClient(player, { Token = token, Result = correct and "ok" or "wrong", Close = true })
	if rec.Kind == "Repair" then
		local m = rec.Machine
		m.Busy = nil
		if correct then
			StoreService.RepairMachine(st, m, player)
		else
			S.MessageService.Toast(player, "Wrong sequence. Try again.", "bad")
		end
		return
	end
	if customer then
		customer.Busy = nil
		if correct then
			local bonus = 0
			if st.Cfg.Interaction == "MatchDemo" then
				customer.AwaitDemo = os.clock() + 8 -- a demo within 8 s pays the bonus
				S.MessageService.Toast(player, "Right product! Hold DEMO at the bench within 8 s for a bonus.", "good")
			end
			StoreService.ResolveRequest(st, customer, player, bonus, st.Key .. ":help")
		else
			S.MessageService.Toast(player, "That is not what they wanted. The customer leaves.", "bad")
			StoreService.FailRequest(st, customer)
		end
	end
end

-- Electronics demo bonus (hold prompt at the demo bench after a correct match)
function StoreService.Demo(player, st)
	local now = os.clock()
	-- most recent customer that was just served with AwaitDemo still valid
	local best
	for c in pairs(st.Customers) do
		if c.AwaitDemo and c.AwaitDemo > now and not c.DemoDone then
			best = c
		end
	end
	if not best then
		S.MessageService.Toast(player, "Nobody is waiting for a demo. Match a product first.", "info")
		return
	end
	best.DemoDone = true
	local bonus = st.Cfg.DemoBonus * (StoreService.HasUpgrade(st, "DemoBench") and 2 or 1) * st.Mall.PriceMultiplier
	bonus = math.floor(bonus + 0.5)
	S.EconomyService.AddCash(st.Owner, bonus, "Demo", st.Stations.Demo.Position)
	S.EconomyService.Record(st.Owner, st.MallId, st.LotId, "Revenue", bonus)
	if player ~= st.Owner then
		S.AssistService.Reward(player, st.Owner, st.Key .. ":demo", st.Stations.Demo.Position)
	else
		S.MessageService.Toast(player, ("Demo bonus +%s"):format(Format.Cash(bonus)), "good")
	end
	push(st.Owner)
end

function StoreService.PendingDemo(st)
	local now = os.clock()
	for c in pairs(st.Customers) do
		if c.AwaitDemo and c.AwaitDemo > now and not c.DemoDone then
			return c
		end
	end
	return nil
end

function StoreService.WorkerDemo(st, worker)
	local c = StoreService.PendingDemo(st)
	if not c then
		return false
	end
	c.DemoDone = true
	local bonus = math.floor(st.Cfg.DemoBonus * (StoreService.HasUpgrade(st, "DemoBench") and 2 or 1) * st.Mall.PriceMultiplier + 0.5)
	S.EconomyService.AddCash(st.Owner, bonus, "Demo", st.Stations.Demo.Position)
	S.EconomyService.Record(st.Owner, st.MallId, st.LotId, "Revenue", bonus)
	S.WorkerService.CountTask(worker)
	push(st.Owner)
	return true
end

-- Arcade machines ------------------------------------------------------------------------

local function setMachineBroken(m, broken)
	m.Broken = broken
	m.Screen.Color = broken and Color3.fromRGB(230, 70, 60) or Color3.fromRGB(80, 220, 250)
	m.Screen.Material = broken and Enum.Material.SmoothPlastic or Enum.Material.Neon
	m.Smoke.Enabled = broken
	m.Prompt.Enabled = broken
	m.Label.Text = broken and "⚠ BROKEN" or "🕹️ OK"
	m.Label.TextColor3 = broken and Color3.fromRGB(255, 120, 110) or Color3.fromRGB(120, 230, 150)
end

function StoreService.FreeMachine(st)
	for _, m in ipairs(st.Machines) do
		if not m.Broken and not m.Customer then
			return m
		end
	end
	return nil
end

function StoreService.BrokenMachine(st)
	for _, m in ipairs(st.Machines) do
		if m.Broken and not m.Busy then
			return m
		end
	end
	return nil
end

function StoreService.PlayMachine(st, m, customer)
	if m.Broken then
		return false
	end
	local plays = customer.Items or 1
	StoreService.CompleteSale(st, customer, nil, plays, 0)
	if math.random() < st.Cfg.BreakChancePerPlay then
		setMachineBroken(m, true)
		if S.FloorService.IsFloorActive(st.MallId, st.Floor) then
			S.MessageService.Toast(st.Owner, "An arcade machine broke down! Repair it (or hire a technician).", "bad")
		end
	end
	return true
end

function StoreService.RepairMachine(st, m, by)
	if not m.Broken then
		return false
	end
	setMachineBroken(m, false)
	if typeof(by) == "Instance" and by:IsA("Player") then
		S.MessageService.Toast(by, "Machine repaired!", "good")
		if by ~= st.Owner then
			S.AssistService.Reward(by, st.Owner, st.Key .. ":repair:" .. m.Index, m.Part.Position)
		end
	elseif type(by) == "table" then
		S.WorkerService.CountTask(by)
	end
	push(st.Owner)
	return true
end

function StoreService.StartRepair(player, st, m)
	if not m.Broken or m.Busy then
		return
	end
	local steps = st.Cfg.RepairSteps
	local seq = {}
	for _ = 1, 3 do
		table.insert(seq, steps[math.random(#steps)])
	end
	openMinigame(player, st, nil, "Repair", {
		Prompt = "Watch the sequence, then repeat it",
		Options = steps,
		Sequence = seq,
		Expect = seq,
		Machine = m,
		TimeLimit = 16,
	})
end

-- Building ------------------------------------------------------------------------------

local function sign(st, text, color)
	local p = Instance.new("Part")
	p.Name = "Sign"
	p.Size = Vector3.new(18, 2.6, 0.3)
	p.Anchored = true
	p.CanCollide = false
	p.Color = color
	p.CFrame = st.Frame * CFrame.new(0, 11.4, S.MallService.LOT_D / 2 + 1.2) * CFrame.Angles(0, math.pi, 0) -- face the corridor
	p.Parent = st.Folder
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(900, 130)
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.TextScaled = true
	tl.Font = Enum.Font.GothamBlack
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.Text = text
	tl.Parent = sg
	sg.Parent = p
	return p
end

local function placeLocal(st, id, x, z, yaw)
	return AssetRegistry.Place(id, st.Frame * CFrame.new(x, 0, z), st.Folder, yaw)
end

local function addShelf(st, index, assetId, x, z, yaw, browseOffset)
	local m = placeLocal(st, assetId, x, z, yaw)
	local part = anchorOf(m)
	local size = AssetRegistry.Size(assetId)
	local shelf = { Index = index, Model = m, Part = part, Stock = 0, Visuals = {}, Spot = (st.Frame * CFrame.new(x, 0, z + (browseOffset or 4))).Position }
	-- product visuals on the shelf (cartons); each entry is a proxy whose Transparency sets every part
	local cols = assetId == "Shelf" and 6 or 3
	for row = 0, 1 do
		for col = 1, cols do
			local vx = -size.X / 2 + size.X * (col - 0.5) / cols
			local v = AssetRegistry.Place("MilkCarton", st.Frame * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw or 0), 0) * CFrame.new(vx, 1.8 + row * 2, -0.2), st.Folder, 0)
			local parts = {}
			for _, d in ipairs(v:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					if d.Name ~= "Root" then
						table.insert(parts, d)
						if st.Type ~= "Convenience" then
							d.Color = st.Cfg.Color
						end
					end
				end
			end
			table.insert(shelf.Visuals, setmetatable({}, { __newindex = function(_, k, val)
				if k == "Transparency" then
					for _, d in ipairs(parts) do
						d.Transparency = val
					end
				end
			end }))
		end
	end
	shelf.Label = label(part, "", size.Y + 1.5)
	shelf.Prompt = prompt(part, "Restock", st.Cfg.Name, { Distance = 9 })
	shelf.Prompt.Triggered:Connect(function(player)
		StoreService.RestockFromCarry(player, st, shelf)
	end)
	table.insert(st.Shelves, shelf)
	return shelf
end

local function addCounter(st, assetId, x, z, serveAction)
	local m = placeLocal(st, assetId, x, z, 180)
	local part = anchorOf(m)
	local size = AssetRegistry.Size(assetId)
	st.Counter = {
		Model = m,
		Part = part,
		Spot = (st.Frame * CFrame.new(x, 0, z + size.Z / 2 + 2.2)).Position,
		QueueDir = st.Frame.LookVector, -- +Z
		ServeSpot = (st.Frame * CFrame.new(x, 0, z - size.Z / 2 - 1.5)).Position,
	}
	local p = prompt(part, serveAction or "Serve customer", st.Cfg.Name, { Distance = 10 })
	st.Counter.Prompt = p
	return st.Counter
end

local function addPallet(st, x, z)
	local part = Instance.new("Part")
	part.Name = "Pallet"
	part.Size = Vector3.new(5, 0.5, 3)
	part.Anchored = true
	part.Color = AssetRegistry.Colors.Wood
	part.Material = Enum.Material.WoodPlanks
	part.CFrame = st.Frame * CFrame.new(x, 0.25, z)
	part.Parent = st.Folder
	st.Pallet = { Part = part, Boxes = 0, Pending = 0, Visuals = {} }
	st.Pallet.Label = label(part, "", 5, UDim2.fromOffset(200, 36))
	local cost = math.floor(StoreService.BoxUnits(st) * st.Cfg.UnitCost * st.Mall.PriceMultiplier + 0.5)
	local order = prompt(part, ("Order box (%s)"):format(Format.Cash(cost)), "Delivery point", { Key = Enum.KeyCode.R, Gamepad = Enum.KeyCode.ButtonY, Offset = Vector2.new(0, -40), Distance = 10 })
	order.Triggered:Connect(function(player)
		StoreService.OrderStock(player, st)
	end)
	local take = prompt(part, "Take box", "Delivery point", { Distance = 10 })
	take.Triggered:Connect(function(player)
		if near(player, part.Position) then
			StoreService.TakeBoxFromPallet(player, st)
		end
	end)
	st.Pallet.OrderPrompt = order
	st.Pallet.TakePrompt = take
	refreshPallet(st)
end

local function addDisplay(st, assetId, x, z)
	local m = placeLocal(st, assetId, x, z, 180)
	local part = anchorOf(m)
	local size = AssetRegistry.Size(assetId)
	local d = { Index = #st.Displays + 1, Model = m, Part = part, Spot = (st.Frame * CFrame.new(x, 0, z + size.Z / 2 + 2)).Position, Customer = nil }
	d.Prompt = prompt(part, "Help customer", st.Cfg.Name, { Distance = 10 })
	d.Prompt.Triggered:Connect(function(player)
		if near(player, part.Position) then
			StoreService.HelpCustomer(player, st, d.Customer)
		end
	end)
	table.insert(st.Displays, d)
	return d
end

local function addMachine(st, x, z)
	local m = placeLocal(st, "ArcadeCabinet", x, z, 180)
	local part = anchorOf(m)
	local screen = Instance.new("Part")
	screen.Name = "Status"
	screen.Size = Vector3.new(2.6, 1.2, 0.2)
	screen.Anchored = true
	screen.CanCollide = false
	screen.Material = Enum.Material.Neon
	screen.Color = Color3.fromRGB(80, 220, 250)
	screen.CFrame = st.Frame * CFrame.new(x, 5.6, z + 1.7)
	screen.Parent = st.Folder
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = 6
	smoke.Lifetime = NumberRange.new(1, 1.6)
	smoke.Speed = NumberRange.new(2, 3)
	smoke.Size = NumberSequence.new(1, 2.5)
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 90, 90))
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Enabled = false
	smoke.Parent = screen
	local rec = { Index = #st.Machines + 1, Model = m, Part = part, Screen = screen, Smoke = smoke, Broken = false, Customer = nil, Spot = (st.Frame * CFrame.new(x, 0, z + 3.5)).Position }
	rec.Label = label(part, "🕹️ OK", 8.5, UDim2.fromOffset(120, 32))
	rec.Prompt = prompt(part, "Repair", "Arcade machine", { Distance = 9 })
	rec.Prompt.Enabled = false
	rec.Prompt.Triggered:Connect(function(player)
		if near(player, part.Position) then
			StoreService.StartRepair(player, st, rec)
		end
	end)
	table.insert(st.Machines, rec)
	return rec
end

local function buildInterior(st)
	local t = st.Type
	if t == "Convenience" then
		addCounter(st, "CheckoutCounter", -9, 7, "Serve customer")
		st.Counter.Prompt.Triggered:Connect(function(player)
			if near(player, st.Counter.Part.Position) then
				if not StoreService.ServeQueued(st, player) then
					S.MessageService.Toast(player, "No customer at the counter.", "info")
				end
			end
		end)
		local xs = { -9, 1, 11 }
		for i = 1, StoreService.ShelfCount(st) do
			addShelf(st, i, "Shelf", xs[i], -7, 180, 4)
		end
		addPallet(st, 12, 8)
		placeLocal(st, "Basket", -14, 10, 0)
		if StoreService.HasUpgrade(st, "SelfCheckout") then
			local kiosk = placeLocal(st, "InfoKiosk", -2, 7, 180)
			local part = anchorOf(kiosk)
			st.Kiosk = { Part = part, NextAt = 0, Label = label(part, "🧾 Self-checkout", 8, UDim2.fromOffset(170, 34)) }
		end
	elseif t == "Clothing" then
		addDisplay(st, "ClothesRack", 0, -7)
		if StoreService.HasUpgrade(st, "Display") then
			addDisplay(st, "ClothesTable", 10, -7)
		end
		-- the rack doubles as the stock shelf
		addShelf(st, 1, "ClothesTable", -11, -7, 180, 4)
		st.Shelves[1].Label.Parent.StudsOffset = Vector3.new(0, 4.5, 0)
		addCounter(st, "CheckoutCounter", -9, 7, "Help customer")
		st.Counter.Prompt.Enabled = false
		addPallet(st, 12, 8)
	elseif t == "FoodKiosk" then
		local kiosk = placeLocal(st, "FoodKiosk", 0, -2, 180)
		st.Stations.Kiosk = anchorOf(kiosk)
		-- cooking stations in a back row behind the booth (the booth mesh fills x -6..6, z -6..2)
		st.Stations.Griddle = anchorOf(placeLocal(st, "Griddle", -5, -10, 180))
		st.Stations.Drinks = anchorOf(placeLocal(st, "DrinkDispenser", 7, -10, 180))
		if StoreService.HasUpgrade(st, "SecondGriddle") then
			placeLocal(st, "Griddle", 1, -10, 180)
		end
		-- the tray sits on the booth counter: find its top surface
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { kiosk }
		local from = (st.Frame * CFrame.new(-3, 5, 1)).Position -- below the canopy
		local hit = workspace:Raycast(from, Vector3.new(0, -6, 0), params)
		local tray = placeLocal(st, "BurgerTray", -3, 1, 0)
		if hit then
			tray:PivotTo(CFrame.new(hit.Position) * (tray:GetPivot() - tray:GetPivot().Position))
		end
		addShelf(st, 1, "Shelf", -13, -8, 90, 0)
		st.Shelves[1].Spot = (st.Frame * CFrame.new(-9, 0, -8)).Position
		-- the kiosk front acts as the counter where customers queue with orders
		st.Counter = {
			Part = st.Stations.Kiosk,
			Spot = (st.Frame * CFrame.new(0, 0, 5)).Position,
			QueueDir = st.Frame.LookVector,
			ServeSpot = (st.Frame * CFrame.new(0, 0, -2)).Position,
		}
		st.Counter.Prompt = prompt(st.Stations.Kiosk, "Prepare order", "Food kiosk", { Distance = 11 })
		st.Counter.Prompt.Triggered:Connect(function(player)
			if near(player, st.Stations.Kiosk.Position, 14) then
				local c = st.Queue[1]
				if c and c.State == "Waiting" and StoreService.TotalStock(st) < unitsFor(st, c) then
					S.MessageService.Toast(player, "Not enough ingredients in the pantry. Restock it first.", "bad")
					return
				end
				StoreService.HelpCustomer(player, st, c)
			end
		end)
		addPallet(st, 12, 8)
	elseif t == "Electronics" then
		addCounter(st, "ElectronicsCounter", 0, 4, "Help customer")
		st.Counter.Prompt.Triggered:Connect(function(player)
			if near(player, st.Counter.Part.Position) then
				local c = st.Queue[1]
				if c and c.State == "Waiting" and StoreService.TotalStock(st) < 1 then
					S.MessageService.Toast(player, "No gadgets in stock. Restock the display from the stockroom.", "bad")
					return
				end
				StoreService.HelpCustomer(player, st, c)
			end
		end)
		addShelf(st, 1, "Shelf", -10, -8, 180, 4)
		local bench = placeLocal(st, "ElectronicsCounter", 10, -6, 180)
		st.Stations.Demo = anchorOf(bench)
		local demo = prompt(st.Stations.Demo, "Demo product", "Demo bench", { Hold = 1.5, Distance = 9 })
		demo.Triggered:Connect(function(player)
			if near(player, st.Stations.Demo.Position) then
				StoreService.Demo(player, st)
			end
		end)
		label(st.Stations.Demo, "🎧 Demo bench", 5.5)
	elseif t == "Arcade" then
		local spots = { { -12, -8 }, { -4, -8 }, { 4, -8 }, { 12, -8 }, { -8, 3 }, { 8, 3 } }
		local n = st.Cfg.Machines + (StoreService.HasUpgrade(st, "MoreMachines") and 2 or 0)
		for i = 1, n do
			addMachine(st, spots[i][1], spots[i][2])
		end
		st.Counter = { Part = anchorOf(placeLocal(st, "CheckoutCounter", -12, 8, 180)), Spot = (st.Frame * CFrame.new(-12, 0, 11)).Position, QueueDir = st.Frame.LookVector, ServeSpot = (st.Frame * CFrame.new(-12, 0, 5)).Position }
	end
end

local function buildStore(player, mallId, floor, lot, profile)
	local k = key(mallId, floor, lot.Id)
	if stores[k] then
		stores[k].Folder:Destroy()
		stores[k] = nil
	end
	if lockedLots[k] then
		lockedLots[k]:Destroy()
		lockedLots[k] = nil
	end
	local mallData = profile.Malls[tostring(mallId)]
	local data = mallData.Lots[lot.Id]
	local cfg = Stores[data.Store]
	local folder = Instance.new("Model")
	folder.Name = ("Store_%s_%s"):format(lot.Id, data.Store)
	folder.Parent = S.MallService.DynamicFolder(mallId, floor)
	local st = {
		Key = k, Owner = player, MallId = mallId, Floor = floor, LotId = lot.Id, Type = data.Store, Cfg = cfg,
		Mall = Malls[mallId], Data = data, MallData = mallData, Folder = folder,
		Frame = S.MallService.LotCFrame(mallId, floor, lot.Id),
		Shelves = {}, Displays = {}, Machines = {}, Stations = {}, Queue = {}, Customers = {},
	}
	stores[k] = st
	sign(st, ("%s · %s"):format(cfg.Name, player.DisplayName), cfg.Color)
	buildInterior(st)
	-- distribute saved stock over the shelves
	local remaining = data.Stock or 0
	for _, sh in ipairs(st.Shelves) do
		local put = math.min(cfg.ShelfCapacity, remaining)
		sh.Stock = put
		remaining -= put
	end
	syncStock(st)
	refreshPrompts(st)
	return st
end

local function buildLockedLot(player, mallId, floor, lot)
	local k = key(mallId, floor, lot.Id)
	local frame = S.MallService.LotCFrame(mallId, floor, lot.Id)
	local folder = Instance.new("Model")
	folder.Name = "Locked_" .. lot.Id
	folder.Parent = S.MallService.DynamicFolder(mallId, floor)
	local shutter = AssetRegistry.Place("ShutterDoor", frame * CFrame.new(0, 0, S.MallService.LOT_D / 2 - 2.5), folder, 180)
	AssetRegistry.Place("Barricade", frame * CFrame.new(0, 0, S.MallService.LOT_D / 2 + 3), folder, 0)
	local cfg = Stores[lot.Store]
	local anchor = anchorOf(shutter)
	local cost = math.floor(lot.Cost * 1 + 0.5)
	local lbl = label(anchor, ("%s FOR LEASE · %s · %s"):format(ICON.Lock, cfg.Name, Format.Cash(cost)), 14, UDim2.fromOffset(300, 40))
	lbl.BackgroundColor3 = cfg.Color
	local p = prompt(anchor, ("Lease for %s"):format(Format.Cash(cost)), cfg.Name, { Hold = 0.5, Distance = 12 })
	p.Triggered:Connect(function(who)
		StoreService.BuyLot(who, mallId, lot.Id)
	end)
	lockedLots[k] = folder
end

-- Mall 2 logistics: loading dock + stockroom on the owner's floor
local function refreshLogistics(lg)
	local d = lg.Dock
	for _, m in ipairs(d.Visuals) do
		m:Destroy()
	end
	table.clear(d.Visuals)
	for i = 1, d.Boxes do
		local col, row = (i - 1) % 3, (i - 1) // 3
		table.insert(d.Visuals, boxVisual(lg.Folder, d.Part.CFrame * CFrame.new(-2.2 + col * 2.2, 0.25 + row * 2.05, 0)))
	end
	d.Label.Text = ("%s Dock: %d box%s%s"):format(ICON.Box, d.Boxes, d.Boxes == 1 and "" or "es", d.Pending and " · van on its way" or "")
	local s = lg.Stockroom
	for _, m in ipairs(s.Visuals) do
		m:Destroy()
	end
	table.clear(s.Visuals)
	local data = lg.MallData.Stockroom
	for i = 1, data.Boxes do
		local col, row = (i - 1) % 4, (i - 1) // 4
		table.insert(s.Visuals, boxVisual(lg.Folder, s.Part.CFrame * CFrame.new(-3.3 + col * 2.2, 0.6 + row * 3, 0)))
	end
	s.Label.Text = ("%s Stockroom %d / %d"):format(ICON.Box, data.Boxes, data.Capacity)
	s.Label.TextColor3 = data.Boxes >= data.Capacity and Color3.fromRGB(255, 120, 110) or Color3.new(1, 1, 1)
	if d.TakePrompt then
		d.TakePrompt.Enabled = d.Boxes > 0
		s.TakePrompt.Enabled = data.Boxes > 0
	end
end

function StoreService.OrderDelivery(player, lg)
	if lg.Owner ~= player then
		S.MessageService.Toast(player, "Only the floor owner can order deliveries.", "bad")
		return false
	end
	local L = Malls[lg.MallId].Logistics
	if lg.Dock.Pending then
		S.MessageService.Toast(player, "A delivery is already on its way.", "info")
		return false
	end
	local boxes = S.ProjectService.DeliveryBoxes(lg.MallId)
	if lg.Dock.Boxes + boxes > 12 then
		S.MessageService.Toast(player, "The dock is full. Move boxes into the stockroom first.", "bad")
		return false
	end
	local cost = boxes * L.DeliveryCostPerBox
	if not S.EconomyService.TrySpend(player, cost, "Delivery", lg.Dock.Part.Position) then
		return false
	end
	-- book the cost evenly on this mall's stores so profit stays honest
	local lots = {}
	for lotId in pairs(lg.MallData.Lots) do
		table.insert(lots, lotId)
	end
	for _, lotId in ipairs(lots) do
		S.EconomyService.Record(player, lg.MallId, lotId, "StockCost", cost / #lots)
	end
	lg.Dock.Pending = true
	refreshLogistics(lg)
	S.MessageService.Tip(player, "Logistics", "Downtown deliveries are generic supplies: dock -> stockroom -> any store. Stockroom space is the bottleneck. Upgrade it in the Business panel.")
	-- van drives in
	local van = lg.Van
	local parked = van:GetPivot()
	task.spawn(function()
		local dur = L.DeliverySeconds * 0.8
		local t0 = os.clock()
		while os.clock() - t0 < dur and van.Parent do
			local a = (os.clock() - t0) / dur
			van:PivotTo(parked * CFrame.new(0, 0, 40 * (1 - a) ^ 2))
			task.wait(0.05)
		end
		if van.Parent then
			van:PivotTo(parked)
		end
	end)
	task.delay(L.DeliverySeconds, function()
		if logistics[("%d:%d"):format(lg.MallId, lg.Floor)] ~= lg then
			return
		end
		lg.Dock.Pending = false
		lg.Dock.Boxes += boxes
		refreshLogistics(lg)
		S.MessageService.Toast(player, ("Delivery arrived: %d boxes at the dock."):format(boxes), "good")
		push(player)
	end)
	push(player)
	return true
end

function StoreService.TakeDockBox(player, lg)
	if lg.Dock.Boxes <= 0 then
		if player then
			S.MessageService.Toast(player, "No boxes on the dock. Order a delivery.", "info")
		end
		return false
	end
	if player then
		if Carry.Get(player) then
			S.MessageService.Toast(player, "Your hands are full.", "bad")
			return false
		end
		if not Carry.Give(player, "StockBox", { Source = "Dock", Mall = lg.MallId }) then
			return false
		end
	end
	lg.Dock.Boxes -= 1
	refreshLogistics(lg)
	return true
end

function StoreService.StoreBoxInStockroom(player, lg)
	local data = lg.MallData.Stockroom
	if player then
		local c = Carry.Get(player)
		if not c or c.Kind ~= "StockBox" or c.Data.Source ~= "Dock" then
			S.MessageService.Toast(player, "Bring a box from the loading dock.", "info")
			return false
		end
		if data.Boxes >= data.Capacity then
			S.MessageService.Toast(player, "The stockroom is full. Restock shelves or upgrade its capacity.", "bad")
			return false
		end
		Carry.Take(player, "StockBox")
		if player ~= lg.Owner then
			S.AssistService.Reward(player, lg.Owner, lg.MallId .. ":stockroom", lg.Stockroom.Part.Position)
		end
	elseif data.Boxes >= data.Capacity then
		return false
	end
	data.Boxes += 1
	refreshLogistics(lg)
	push(lg.Owner)
	return true
end

function StoreService.TakeStockroomBox(player, lg)
	local data = lg.MallData.Stockroom
	if data.Boxes <= 0 then
		if player then
			S.MessageService.Toast(player, "The stockroom is empty.", "info")
		end
		return false
	end
	if player then
		if Carry.Get(player) then
			S.MessageService.Toast(player, "Your hands are full.", "bad")
			return false
		end
		if not Carry.Give(player, "StockBox", { Source = "Stockroom", Mall = lg.MallId }) then
			return false
		end
	end
	data.Boxes -= 1
	refreshLogistics(lg)
	push(lg.Owner)
	return true
end

function StoreService.UpgradeStockroom(player, mallId)
	local profile = S.DataService.GetProfile(player)
	local mall = Malls[mallId]
	if not profile or not mall.Logistics then
		return false
	end
	local data = profile.Malls[tostring(mallId)].Stockroom
	local up = mall.Logistics.StockroomUpgrade
	if data.Capacity >= up.Capacity then
		S.MessageService.Toast(player, "The stockroom is already expanded.", "info")
		return false
	end
	if not S.EconomyService.TrySpend(player, up.Cost, "Upgrade") then
		return false
	end
	data.Capacity = up.Capacity
	local lg = StoreService.Logistics(mallId, S.FloorService.GetFloor(player))
	if lg then
		refreshLogistics(lg)
	end
	S.MessageService.Toast(player, ("Stockroom expanded to %d boxes."):format(up.Capacity), "good")
	push(player)
	return true
end

local function buildLogistics(player, mallId, floor, profile)
	local mall = Malls[mallId]
	local L = mall.Logistics
	local k = ("%d:%d"):format(mallId, floor)
	if logistics[k] then
		logistics[k].Folder:Destroy()
	end
	local folder = Instance.new("Model")
	folder.Name = "Logistics"
	folder.Parent = S.MallService.DynamicFolder(mallId, floor)
	local origin = S.MallService.FloorOrigin(mallId, floor)
	local lg = { Owner = player, MallId = mallId, Floor = floor, MallData = profile.Malls[tostring(mallId)], Folder = folder, Dock = { Boxes = 0, Pending = false, Visuals = {} }, Stockroom = { Visuals = {} } }
	-- van parked beside the dock
	lg.Van = AssetRegistry.Place("DeliveryVan", CFrame.new(origin + L.DockPos + Vector3.new(-6, 1.2, 0)), folder, 180)
	AssetRegistry.Place("HandTruck", CFrame.new(origin + L.DockPos + Vector3.new(10, 1.2, 4)), folder, 30)
	local dock = Instance.new("Part")
	dock.Name = "DockPallet"
	dock.Size = Vector3.new(8, 0.5, 3)
	dock.Anchored = true
	dock.Color = AssetRegistry.Colors.Wood
	dock.Material = Enum.Material.WoodPlanks
	dock.CFrame = CFrame.new(origin + L.DockPos + Vector3.new(6, 1.45, -3))
	dock.Parent = folder
	lg.Dock.Part = dock
	lg.Dock.Label = label(dock, "", 5, UDim2.fromOffset(260, 36))
	local boxes = S.ProjectService.DeliveryBoxes(mallId)
	local order = prompt(dock, ("Order delivery (%s)"):format(Format.Cash(boxes * L.DeliveryCostPerBox)), "Loading dock", { Key = Enum.KeyCode.R, Gamepad = Enum.KeyCode.ButtonY, Offset = Vector2.new(0, -40), Distance = 10 })
	order.Triggered:Connect(function(who)
		StoreService.OrderDelivery(who, lg)
	end)
	lg.Dock.OrderPrompt = order
	local take = prompt(dock, "Take box", "Loading dock", { Distance = 10 })
	take.Triggered:Connect(function(who)
		if near(who, dock.Position) then
			StoreService.TakeDockBox(who, lg)
		end
	end)
	lg.Dock.TakePrompt = take
	-- stockroom rack
	local rack = AssetRegistry.Place("StockroomRack", CFrame.new(origin + L.StockroomPos), folder, 0)
	local rackPart = anchorOf(rack)
	lg.Stockroom.Part = rackPart
	lg.Stockroom.Label = label(rackPart, "", 10.5, UDim2.fromOffset(220, 36))
	local store = prompt(rackPart, "Store box", "Stockroom", { Key = Enum.KeyCode.R, Gamepad = Enum.KeyCode.ButtonY, Offset = Vector2.new(0, -40), Distance = 10 })
	store.Triggered:Connect(function(who)
		if near(who, rackPart.Position) then
			StoreService.StoreBoxInStockroom(who, lg)
		end
	end)
	local takeS = prompt(rackPart, "Take box", "Stockroom", { Distance = 10 })
	takeS.Triggered:Connect(function(who)
		if near(who, rackPart.Position) then
			StoreService.TakeStockroomBox(who, lg)
		end
	end)
	lg.Stockroom.TakePrompt = takeS
	logistics[k] = lg
	refreshLogistics(lg)
	return lg
end

-- Purchases ------------------------------------------------------------------------------

function StoreService.BuyLot(player, mallId, lotId)
	local profile = S.DataService.GetProfile(player)
	local floor = S.FloorService.GetFloor(player)
	local lot = S.MallService.LotCfg(mallId, lotId)
	if not profile or not floor or not lot then
		return false
	end
	if not profile.UnlockedMalls[tostring(mallId)] then
		S.MessageService.Toast(player, "You do not have a floor in this mall yet.", "bad")
		return false
	end
	local mallData = profile.Malls[tostring(mallId)]
	if mallData.Lots[lotId] then
		S.MessageService.Toast(player, "You already own this store.", "info")
		return false
	end
	-- only the owner of this floor can lease on it (visitors cannot claim businesses)
	local where, whereFloor = S.FloorService.WhereIs(player)
	if where ~= mallId or whereFloor ~= floor then
		S.MessageService.Toast(player, "You can only lease stores on your own floor.", "bad")
		return false
	end
	if not S.EconomyService.TrySpend(player, lot.Cost, "Lease") then
		return false
	end
	mallData.Lots[lotId] = S.DataService.NewLotState(lot.Store)
	buildStore(player, mallId, floor, lot, profile)
	local cfg = Stores[lot.Store]
	S.MessageService.Toast(player, ("%s opened! New interaction: %s."):format(cfg.Name, cfg.Interaction == "Match" and "match outfits to customer requests" or cfg.Interaction == "Assemble" and "assemble food orders" or cfg.Interaction == "MatchDemo" and "match gadgets and run demos" or cfg.Interaction == "Repair" and "keep the machines running" or "restock and serve"), "big")
	Remotes.Effect:FireClient(player, { Kind = "Celebrate", Small = true })
	if S.WorkerService then
		S.WorkerService.OnLotOpened(player, mallId, floor, lotId)
	end
	evaluate(player)
	push(player)
	return true
end

function StoreService.BuyUpgrade(player, mallId, lotId, upgradeId)
	local profile = S.DataService.GetProfile(player)
	local floor = S.FloorService.GetFloor(player)
	if not profile or not floor then
		return false
	end
	local st = stores[key(mallId, floor, lotId)]
	if not st or st.Owner ~= player then
		return false
	end
	local up
	for _, u in ipairs(st.Cfg.Upgrades) do
		if u.Id == upgradeId then
			up = u
		end
	end
	if not up or st.Data.Upgrades[upgradeId] then
		return false
	end
	local cost = math.floor(up.Cost * st.Mall.PriceMultiplier + 0.5)
	if not S.EconomyService.TrySpend(player, cost, "Upgrade") then
		return false
	end
	st.Data.Upgrades[upgradeId] = true
	-- rebuild the store (shelves / displays / machines may change); keep stock
	local lot = S.MallService.LotCfg(mallId, lotId)
	local rebuilt = buildStore(player, mallId, floor, lot, profile)
	if S.WorkerService then
		S.WorkerService.OnStoreRebuilt(rebuilt)
	end
	S.MessageService.Toast(player, ("%s installed in %s."):format(up.Name, st.Cfg.Name), "good")
	S.MessageService.Tip(player, "Upgrade", "Upgrades are reinvestment: they cost now and pay back over many sales.")
	evaluate(player)
	push(player)
	return true
end

-- Floor lifecycle -------------------------------------------------------------------------

function StoreService.BuildFloor(player, mallId, floor)
	local profile = S.DataService.GetProfile(player)
	local mall = Malls[mallId]
	for _, lot in ipairs(mall.Lots) do
		if profile.Malls[tostring(mallId)].Lots[lot.Id] then
			buildStore(player, mallId, floor, lot, profile)
		else
			buildLockedLot(player, mallId, floor, lot)
		end
	end
	if mall.Logistics then
		buildLogistics(player, mallId, floor, profile)
	end
end

local function releaseFloor(player, floor)
	for k, st in pairs(stores) do
		if st.Owner == player then
			stores[k] = nil
		end
	end
	for k, m in pairs(lockedLots) do
		if m.Parent and m.Parent.Parent and m.Parent.Parent.Name == "Floor" .. floor then
			lockedLots[k] = nil
		end
	end
	for k, lg in pairs(logistics) do
		if lg.Owner == player then
			logistics[k] = nil
		end
	end
	for token, rec in pairs(minigames) do
		if rec.Player == player or rec.Store.Owner == player then
			minigames[token] = nil
		end
	end
end

-- Economic simulation for stores on floors nobody is on ---------------------------------------

local function simulateTick()
	local dt = Economy.Simulation.TickSeconds
	for _, st in pairs(stores) do
		if not S.FloorService.IsFloorActive(st.MallId, st.Floor) then
			local worker = S.WorkerService and S.WorkerService.SellerFor(st)
			if not worker and st.Kiosk then
				worker = "Kiosk"
			end
			if worker then
				local perCustomer = (st.Cfg.ItemsPerCustomer[1] + st.Cfg.ItemsPerCustomer[2]) / 2
				local customers = dt / Economy.Customers.SpawnIntervalSeconds * Economy.Simulation.InactiveSaleRate
				local units = math.floor(customers * perCustomer + math.random())
				if units > 0 then
					if st.Cfg.ShelfCapacity > 0 then
						units = math.min(units, StoreService.TotalStock(st))
						local need = units
						for _, sh in ipairs(st.Shelves) do
							local take = math.min(sh.Stock, need)
							sh.Stock -= take
							need -= take
						end
						syncStock(st)
					end
					if units > 0 then
						StoreService.CompleteSale(st, nil, worker, units, 0)
					end
				end
				-- stockers keep shelves filled from the pallet
				local stocker = S.WorkerService.StockerFor(st)
				if stocker and StoreService.PalletHasBox(st) then
					local sh = StoreService.ShelfNeedingStock(st)
					if sh then
						local okTake, units = StoreService.TakeBoxFromPallet(nil, st)
						if okTake then
							local _, left = StoreService.RestockShelf(st, sh, units, stocker)
							StoreService.ReturnUnitsToPallet(st, left)
						end
					end
				end
			end
		end
	end
end

-- a dropped stock box that nobody picked up again goes back to where it came from
local function returnBox(kind, data)
	if kind ~= "StockBox" or type(data) ~= "table" then
		return
	end
	if data.Source == "Pallet" and data.Store then
		local st = stores[data.Store]
		if st and st.Pallet then
			StoreService.ReturnUnitsToPallet(st, data.Units or StoreService.BoxUnits(st))
		end
	elseif data.Source == "Stockroom" and data.Opened and data.Store then
		-- an opened generic box already became this store's product: its leftovers go to the store's own pallet-less shelf pool
		local st = stores[data.Store]
		if st then
			local sh = StoreService.ShelfNeedingStock(st)
			if sh then
				StoreService.RestockShelf(st, sh, data.Units or 0, nil)
			end
		end
	elseif (data.Source == "Stockroom" or data.Source == "Dock") and data.Mall then
		for _, lg in pairs(logistics) do
			if lg.MallId == data.Mall then
				if data.Source == "Stockroom" then
					StoreService.StoreBoxInStockroom(nil, lg)
				else
					lg.Dock.Boxes += 1
					refreshLogistics(lg)
				end
			end
		end
	end
end

-- Dropping a pallet box within reach of its own pallet puts it straight back (with its remaining units)
local function dropNearPallet(player, kind, data, position)
	if kind ~= "StockBox" or type(data) ~= "table" or data.Source ~= "Pallet" or not data.Store then
		return false
	end
	local st = stores[data.Store]
	if not st or not st.Pallet or (st.Pallet.Part.Position - position).Magnitude > 12 then
		return false
	end
	StoreService.ReturnUnitsToPallet(st, data.Units or StoreService.BoxUnits(st))
	S.MessageService.Toast(player, ("Box put back on the delivery point (%d units)."):format(data.Units or StoreService.BoxUnits(st)), "good")
	push(st.Owner)
	return true
end

function StoreService.Init(services)
	S = services
	Carry.OnExpire = returnBox
	Carry.OnDrop = dropNearPallet
end

function StoreService.Start()
	S.FloorService.OnFloorReleased:Connect(releaseFloor)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, st in pairs(stores) do
				if S.FloorService.IsFloorActive(st.MallId, st.Floor) then
					pcall(refreshPrompts, st)
					pcall(StoreService.KioskTick, st)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Economy.Simulation.TickSeconds)
			local ok, err = pcall(simulateTick)
			if not ok then
				warn("[Shoprise] simulateTick: " .. tostring(err))
			end
		end
	end)
end

return StoreService
