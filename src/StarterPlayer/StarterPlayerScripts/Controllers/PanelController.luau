--[[
	PanelController — the management panel: Business (ledgers, stock, upgrades), Stores (lease),
	Workers (hired staff, reassignment, manager), Mall (milestones, unlock, project, travel), Style.
	Everything is a request; the server validates and the panel re-renders from the next snapshot.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Format = require(ReplicatedStorage.Shared.Format)
local Constants = require(ReplicatedStorage.Shared.Constants)
local UI = require(script.Parent.UI)
local HUD = require(script.Parent.HUDController)

local Panel = {}
local player = Players.LocalPlayer
local gui, root, content, tabButtons, titleLabel
local currentTab = nil
local ICON = Constants.ICONS

local function act(name, payload)
	Remotes.Action:FireServer(name, payload or {})
end

local function card(parent, order)
	local c = UI.Frame(parent, UDim2.new(1, -8, 0, 0), nil, UI.Colors.Card)
	c.AutomaticSize = Enum.AutomaticSize.Y
	c.LayoutOrder = order or 0
	UI.Corner(c, 12)
	UI.Pad(c, 10)
	UI.List(c, 6)
	return c
end

local function row(parent, order)
	local r = UI.Frame(parent, UDim2.new(1, 0, 0, 34), nil, UI.Colors.Card)
	r.BackgroundTransparency = 1
	r.LayoutOrder = order or 0
	UI.List(r, 8, true)
	return r
end

local function stat(parent, name, value, color, order)
	local f = UI.Frame(parent, UDim2.new(0.25, -6, 0, 44), nil, UI.Colors.Card2)
	f.LayoutOrder = order or 0
	UI.Corner(f, 8)
	UI.Label(f, name, UDim2.new(1, -8, 0, 16), { Pos = UDim2.fromOffset(6, 2), TextSize = 11, Color = UI.Colors.Muted })
	UI.Label(f, value, UDim2.new(1, -8, 0, 22), { Pos = UDim2.fromOffset(6, 18), TextSize = 16, Font = Enum.Font.GothamBold, Color = color or UI.Colors.Text })
	return f
end

local function current(state)
	return state.Malls[tostring(state.CurrentMall)]
end

-- Tabs ---------------------------------------------------------------------------------------

local tabs = {}

tabs.Business = function(state)
	local mall = current(state)
	local order = 0
	local anyStore = false
	for _, lot in ipairs(mall.Lots) do
		if lot.Owned then
			anyStore = true
			order += 1
			local c = card(content, order)
			UI.Label(c, ("%s  %s"):format(lot.Icon, lot.Name), UDim2.new(1, 0, 0, 24), { Font = Enum.Font.GothamBold, TextSize = 18, Order = 1 })
			local stats = row(c, 2)
			stats.Size = UDim2.new(1, 0, 0, 44)
			stat(stats, "Revenue", Format.Cash(lot.Ledger.Revenue), UI.Colors.Good, 1)
			stat(stats, "Stock cost", Format.Cash(lot.Ledger.StockCost), UI.Colors.Warn, 2)
			stat(stats, "Wages", Format.Cash(lot.Ledger.Wages), UI.Colors.Warn, 3)
			stat(stats, "Net profit", Format.Cash(lot.Profit), lot.Profit >= 0 and UI.Colors.Good or UI.Colors.Bad, 4)
			local info = row(c, 3)
			info.Size = UDim2.new(1, 0, 0, 44)
			if lot.Capacity > 0 then
				stat(info, "Stock on shelves", ("%d / %d"):format(lot.Stock, lot.Capacity), lot.Stock == 0 and UI.Colors.Bad or UI.Colors.Text, 1)
			else
				stat(info, "Plays sold", tostring(lot.Ledger.Sales), UI.Colors.Text, 1)
			end
			stat(info, "Satisfaction", ("%d%%"):format(lot.Satisfaction), lot.Satisfaction < 40 and UI.Colors.Bad or UI.Colors.Text, 2)
			stat(info, "Unit cost → price", ("%s → %s"):format(Format.Cash(lot.UnitCost), Format.Cash(lot.UnitPrice)), UI.Colors.Text, 3)
			stat(info, "Customers served", tostring(lot.Ledger.Served), UI.Colors.Text, 4)
			if lot.HasPallet then
				local pr = row(c, 4)
				pr.Name = "OrderRow"
				UI.Button(pr, ("📦 Order box (%s)"):format(Format.Cash(lot.BoxCost)), UDim2.new(0, 190, 1, 0), UI.Colors.Accent, function()
					act("OrderStock", { MallId = mall.Id, LotId = lot.Id })
				end, { Order = 1, TextSize = 14, Name = "OrderStock_" .. lot.Id })
				UI.Label(pr, ("At delivery point: %d box(es)%s"):format(lot.PalletBoxes or 0, (lot.PalletPending or 0) > 0 and (" · %d arriving"):format(lot.PalletPending) or ""), UDim2.new(1, -200, 1, 0), { TextSize = 13, Color = UI.Colors.Muted, Order = 2 })
			end
			UI.Label(c, "Upgrades (reinvest profit)", UDim2.new(1, 0, 0, 18), { TextSize = 12, Color = UI.Colors.Muted, Order = 5 })
			for i, up in ipairs(lot.Upgrades) do
				local ur = row(c, 10 + i)
				ur.Size = UDim2.new(1, 0, 0, 40)
				if up.Owned then
					UI.Label(ur, "✅ " .. up.Name, UDim2.new(0, 170, 1, 0), { TextSize = 14, Color = UI.Colors.Good, Order = 1, Bg = UI.Colors.Card2 })
				else
					UI.Button(ur, ("%s · %s"):format(up.Name, Format.Cash(up.Cost)), UDim2.new(0, 170, 1, 0), UI.Colors.Coral, function()
						act("BuyUpgrade", { MallId = mall.Id, LotId = lot.Id, UpgradeId = up.Id })
					end, { Order = 1, TextSize = 13, Name = "Upgrade_" .. lot.Id .. "_" .. up.Id })
				end
				UI.Label(ur, up.Desc, UDim2.new(1, -180, 1, 0), { TextSize = 12, Color = UI.Colors.Muted, Order = 2 })
			end
		end
	end
	if mall.Stockroom then
		order += 1
		local c = card(content, order)
		UI.Label(c, "🚚 Logistics: loading dock → stockroom → shelves", UDim2.new(1, 0, 0, 24), { Font = Enum.Font.GothamBold, TextSize = 17, Order = 1 })
		local r1 = row(c, 2)
		r1.Size = UDim2.new(1, 0, 0, 44)
		stat(r1, "Stockroom", ("%d / %d boxes"):format(mall.Stockroom.Boxes, mall.Stockroom.Capacity), mall.Stockroom.Boxes >= mall.Stockroom.Capacity and UI.Colors.Bad or UI.Colors.Text, 1)
		stat(r1, "Per delivery", ("%d boxes"):format(mall.Logistics.DeliveryBoxes), UI.Colors.Text, 2)
		stat(r1, "Cost per box", Format.Cash(mall.Logistics.CostPerBox), UI.Colors.Warn, 3)
		local r2 = row(c, 3)
		UI.Button(r2, ("Order delivery (%s)"):format(Format.Cash(mall.Logistics.DeliveryBoxes * mall.Logistics.CostPerBox)), UDim2.new(0, 200, 1, 0), UI.Colors.Accent, function()
			act("OrderDelivery", { MallId = mall.Id })
		end, { Order = 1, TextSize = 14 })
		if mall.Stockroom.Capacity < mall.Stockroom.UpgradeCapacity then
			UI.Button(r2, ("Expand stockroom to %d (%s)"):format(mall.Stockroom.UpgradeCapacity, Format.Cash(mall.Stockroom.UpgradeCost)), UDim2.new(0, 230, 1, 0), UI.Colors.Coral, function()
				act("UpgradeStockroom", { MallId = mall.Id })
			end, { Order = 2, TextSize = 13 })
		end
	end
	if not anyStore then
		local c = card(content, 1)
		UI.Label(c, "You have no store in this mall yet. Lease one from the Stores tab or at a shuttered storefront on your floor.", UDim2.new(1, 0, 0, 40), { TextSize = 14 })
	end
	order += 1
	local tips = card(content, order)
	UI.Label(tips, "💡 Profit = revenue − stock cost − wages. Satisfied customers pay up to 25% more. Empty shelves and long waits hurt satisfaction.", UDim2.new(1, 0, 0, 44), { TextSize = 13, Color = UI.Colors.Muted })
end

tabs.Stores = function(state)
	local mall = current(state)
	for i, lot in ipairs(mall.Lots) do
		local c = card(content, i)
		UI.Label(c, ("%s  %s  ·  Lot %s"):format(lot.Icon, lot.Name, lot.Id), UDim2.new(1, 0, 0, 24), { Font = Enum.Font.GothamBold, TextSize = 17, Order = 1 })
		local desc = ({ Restock = "Carry stock boxes to shelves, serve at the counter.", Match = "Match customers' outfit symbols at the display.", Assemble = "Assemble food orders at the kiosk stations.", MatchDemo = "Match the gadget a customer wants, run a demo for a bonus.", Repair = "Keep arcade machines running with quick repair sequences." })[lot.Interaction]
		UI.Label(c, desc, UDim2.new(1, 0, 0, 20), { TextSize = 13, Color = UI.Colors.Muted, Order = 2 })
		if lot.Owned then
			UI.Label(c, "✅ Open", UDim2.new(0, 120, 0, 30), { TextSize = 14, Color = UI.Colors.Good, Order = 3, Bg = UI.Colors.Card2, Align = Enum.TextXAlignment.Center })
		else
			local r = row(c, 3)
			UI.Button(r, ("Lease for %s"):format(Format.Cash(lot.Cost)), UDim2.new(0, 170, 1, 0), UI.Colors.Coral, function()
				act("BuyLot", { MallId = mall.Id, LotId = lot.Id })
			end, { Order = 1, TextSize = 14, Name = "Lease_" .. lot.Id })
			UI.Label(r, "You must be on your own floor in this mall.", UDim2.new(1, -180, 1, 0), { TextSize = 12, Color = UI.Colors.Muted, Order = 2 })
		end
	end
end

tabs.Workers = function(state)
	local mall = current(state)
	local total = 0
	local c = card(content, 1)
	UI.Label(c, ("Staff in %s"):format(mall.Name), UDim2.new(1, 0, 0, 24), { Font = Enum.Font.GothamBold, TextSize = 17, Order = 1 })
	if #mall.Workers == 0 then
		UI.Label(c, "No workers yet. Explore your floor: a courier lost a delivery, the staff room has no power, and new shops offer trials.", UDim2.new(1, 0, 0, 40), { TextSize = 13, Color = UI.Colors.Muted, Order = 2 })
	end
	for i, w in ipairs(mall.Workers) do
		total += w.Wage
		local r = row(c, 10 + i)
		r.Size = UDim2.new(1, 0, 0, 40)
		local lotName = "—"
		for _, lot in ipairs(mall.Lots) do
			if lot.Id == w.Lot then
				lotName = lot.Name
			end
		end
		if w.Managing then
			lotName = "Managing " .. (state.Malls[tostring(w.Managing)] and state.Malls[tostring(w.Managing)].Name or "")
		end
		UI.Label(r, ("%s %s · Lv%d %s"):format(ICON.Worker, w.Name, w.Level, w.LevelName), UDim2.new(0, 220, 1, 0), { TextSize = 13, Order = 1, Bg = UI.Colors.Card2 })
		UI.Label(r, ("%s/min · %d tasks · %s%s"):format(Format.Cash(w.Wage), w.Tasks, lotName, w.Unpaid and " · ⚠ UNPAID" or ""), UDim2.new(1, -330, 1, 0), { TextSize = 12, Color = w.Unpaid and UI.Colors.Bad or UI.Colors.Muted, Order = 2 })
		if w.Type ~= "Manager" then
			-- cycle through owned lots
			local owned = {}
			for _, lot in ipairs(mall.Lots) do
				if lot.Owned then
					table.insert(owned, lot)
				end
			end
			if #owned > 1 then
				UI.Button(r, "Move ➜", UDim2.new(0, 90, 1, 0), UI.Colors.Card2, function()
					local idx = 1
					for j, lot in ipairs(owned) do
						if lot.Id == w.Lot then
							idx = j
						end
					end
					local nextLot = owned[idx % #owned + 1]
					act("AssignWorker", { MallId = mall.Id, WorkerId = w.Id, LotId = nextLot.Id })
				end, { Order = 3, TextSize = 13 })
			end
		end
	end
	UI.Label(c, ("Total wages: %s per minute"):format(Format.Cash(total)), UDim2.new(1, 0, 0, 20), { TextSize = 13, Color = UI.Colors.Warn, Order = 100 })
	-- managers for earlier malls
	for _, other in pairs(state.Malls) do
		if other.Id < state.CurrentMall and other.Unlocked then
			local mc = card(content, 2 + other.Id)
			UI.Label(mc, ("📋 %s"):format(other.Name), UDim2.new(1, 0, 0, 24), { Font = Enum.Font.GothamBold, TextSize = 16, Order = 1 })
			if other.ManagerAssigned then
				UI.Label(mc, "✅ A manager runs this mall. It earns a modest net income every minute while you are elsewhere.", UDim2.new(1, 0, 0, 36), { TextSize = 13, Color = UI.Colors.Good, Order = 2 })
			else
				UI.Label(mc, "Assign a Manager so this mall keeps earning (modestly) while you build here.", UDim2.new(1, 0, 0, 20), { TextSize = 13, Color = UI.Colors.Muted, Order = 2 })
				UI.Button(mc, "Assign manager", UDim2.new(0, 170, 0, 34), UI.Colors.Accent, function()
					act("AssignManager", { MallId = other.Id })
				end, { Order = 3, TextSize = 14 })
			end
		end
	end
end

tabs.Mall = function(state)
	local mall = current(state)
	-- project
	local pc = card(content, 1)
	local pj = mall.Project
	UI.Label(pc, ("🏗 Shared project: %s"):format(pj.Name), UDim2.new(1, 0, 0, 24), { Font = Enum.Font.GothamBold, TextSize = 17, Order = 1 })
	UI.Label(pc, pj.Desc, UDim2.new(1, 0, 0, 36), { TextSize = 13, Color = UI.Colors.Muted, Order = 2 })
	local barBg = UI.Frame(pc, UDim2.new(1, 0, 0, 14), nil, UI.Colors.Card2)
	barBg.LayoutOrder = 3
	UI.Corner(barBg, 6)
	local bar = UI.Frame(barBg, UDim2.fromScale(math.clamp(pj.Progress / pj.Cost, 0, 1), 1), nil, UI.Colors.Good)
	UI.Corner(bar, 6)
	local contribs = {}
	for name, amt in pairs(pj.Contributors) do
		table.insert(contribs, ("%s %s"):format(name, Format.Cash(amt)))
	end
	UI.Label(pc, ("%s / %s%s · you: %s%s"):format(Format.Cash(pj.Progress), Format.Cash(pj.Cost), pj.Complete and " ✅ complete" or "", Format.Cash(mall.MyContribution), #contribs > 0 and ("\nContributors: " .. table.concat(contribs, ", ")) or ""), UDim2.new(1, 0, 0, 40), { TextSize = 13, Order = 4 })
	if not pj.Complete then
		UI.Button(pc, ("Contribute %s"):format(Format.Cash(pj.Step)), UDim2.new(0, 170, 0, 34), UI.Colors.Accent, function()
			act("Contribute", { MallId = mall.Id })
		end, { Order = 5, TextSize = 14, Name = "Contribute" })
	end
	-- unlock next
	if mall.Unlock then
		local uc = card(content, 2)
		UI.Label(uc, ("🏢 Next: %s"):format(mall.Unlock.NextMall or "?"), UDim2.new(1, 0, 0, 24), { Font = Enum.Font.GothamBold, TextSize = 17, Order = 1 })
		for i, ms in ipairs(mall.Unlock.Milestones) do
			UI.Label(uc, (ms.Done and "✅ " or "⬜ ") .. ms.Text, UDim2.new(1, 0, 0, 20), { TextSize = 14, Color = ms.Done and UI.Colors.Good or UI.Colors.Text, Order = 1 + i })
		end
		if mall.Unlock.Unlocked then
			UI.Label(uc, "✅ Unlocked. Travel from the Mall Transit sign on your floor, or:", UDim2.new(1, 0, 0, 20), { TextSize = 13, Color = UI.Colors.Good, Order = 50 })
			UI.Button(uc, "Travel to " .. (mall.Unlock.NextMall or ""), UDim2.new(0, 220, 0, 34), UI.Colors.Accent, function()
				act("Travel", { MallId = mall.Id + 1 })
			end, { Order = 51, TextSize = 14 })
		else
			UI.Button(uc, ("%s · %s"):format(mall.Unlock.Text, Format.Cash(mall.Unlock.OpeningCost)), UDim2.new(0, 320, 0, 34), mall.Unlock.AllDone and UI.Colors.Coral or UI.Colors.Card2, function()
				act("UnlockMall", { MallId = mall.Id })
			end, { Order = 50, TextSize = 14, Name = "UnlockMall" })
			UI.Label(uc, "Your stores here stay yours. A manager can run them later for passive income.", UDim2.new(1, 0, 0, 20), { TextSize = 12, Color = UI.Colors.Muted, Order = 51 })
		end
	end
	-- travel back / stats
	local tc = card(content, 3)
	UI.Label(tc, "🚌 Travel", UDim2.new(1, 0, 0, 24), { Font = Enum.Font.GothamBold, TextSize = 16, Order = 1 })
	local tr = row(tc, 2)
	for _, other in pairs(state.Malls) do
		if other.Id ~= state.CurrentMall then
			UI.Button(tr, other.Name, UDim2.new(0, 180, 1, 0), UI.Colors.Card2, function()
				act("Travel", { MallId = other.Id })
			end, { Order = other.Id, TextSize = 13 })
		end
	end
	UI.Button(tr, "Back to my floor", UDim2.new(0, 150, 1, 0), UI.Colors.Card2, function()
		act("GoHome")
	end, { Order = 9, TextSize = 13 })
	local sc = card(content, 4)
	UI.Label(sc, ("📈 Lifetime: %s revenue · %d customers served · %s assist bonuses · %d baskets returned"):format(Format.Cash(state.Stats.Revenue), state.Stats.Served, Format.Cash(state.Stats.Assist), state.Stats.Baskets), UDim2.new(1, 0, 0, 36), { TextSize = 13, Color = UI.Colors.Muted })
end

tabs.Style = function(state)
	local c = card(content, 1)
	UI.Label(c, "🎨 Storefront accent colour (cosmetic)", UDim2.new(1, 0, 0, 24), { Font = Enum.Font.GothamBold, TextSize = 16, Order = 1 })
	local r = row(c, 2)
	r.Size = UDim2.new(1, 0, 0, 40)
	local colors = { Color3.fromRGB(64, 150, 150), Color3.fromRGB(240, 120, 100), Color3.fromRGB(140, 110, 200), Color3.fromRGB(250, 170, 60), Color3.fromRGB(90, 180, 90) }
	for i, col in ipairs(colors) do
		UI.Button(r, state.Accent == i and "●" or "", UDim2.new(0, 40, 1, 0), col, function()
			act("SetAccent", { Index = i })
		end, { Order = i })
	end
end

-- Panel shell -------------------------------------------------------------------------------

local function render()
	if not root or not root.Visible or not HUD.State or not currentTab then
		return
	end
	content:ClearAllChildren()
	UI.List(content, 8)
	titleLabel.Text = currentTab
	for name, btn in pairs(tabButtons) do
		btn.BackgroundColor3 = name == currentTab and UI.Colors.Accent or UI.Colors.Card2
	end
	local ok, err = pcall(tabs[currentTab], HUD.State)
	if not ok then
		warn("[Shoprise] panel render: " .. tostring(err))
	end
end

function Panel.Open(tab)
	if root.Visible and currentTab == tab then
		Panel.Close()
		return
	end
	currentTab = tab
	root.Visible = true
	render()
end

function Panel.Close()
	root.Visible = false
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "ShoprisePanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	local scale = Instance.new("UIScale")
	scale.Scale = UI.Scale()
	scale.Parent = gui
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		scale.Scale = UI.Scale()
	end)
	local mobile = UI.IsMobile()
	root = UI.Frame(gui, mobile and UDim2.new(1, -16, 1, -150) or UDim2.fromOffset(680, 520), mobile and UDim2.fromOffset(8, 70) or UDim2.new(0.5, -340, 0.5, -270), UI.Colors.Bg, "Panel")
	root.BackgroundTransparency = 0.04
	root.Visible = false
	UI.Corner(root, 16)
	local header = UI.Frame(root, UDim2.new(1, 0, 0, 44), nil, UI.Colors.Bg)
	header.BackgroundTransparency = 1
	titleLabel = UI.Label(header, "Business", UDim2.new(1, -60, 1, 0), { Pos = UDim2.fromOffset(16, 0), Font = Enum.Font.GothamBlack, TextSize = 20 })
	UI.Button(header, "X", UDim2.fromOffset(36, 32), UI.Colors.Card2, Panel.Close, { Pos = UDim2.new(1, -44, 0, 6), Name = "Close" })
	local tabBar = UI.Frame(root, UDim2.new(1, -24, 0, 36), UDim2.fromOffset(12, 46), UI.Colors.Bg)
	tabBar.BackgroundTransparency = 1
	UI.List(tabBar, 6, true)
	tabButtons = {}
	for i, name in ipairs({ "Business", "Stores", "Workers", "Mall", "Style" }) do
		tabButtons[name] = UI.Button(tabBar, name, UDim2.new(0.2, -5, 1, 0), UI.Colors.Card2, function()
			currentTab = name
			render()
		end, { Order = i, TextSize = 14 })
	end
	content = UI.Scroll(root, UDim2.new(1, -24, 1, -96), UDim2.fromOffset(12, 88))
end

function Panel.Init() end

function Panel.Start()
	build()
	HUD.OnOpenPanel:Connect(Panel.Open)
	HUD.OnState:Connect(function()
		render()
	end)
end

return Panel
