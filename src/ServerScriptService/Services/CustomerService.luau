--[[
	CustomerService — NPC shoppers for stores on floors that have a player on them. Customers enter,
	browse/queue/request, get served (by a player or a worker), pay and leave. Floors without players
	are simulated economically by StoreService instead. Also runs the periodic shopping rush.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Config.Economy)
local Malls = require(ReplicatedStorage.Config.Malls)
local Constants = require(ReplicatedStorage.Shared.Constants)

local CustomerService = {}
local S
local customers = {} -- set
local total = 0
local rushUntil = 0
local SHIRTS = { Color3.fromRGB(240, 120, 110), Color3.fromRGB(64, 150, 150), Color3.fromRGB(250, 210, 80), Color3.fromRGB(140, 110, 200), Color3.fromRGB(90, 180, 90), Color3.fromRGB(250, 170, 60) }
local ICON = Constants.ICONS

local function alive(c)
	return c.Npc and c.Npc.Parent ~= nil and c.Store.Folder.Parent ~= nil and S.StoreService.Get(c.Store.MallId, c.Store.Floor, c.Store.LotId) == c.Store
end

local function bubble(c, text, color)
	S.NpcService.SetBubble(c.Npc, text, color)
end

local function corridorPoint(st, x)
	return S.MallService.ToWorld(st.MallId, st.Floor, Vector3.new(x, 0, S.MallService.CORRIDOR_Z))
end

local function lotFront(st)
	return (st.Frame * CFrame.new(0, 0, S.MallService.LOT_D / 2 + 3)).Position
end

local function pathIn(c, target)
	local st = c.Store
	local entrance = c.Entrance
	local lotX = S.MallService.LotCfg(st.MallId, st.LotId).Pos.X
	return S.NpcService.WalkPath(c.Npc, { corridorPoint(st, entrance.X - S.MallService.FloorOrigin(st.MallId, st.Floor).X), corridorPoint(st, lotX), lotFront(st), target }, 14)
end

local function leave(c)
	local st = c.Store
	if not c.Npc.Parent then
		return
	end
	c.State = "Leaving"
	if c.Angry then
		bubble(c, "😠", Color3.fromRGB(200, 60, 50))
	elseif c.Served then
		bubble(c, ICON.Cash, Color3.fromRGB(40, 150, 80))
	end
	task.wait(0.25) -- served customers head out right away; the bubble stays while they walk
	local lotX = S.MallService.LotCfg(st.MallId, st.LotId).Pos.X
	S.NpcService.WalkPath(c.Npc, { lotFront(st), corridorPoint(st, lotX), corridorPoint(st, c.Entrance.X - S.MallService.FloorOrigin(st.MallId, st.Floor).X), c.Entrance }, 14)
end

-- wait until predicate() or timeout; returns predicate result
local function waitFor(c, predicate, timeout)
	local deadline = os.clock() + timeout
	while alive(c) and os.clock() < deadline do
		local r = predicate()
		if r then
			return r
		end
		task.wait(0.25)
	end
	return nil
end

local function queueLoop(c, st, waitingState)
	c.State = "Queued"
	local idx = S.StoreService.JoinQueue(st, c)
	local lastIdx = nil
	local patience = S.StoreService.Patience(st)
	local started = os.clock()
	local function done()
		return c.Served or c.State == "Served" or c.State == "Leaving"
	end
	while alive(c) and not done() do
		local i = S.StoreService.QueueIndex(st, c)
		if not i then
			break
		end
		if i ~= lastIdx then
			lastIdx = i
			S.NpcService.MoveTo(c.Npc, S.StoreService.QueueSpot(st, i), 8, done)
			if done() then
				break
			end
			S.NpcService.Face(c.Npc, st.Counter.Part.Position)
			if i == 1 then
				if waitingState == "Waiting" and c.State == "Queued" then
					c.State = "Waiting"
					c.Request = c.Request or S.StoreService.RandomRequest(st)
					bubble(c, S.StoreService.RequestText(st, c.Request))
					started = os.clock()
				elseif waitingState == "Queued" then
					bubble(c, "🧾")
				end
			else
				bubble(c, "⏳")
			end
		end
		if os.clock() - started > patience and not c.Busy and not done() then
			-- gave up waiting
			c.Angry = true
			S.StoreService.LeaveQueue(st, c)
			S.StoreService.CustomerLeftAngry(st, "wait")
			c.State = "Leaving"
			break
		end
		task.wait(0.3)
	end
end

local function lifecycleRestock(c, st)
	local shelf
	for _, sh in ipairs(st.Shelves) do
		if sh.Stock > 0 and (not shelf or math.random() < 0.5) then
			shelf = sh
		end
	end
	shelf = shelf or st.Shelves[math.random(#st.Shelves)]
	if not pathIn(c, shelf.Spot) then
		return
	end
	c.State = "Browsing"
	S.NpcService.Face(c.Npc, shelf.Part.Position)
	bubble(c, st.Cfg.ProductIcon .. "?")
	task.wait(Economy.Customers.BrowseSeconds)
	if not alive(c) then
		return
	end
	if shelf.Stock <= 0 then
		bubble(c, "😕 empty", Color3.fromRGB(200, 60, 50))
		c.Angry = true
		S.StoreService.CustomerLeftAngry(st, "empty")
		task.wait(1)
		return
	end
	local want = math.random(st.Cfg.ItemsPerCustomer[1], st.Cfg.ItemsPerCustomer[2])
	c.Items = math.min(want, shelf.Stock)
	shelf.Stock -= c.Items
	c.Shelf = shelf
	S.StoreService.SyncStock(st)
	bubble(c, ("%s x%d"):format(st.Cfg.ProductIcon, c.Items))
	queueLoop(c, st, "Queued")
	if not c.Served and c.Shelf then
		-- items go back to the shelf
		c.Shelf.Stock = math.min(st.Cfg.ShelfCapacity, c.Shelf.Stock + c.Items)
		S.StoreService.SyncStock(st)
	end
end

local function lifecycleMatch(c, st)
	if S.StoreService.TotalStock(st) <= 0 then
		pathIn(c, lotFront(st) + st.Frame.LookVector * -4)
		bubble(c, "😕 empty", Color3.fromRGB(200, 60, 50))
		c.Angry = true
		S.StoreService.CustomerLeftAngry(st, "empty")
		task.wait(1.2)
		return
	end
	local display = waitFor(c, function()
		return S.StoreService.FreeDisplay(st)
	end, 20)
	if not display then
		c.Angry = true
		return
	end
	display.Customer = c
	c.Display = display
	if not pathIn(c, display.Spot) then
		display.Customer = nil
		return
	end
	S.NpcService.Face(c.Npc, display.Part.Position)
	c.Request = S.StoreService.RandomRequest(st)
	c.State = "Waiting"
	bubble(c, S.StoreService.RequestText(st, c.Request))
	local served = waitFor(c, function()
		return c.State ~= "Waiting" and c.State
	end, S.StoreService.Patience(st) + 15)
	if not served or c.State == "Waiting" then
		c.State = "Leaving"
		c.Angry = true
		display.Customer = nil
		S.StoreService.CustomerLeftAngry(st, "wait")
	end
end

local function lifecycleRequestQueue(c, st)
	pathIn(c, st.Counter.Spot)
	queueLoop(c, st, "Waiting")
end

local function lifecycleArcade(c, st)
	pathIn(c, lotFront(st) + st.Frame.LookVector * -4)
	bubble(c, "🕹️?")
	local m = waitFor(c, function()
		return S.StoreService.FreeMachine(st)
	end, 12)
	if not m then
		bubble(c, "😕 broken", Color3.fromRGB(200, 60, 50))
		c.Angry = true
		S.StoreService.CustomerLeftAngry(st, "wait")
		task.wait(1)
		return
	end
	m.Customer = c
	c.Items = math.random(st.Cfg.ItemsPerCustomer[1], st.Cfg.ItemsPerCustomer[2])
	S.NpcService.MoveTo(c.Npc, m.Spot, 10)
	S.NpcService.Face(c.Npc, m.Part.Position)
	bubble(c, "🕹️")
	task.wait(3)
	if alive(c) then
		S.StoreService.PlayMachine(st, m, c)
		task.wait(1.5)
	end
	m.Customer = nil
end

local function lifecycle(c)
	local st = c.Store
	local kind = st.Cfg.Interaction
	local ok, err = pcall(function()
		if kind == "Restock" then
			lifecycleRestock(c, st)
		elseif kind == "Match" then
			lifecycleMatch(c, st)
		elseif kind == "Assemble" or kind == "MatchDemo" then
			lifecycleRequestQueue(c, st)
		elseif kind == "Repair" then
			lifecycleArcade(c, st)
		end
		if alive(c) then
			leave(c)
		end
	end)
	if not ok then
		warn("[Shoprise] customer lifecycle: " .. tostring(err))
	end
	-- cleanup
	if c.Display and c.Display.Customer == c then
		c.Display.Customer = nil
	end
	S.StoreService.LeaveQueue(st, c)
	st.Customers[c] = nil
	customers[c] = nil
	total -= 1
	S.NpcService.Destroy(c.Npc)
end

local function spawnCustomer(st)
	local entrances = S.MallService.Entrances(st.MallId, st.Floor)
	local entrance = entrances[math.random(#entrances)]
	local npc = S.NpcService.Create({ Name = "Customer", Shirt = SHIRTS[math.random(#SHIRTS)], Position = entrance, WalkSpeed = 12 + math.random() * 3 })
	local c = { Npc = npc, Store = st, State = "Walking", Entrance = entrance, Items = 1 }
	customers[c] = true
	st.Customers[c] = true
	total += 1
	task.spawn(lifecycle, c)
end

local function countIn(st)
	local n = 0
	for _ in pairs(st.Customers) do
		n += 1
	end
	return n
end

local function spawnerTick()
	local now = os.clock()
	local rush = now < rushUntil
	for _, mall in ipairs(Malls) do
		for f = 1, mall.Floors do
			if S.FloorService.IsFloorActive(mall.Id, f) then
				for _, st in ipairs(S.StoreService.ActiveStoresOn(mall.Id, f)) do
					local max = Economy.Customers.MaxPerStore + (rush and 2 or 0)
					if countIn(st) < max and total < Economy.Customers.MaxPerServer then
						st.NextSpawn = st.NextSpawn or now + 2
						if now >= st.NextSpawn then
							spawnCustomer(st)
							local sat = st.Data.Satisfaction or 80
							local interval = Economy.Customers.SpawnIntervalSeconds * (1.3 - sat / 100 * 0.6)
							if st.Cfg.ShelfCapacity > 0 and S.StoreService.TotalStock(st) == 0 then
								interval *= 2
							end
							if rush then
								interval /= Economy.Rush.SpawnMultiplier
							end
							st.NextSpawn = now + math.max(Economy.Customers.MinSpawnIntervalSeconds, interval + math.random() * 2)
						end
					end
				end
			end
		end
	end
end

function CustomerService.IsRush()
	return os.clock() < rushUntil
end

function CustomerService.Init(services)
	S = services
end

function CustomerService.Start()
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(spawnerTick)
			if not ok then
				warn("[Shoprise] spawnerTick: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		task.wait(Economy.Rush.FirstAfterSeconds)
		while true do
			rushUntil = os.clock() + Economy.Rush.DurationSeconds
			S.MessageService.Broadcast(Economy.Rush.AnnounceText, "big")
			task.wait(Economy.Rush.IntervalSeconds)
		end
	end)
	S.FloorService.OnFloorReleased:Connect(function(player)
		for c in pairs(customers) do
			if c.Store.Owner == player then
				S.NpcService.Destroy(c.Npc)
			end
		end
	end)
end

return CustomerService
