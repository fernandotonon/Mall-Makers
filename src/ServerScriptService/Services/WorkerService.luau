--[[
	WorkerService — worker discovery scenes (lost delivery, dark staff room, kiosk trial), hiring,
	worker NPCs that automate store tasks, levels, and manager assignment for earlier malls.
]]
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Config.Economy)
local Workers = require(ReplicatedStorage.Config.Workers)
local Stores = require(ReplicatedStorage.Config.Stores)
local Malls = require(ReplicatedStorage.Config.Malls)
local Format = require(ReplicatedStorage.Shared.Format)
local Constants = require(ReplicatedStorage.Shared.Constants)
local AssetRegistry = require(ReplicatedStorage.Shared.AssetRegistry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Carry = require(script.Parent.Carry)

local WorkerService = {}
local S
local scenes = {} -- "mallId:floor:discId" -> { Folder, Player, ... }
local runtime = {} -- worker.Id -> { Worker, Npc, Store, Alive, Owner }
local ICON = Constants.ICONS

local function near(player, position, dist)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and (root.Position - position).Magnitude <= (dist or Constants.INTERACT_DISTANCE)
end

local function prompt(parent, action, object, hold, keyR)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object or ""
	p.MaxActivationDistance = 9
	p.HoldDuration = hold or 0
	p.RequiresLineOfSight = false
	if keyR then
		p.KeyboardKeyCode = Enum.KeyCode.R
		p.GamepadKeyCode = Enum.KeyCode.ButtonY
	end
	p.Parent = parent
	return p
end

local function label(parent, text, offsetY, width)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(width or 240, 44)
	bb.StudsOffset = Vector3.new(0, offsetY or 4, 0)
	bb.MaxDistance = 40
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
	tl.BackgroundTransparency = 0.2
	tl.TextScaled = true
	tl.TextWrapped = true
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

-- Levels ---------------------------------------------------------------------------------

function WorkerService.Level(w)
	local lvl = 1
	for i, L in ipairs(Economy.WorkerLevels) do
		if (w.Tasks or 0) >= L.Tasks then
			lvl = i
		end
	end
	return lvl, Economy.WorkerLevels[lvl]
end

function WorkerService.CountTask(w)
	local before = WorkerService.Level(w)
	w.Tasks = (w.Tasks or 0) + 1
	local after, info = WorkerService.Level(w)
	local rt = runtime[w.Id]
	if after > before and rt and rt.Owner then
		S.MessageService.Toast(rt.Owner, ("Your %s is now %s (works %d%% faster)."):format(Workers[w.Type].Name, info.Label, math.floor((info.Speed - 1) * 100 + 0.5)), "good")
		push(rt.Owner)
	end
end

function WorkerService.GetWorkers(player, mallId)
	local profile = S.DataService.GetProfile(player)
	if not profile then
		return {}
	end
	return profile.Malls[tostring(mallId)].Workers
end

local function workersIn(st, typ)
	local list = {}
	for _, w in ipairs(st.MallData.Workers) do
		if w.Lot == st.LotId and (not typ or w.Type == typ) and not w.Unpaid then
			table.insert(list, w)
		end
	end
	return list
end

-- a worker that can complete sales in this store (used by the inactive-floor simulation)
function WorkerService.SellerFor(st)
	local kinds = ({ Convenience = { "Cashier" }, Clothing = { "Cashier" }, FoodKiosk = { "Cook" }, Electronics = { "Cashier", "Technician" }, Arcade = { "Technician" } })[st.Type] or {}
	for _, k in ipairs(kinds) do
		local w = workersIn(st, k)[1]
		if w then
			return w
		end
	end
	return nil
end

function WorkerService.StockerFor(st)
	return workersIn(st, "Stocker")[1]
end

-- Worker NPC behaviour ---------------------------------------------------------------------

local function stationFor(st, w)
	if w.Type == "Stocker" then
		return st.Pallet and (st.Pallet.Part.Position + st.Frame.RightVector * -3) or (st.Frame * CFrame.new(8, 0, 10)).Position
	end
	if st.Counter then
		return st.Counter.ServeSpot
	end
	return (st.Frame * CFrame.new(0, 0, 0)).Position
end

local function runWorker(rt)
	local w, st, npc = rt.Worker, rt.Store, rt.Npc
	local cfg = Workers[w.Type]
	local function ok()
		return rt.Alive and npc.Parent and S.StoreService.Get(st.MallId, st.Floor, st.LotId) == st
	end
	local function speed()
		local _, info = WorkerService.Level(w)
		return info.Speed
	end
	local function work(seconds, text)
		S.NpcService.SetBubble(npc, text)
		local t0 = os.clock()
		while ok() and os.clock() - t0 < seconds / speed() do
			task.wait(0.2)
		end
		S.NpcService.SetBubble(npc, nil)
		return ok()
	end
	while ok() do
		if w.Unpaid then
			S.NpcService.SetBubble(npc, "💤 unpaid", Color3.fromRGB(200, 60, 50))
			task.wait(2)
		elseif not S.FloorService.IsFloorActive(st.MallId, st.Floor) then
			task.wait(2)
		else
			local did = false
			if w.Type == "Cashier" or (w.Type == "Technician" and st.Type == "Electronics") then
				local c, display = S.StoreService.NextRequest(st)
				if not c then
					c = S.StoreService.NextQueued(st)
				end
				if c and not c.Busy then
					c.Busy = w
					local target = display and (display.Part.Position + display.Spot - display.Part.Position) or st.Counter.ServeSpot
					if display then
						target = display.Part.Position + (display.Spot - display.Part.Position).Unit * -2.5
					end
					S.NpcService.MoveTo(npc, target, 8)
					S.NpcService.Face(npc, c.Npc.PrimaryPart and c.Npc.PrimaryPart.Position or target)
					if work(cfg.ServeSeconds or 4, "🧾") and c.Busy == w then
						if c.State == "Waiting" then
							if S.StoreService.TotalStock(st) >= (c.Request and c.Request.Order and #c.Request.Order or 1) or st.Cfg.ShelfCapacity == 0 then
								S.StoreService.ResolveRequest(st, c, w)
							else
								S.NpcService.SetBubble(npc, "📦!", Color3.fromRGB(200, 60, 50))
								task.wait(1.5)
							end
						elseif c.State == "Queued" then
							c.Busy = nil
							S.StoreService.ServeQueued(st, w)
						end
					end
					if c.Busy == w then
						c.Busy = nil
					end
					did = true
				end
				if not did and w.Type == "Technician" then
					if S.StoreService.PendingDemo(st) then
						S.NpcService.MoveTo(npc, st.Stations.Demo.Position + st.Frame.LookVector * 3, 8)
						if work(2, "🎧") then
							S.StoreService.WorkerDemo(st, w)
						end
						did = true
					end
				end
			elseif w.Type == "Cook" then
				local c = S.StoreService.NextRequest(st)
				if c and not c.Busy then
					c.Busy = w
					local units = c.Request and c.Request.Order and #c.Request.Order or 1
					if S.StoreService.TotalStock(st) >= units then
						S.NpcService.MoveTo(npc, st.Stations.Griddle.Position + st.Frame.LookVector * 2.5, 8)
						if work((cfg.AssembleSeconds or 4) / (S.StoreService.HasUpgrade(st, "SecondGriddle") and 1.4 or 1), "🍳") and c.Busy == w then
							S.NpcService.MoveTo(npc, st.Counter.ServeSpot, 6)
							S.StoreService.ResolveRequest(st, c, w)
						end
					else
						S.NpcService.SetBubble(npc, "📦!", Color3.fromRGB(200, 60, 50))
						task.wait(1.5)
					end
					if c.Busy == w then
						c.Busy = nil
					end
					did = true
				end
			elseif w.Type == "Stocker" then
				local shelf = S.StoreService.ShelfNeedingStock(st)
				if shelf and shelf.Stock <= st.Cfg.ShelfCapacity * 0.75 then
					local lg = st.Mall.Logistics and S.StoreService.Logistics(st.MallId, st.Floor)
					local source, takeFn
					if lg then
						if lg.MallData.Stockroom.Boxes > 0 then
							source = lg.Stockroom.Part.Position + Vector3.new(0, 0, 4)
							takeFn = function()
								return S.StoreService.TakeStockroomBox(nil, lg)
							end
						end
					elseif S.StoreService.PalletHasBox(st) then
						source = st.Pallet.Part.Position + st.Frame.RightVector * -3
						takeFn = function()
							return S.StoreService.TakeBoxFromPallet(nil, st)
						end
					end
					if source then
						S.NpcService.MoveTo(npc, source, 10)
						if ok() and takeFn() then
							local box = AssetRegistry.Place("StockBox", npc.PrimaryPart.CFrame * CFrame.new(0, -0.5, -1.6), npc, 0)
							for _, d in ipairs(box:GetDescendants()) do
								if d:IsA("BasePart") then
									d.Anchored = false
									d.CanCollide = false
									d.Massless = true
									local weld = Instance.new("WeldConstraint")
									weld.Part0 = npc.PrimaryPart
									weld.Part1 = d
									weld.Parent = d
								end
							end
							S.NpcService.MoveTo(npc, shelf.Spot, 10)
							S.NpcService.Face(npc, shelf.Part.Position)
							local done = work(cfg.RestockSeconds or 6, ICON.Box)
							box:Destroy()
							if done then
								S.StoreService.RestockShelf(st, shelf, S.StoreService.BoxUnits(st), w)
							end
						end
						did = true
					end
				end
			elseif w.Type == "Technician" and st.Type == "Arcade" then
				local m = S.StoreService.BrokenMachine(st)
				if m then
					m.Busy = w
					S.NpcService.MoveTo(npc, m.Spot, 8)
					S.NpcService.Face(npc, m.Part.Position)
					if work(cfg.RepairSeconds or 6, ICON.Wrench) then
						S.StoreService.RepairMachine(st, m, w)
					end
					if m.Busy == w then
						m.Busy = nil
					end
					did = true
				end
			end
			if not did then
				-- idle at the station
				local root = npc.PrimaryPart
				local station = stationFor(st, w)
				if root and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(station.X, 0, station.Z)).Magnitude > 3 then
					S.NpcService.MoveTo(npc, station, 8)
				end
				task.wait(0.8)
			end
		end
	end
	S.NpcService.Destroy(npc)
end

local function spawnWorker(owner, mallId, floor, w)
	if runtime[w.Id] then
		runtime[w.Id].Alive = false
		S.NpcService.Destroy(runtime[w.Id].Npc)
		runtime[w.Id] = nil
	end
	local cfg = Workers[w.Type]
	local st = w.Lot and S.StoreService.Get(mallId, floor, w.Lot)
	local pos
	if w.Type == "Manager" then
		pos = S.MallService.ToWorld(mallId, floor, S.MallService.BOARD_POS + Vector3.new(5, 0, -3))
	elseif st then
		pos = stationFor(st, w)
	else
		pos = S.MallService.ToWorld(mallId, floor, S.MallService.SPAWN + Vector3.new(6, 0, -4))
	end
	local npc = S.NpcService.Create({ Name = "Worker_" .. w.Type, Shirt = cfg.Shirt, Hat = w.Type == "Cook" and Color3.new(1, 1, 1) or nil, Position = pos, WalkSpeed = 13 })
	local rt = { Worker = w, Npc = npc, Store = st, Alive = true, Owner = owner }
	runtime[w.Id] = rt
	local lvl, info = WorkerService.Level(w)
	label(npc.Head, ("%s · %s"):format(cfg.Name, info.Label), 2.8, 160)
	if w.Type == "Manager" then
		S.NpcService.SetBubble(npc, "📋")
	elseif st then
		task.spawn(runWorker, rt)
	else
		S.NpcService.SetBubble(npc, "💤 no store", Color3.fromRGB(200, 60, 50))
	end
	return rt
end

-- Discovery scenes ---------------------------------------------------------------------------

local function sceneKey(mallId, floor, discId)
	return ("%d:%d:%s"):format(mallId, floor, discId)
end

local function pickLot(player, mallId, workerType)
	local profile = S.DataService.GetProfile(player)
	local mallData = profile.Malls[tostring(mallId)]
	if workerType == "Manager" then
		return nil
	end
	local best, bestCount
	for lotId, lot in pairs(mallData.Lots) do
		local cfg = Stores[lot.Store]
		if table.find(cfg.Workers, workerType) then
			local count = 0
			for _, w in ipairs(mallData.Workers) do
				if w.Lot == lotId and w.Type == workerType then
					count += 1
				end
			end
			if not best or count < bestCount then
				best, bestCount = lotId, count
			end
		end
	end
	return best
end

function WorkerService.Hire(player, mallId, floor, disc)
	local profile = S.DataService.GetProfile(player)
	if not profile then
		return false
	end
	local cfg = Workers[disc.Worker]
	if profile.Cash < cfg.Wage then
		S.MessageService.Toast(player, ("You need at least one wage (%s) in cash to hire a %s."):format(Format.Cash(cfg.Wage), cfg.Name), "bad")
		return false
	end
	local mallData = profile.Malls[tostring(mallId)]
	local w = { Id = HttpService:GenerateGUID(false), Type = disc.Worker, Lot = pickLot(player, mallId, disc.Worker), Tasks = 0, Discovery = disc.Id, Hired = os.time() }
	table.insert(mallData.Workers, w)
	mallData.Discovered[disc.Id] = true
	local sk = sceneKey(mallId, floor, disc.Id)
	if scenes[sk] then
		scenes[sk].Folder:Destroy()
		scenes[sk] = nil
	end
	spawnWorker(player, mallId, floor, w)
	S.MessageService.Toast(player, ("%s hired! Wage %s per minute. %s"):format(cfg.Name, Format.Cash(cfg.Wage), cfg.Benefit), "big")
	S.MessageService.Tip(player, "Hire_" .. disc.Worker, cfg.Tip)
	if not w.Lot and w.Type ~= "Manager" then
		S.MessageService.Toast(player, ("Your %s has no suitable store yet. Open one and they will start working."):format(cfg.Name), "info")
	end
	if S.ProgressService then
		S.ProgressService.Evaluate(player)
	end
	push(player)
	return true
end

local function buildCandidate(scene, disc, position, lockedText)
	local cfg = Workers[disc.Worker]
	local npc = S.NpcService.Create({ Name = "Candidate_" .. disc.Worker, Shirt = cfg.Shirt, Hat = disc.Worker == "Cook" and Color3.new(1, 1, 1) or nil, Position = position, WalkSpeed = 0 })
	npc.Parent = scene.Folder
	S.NpcService.SetBubble(npc, "👋")
	label(npc.Head, ("%s · %s/min\n%s"):format(cfg.Name, Format.Cash(cfg.Wage), cfg.Benefit), 3.4, 300).TextScaled = true
	local p = prompt(npc.PrimaryPart, lockedText or ("Hire %s (%s/min)"):format(cfg.Name, Format.Cash(cfg.Wage)), "Worker", 0.5)
	scene.Candidate = npc
	scene.HirePrompt = p
	p.Triggered:Connect(function(player)
		if player ~= scene.Player then
			S.MessageService.Toast(player, "Only the floor owner can recruit here.", "info")
			return
		end
		if scene.Locked and scene.Locked(player) then
			return
		end
		WorkerService.Hire(player, scene.MallId, scene.Floor, disc)
	end)
	return npc
end

local function buildScene(player, mallId, floor, disc)
	local sk = sceneKey(mallId, floor, disc.Id)
	if scenes[sk] then
		scenes[sk].Folder:Destroy()
	end
	local folder = Instance.new("Model")
	folder.Name = "Discovery_" .. disc.Id
	folder.Parent = S.MallService.DynamicFolder(mallId, floor)
	local scene = { Folder = folder, Player = player, MallId = mallId, Floor = floor, Disc = disc }
	scenes[sk] = scene
	local pos = S.MallService.ToWorld(mallId, floor, disc.Pos)
	if disc.Kind == "LostDelivery" then
		local courier = S.NpcService.Create({ Name = "Courier", Shirt = Color3.fromRGB(240, 170, 60), Position = pos, WalkSpeed = 0 })
		courier.Parent = folder
		S.NpcService.SetBubble(courier, ICON.Box .. "?")
		label(courier.Head, disc.Text, 3.4, 320)
		local box = AssetRegistry.Place("StockBox", CFrame.new(S.MallService.ToWorld(mallId, floor, disc.BoxPos)), folder, 25)
		local anchor = box.PrimaryPart or box:FindFirstChildWhichIsA("BasePart", true)
		label(anchor, "📦 Lost delivery", 3.5, 160)
		prompt(anchor, "Pick up lost box", "Lost delivery").Triggered:Connect(function(who)
			if who ~= player then
				S.MessageService.Toast(who, "This delivery belongs to the floor owner.", "info")
				return
			end
			if Carry.Get(who) then
				S.MessageService.Toast(who, "Your hands are full.", "bad")
				return
			end
			if near(who, anchor.Position) and Carry.Give(who, "LostBox", { Disc = disc.Id }) then
				box:Destroy()
				S.MessageService.Toast(who, "Bring the box back to the courier.", "info")
			end
		end)
		prompt(courier.PrimaryPart, "Return box", "Courier").Triggered:Connect(function(who)
			if who ~= player or scene.Candidate then
				return
			end
			local c = Carry.Get(who)
			if not c or c.Kind ~= "LostBox" or c.Data.Disc ~= disc.Id then
				S.MessageService.Toast(who, "Find the lost box on this floor first.", "info")
				return
			end
			Carry.Take(who, "LostBox")
			S.NpcService.SetBubble(courier, "🙏")
			S.MessageService.Toast(who, "Thanks! A worker who was helping the courier wants a job.", "good")
			buildCandidate(scene, disc, pos + Vector3.new(4, 0, 0))
		end)
	elseif disc.Kind == "RestorePower" then
		local gen = AssetRegistry.Place("Generator", CFrame.new(pos), folder, 0)
		local anchor = gen.PrimaryPart or gen:FindFirstChildWhichIsA("BasePart", true)
		label(anchor, disc.Text, 5, 320)
		-- darkness overlay in the staff room until power is restored
		local r = S.MallService.STAFF_ROOM
		local o = S.MallService.FloorOrigin(mallId, floor)
		local dark = Instance.new("Part")
		dark.Name = "Dark"
		dark.Size = Vector3.new(r.x1 - r.x0 - 1, 9.4, r.z1 - r.z0 - 1)
		dark.Anchored = true
		dark.CanCollide = false
		dark.CanQuery = false
		dark.Color = Color3.new(0, 0, 0)
		dark.Transparency = 0.55
		dark.CFrame = CFrame.new(o.X + (r.x0 + r.x1) / 2, o.Y + 5, o.Z + (r.z0 + r.z1) / 2)
		dark.Parent = folder
		local light = Instance.new("PointLight")
		light.Brightness = 2
		light.Range = 24
		light.Enabled = false
		light.Parent = anchor
		prompt(anchor, "Restart generator", "Generator", 2).Triggered:Connect(function(who)
			if who ~= player then
				S.MessageService.Toast(who, "Only the floor owner can restore this room.", "info")
				return
			end
			if scene.Candidate or not near(who, anchor.Position) then
				return
			end
			dark:Destroy()
			light.Enabled = true
			S.MessageService.Toast(who, "Power restored! Someone was waiting in the dark...", "good")
			buildCandidate(scene, disc, pos + Vector3.new(-5, 0, 3))
		end)
	elseif disc.Kind == "Trial" then
		local profile = S.DataService.GetProfile(player)
		local lot = profile.Malls[tostring(mallId)].Lots[disc.RequiresLot]
		if not lot then
			folder:Destroy()
			scenes[sk] = nil
			return
		end
		local storeType = lot.Store
		scene.Locked = function(who)
			local done = (profile.Stats.SelfServes[storeType] or 0)
			if done < disc.Serves then
				S.MessageService.Toast(who, ("Trial: serve %d more %s orders yourself first (%d/%d)."):format(disc.Serves - done, Stores[storeType].Name, done, disc.Serves), "info")
				return true
			end
			return false
		end
		buildCandidate(scene, disc, pos, ("Hire %s (trial: %d orders)"):format(Workers[disc.Worker].Name, disc.Serves))
		label(scene.Candidate.Head, disc.Text, 5.2, 320)
	end
end

function WorkerService.BuildFloor(player, mallId, floor)
	local profile = S.DataService.GetProfile(player)
	local mallData = profile.Malls[tostring(mallId)]
	for _, disc in ipairs(Malls[mallId].Discoveries) do
		if not mallData.Discovered[disc.Id] then
			buildScene(player, mallId, floor, disc)
		end
	end
	for _, w in ipairs(mallData.Workers) do
		spawnWorker(player, mallId, floor, w)
	end
end

function WorkerService.OnLotOpened(player, mallId, floor, lotId)
	local profile = S.DataService.GetProfile(player)
	local mallData = profile.Malls[tostring(mallId)]
	for _, disc in ipairs(Malls[mallId].Discoveries) do
		if disc.RequiresLot == lotId and not mallData.Discovered[disc.Id] then
			buildScene(player, mallId, floor, disc)
		end
	end
	for _, w in ipairs(mallData.Workers) do
		if not w.Lot and w.Type ~= "Manager" then
			w.Lot = pickLot(player, mallId, w.Type)
			if w.Lot then
				spawnWorker(player, mallId, floor, w)
			end
		end
	end
end

function WorkerService.OnStoreRebuilt(st)
	for _, w in ipairs(st.MallData.Workers) do
		if w.Lot == st.LotId then
			spawnWorker(st.Owner, st.MallId, st.Floor, w)
		end
	end
end

-- reassign a worker to another lot on the same mall
function WorkerService.Assign(player, mallId, workerId, lotId)
	local profile = S.DataService.GetProfile(player)
	local floor = S.FloorService.GetFloor(player)
	if not profile or not floor then
		return false
	end
	local mallData = profile.Malls[tostring(mallId)]
	for _, w in ipairs(mallData.Workers) do
		if w.Id == workerId and w.Type ~= "Manager" then
			local lot = mallData.Lots[lotId]
			if not lot or not table.find(Stores[lot.Store].Workers, w.Type) then
				S.MessageService.Toast(player, "That store has no station for this worker.", "bad")
				return false
			end
			w.Lot = lotId
			spawnWorker(player, mallId, floor, w)
			push(player)
			return true
		end
	end
	return false
end

function WorkerService.AssignManager(player, mallId)
	local profile = S.DataService.GetProfile(player)
	if not profile then
		return false
	end
	local mallData = profile.Malls[tostring(mallId)]
	if mallData.ManagerAssigned then
		S.MessageService.Toast(player, "A manager already runs that mall.", "info")
		return false
	end
	if profile.CurrentMall == mallId then
		S.MessageService.Toast(player, "Managers run malls you have moved on from. Travel to your newer mall first.", "info")
		return false
	end
	-- any hired manager (from any mall) that is not managing yet
	local manager
	for _, m in pairs(profile.Malls) do
		for _, w in ipairs(m.Workers) do
			if w.Type == "Manager" and not w.Managing then
				manager = w
			end
		end
	end
	if not manager then
		S.MessageService.Toast(player, "You need a free Manager. One waits in Downtown's management office.", "bad")
		return false
	end
	manager.Managing = mallId
	mallData.ManagerAssigned = true
	S.MessageService.Toast(player, ("Manager assigned to %s. It now earns a modest net income every minute while you are away."):format(Malls[mallId].Name), "big")
	S.MessageService.Tip(player, "ManagedIncome", "Managed malls earn less than active play: use the income to seed stock in your new mall.")
	if S.ProgressService then
		S.ProgressService.Evaluate(player)
	end
	push(player)
	return true
end

function WorkerService.Init(services)
	S = services
end

function WorkerService.Start()
	S.FloorService.OnFloorReleased:Connect(function(player)
		for id, rt in pairs(runtime) do
			if rt.Owner == player then
				rt.Alive = false
				S.NpcService.Destroy(rt.Npc)
				runtime[id] = nil
			end
		end
		for k, scene in pairs(scenes) do
			if scene.Player == player then
				scene.Folder:Destroy()
				scenes[k] = nil
			end
		end
	end)
end

return WorkerService
