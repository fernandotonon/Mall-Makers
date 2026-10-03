--[[
	ShopService — Robux passes / products (cosmetic and fun only), storefront styles, session-time
	rewards and the timed boosts they give (Express Delivery, Rush).
	Boost expiry times use workspace:GetServerTimeNow() so the client can show countdowns.
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shop = require(ReplicatedStorage.Config.Shop)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ShopService = {}
local S
local session = {} -- player -> { Start = serverTime, Claimed = { [index] = true }, Notified = { [index] = true } }
local boosts = {} -- player -> { Express = serverTime, Rush = serverTime }
local serverRush = { Until = 0, By = nil }

local function now()
	return workspace:GetServerTimeNow()
end

-- Ownership ---------------------------------------------------------------------------

function ShopService.Owns(player, passKey)
	return player:GetAttribute("Pass_" .. passKey) == true
end

local function applyNameTag(player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("VipTag")
	if old then
		old:Destroy()
	end
	if not ShopService.Owns(player, "VIP") then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "VipTag"
	bb.Size = UDim2.fromOffset(110, 26)
	bb.StudsOffset = Vector3.new(0, 2.4, 0)
	bb.MaxDistance = 60
	bb.AlwaysOnTop = true
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = Color3.fromRGB(40, 32, 10)
	l.BackgroundTransparency = 0.2
	l.TextColor3 = Color3.fromRGB(255, 205, 60)
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.Text = "⭐ VIP"
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = l
	l.Parent = bb
	bb.Parent = head
end

local function setPass(player, passKey, owned)
	player:SetAttribute("Pass_" .. passKey, owned and true or nil)
	if passKey == "VIP" then
		applyNameTag(player)
	end
	ShopService.ApplyStyleFor(player)
	S.ProgressService.Push(player)
end

local function checkPasses(player)
	for key, pass in pairs(Shop.GamePasses) do
		if pass.Id ~= 0 then
			task.spawn(function()
				local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
				if ok and owns then
					setPass(player, key, true)
				end
			end)
		end
	end
end

-- Styles ------------------------------------------------------------------------------

local function accentAllowed(player, index)
	local a = Shop.Accents[index]
	return a ~= nil and (a.Requires == nil or ShopService.Owns(player, a.Requires))
end

function ShopService.ApplyStyle(st)
	local player = st.Owner
	local profile = player and S.DataService.GetProfile(player)
	local sign = st.Folder:FindFirstChild("Sign")
	if not profile or not sign then
		return
	end
	local idx = profile.Cosmetic.Accent or 1
	if not accentAllowed(player, idx) then
		idx = 1
	end
	sign.Color = Shop.Accents[idx].Color
	local neon = profile.Cosmetic.Neon and ShopService.Owns(player, "StylePack")
	sign.Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
end

function ShopService.ApplyStyleFor(player)
	for _, st in ipairs(S.StoreService.StoresOf(player)) do
		ShopService.ApplyStyle(st)
	end
end

function ShopService.SetAccent(player, index)
	local profile = S.DataService.GetProfile(player)
	index = tonumber(index)
	if not profile or not index or not Shop.Accents[index] then
		return false
	end
	if not accentAllowed(player, index) then
		S.MessageService.Toast(player, ("That colour comes with %s (Menu ▸ Shop)."):format(Shop.GamePasses[Shop.Accents[index].Requires].Name), "info")
		return false
	end
	profile.Cosmetic.Accent = index
	ShopService.ApplyStyleFor(player)
	S.ProgressService.Push(player)
	return true
end

function ShopService.SetNeon(player, on)
	local profile = S.DataService.GetProfile(player)
	if not profile then
		return
	end
	if on and not ShopService.Owns(player, "StylePack") then
		S.MessageService.Toast(player, "The neon sign comes with the Style Pack (Menu ▸ Shop).", "info")
		return
	end
	profile.Cosmetic.Neon = on and true or false
	ShopService.ApplyStyleFor(player)
	S.ProgressService.Push(player)
end

-- Boosts ------------------------------------------------------------------------------

local function addBoost(player, kind, seconds)
	boosts[player] = boosts[player] or {}
	local b = boosts[player]
	b[kind] = math.max(b[kind] or 0, now()) + seconds
	S.ProgressService.Push(player)
end

function ShopService.ExpressActive(player)
	local b = player and boosts[player]
	return b ~= nil and (b.Express or 0) > now()
end

-- customers spawn faster for this store: server rush (bought) or the owner's own rush (reward)
function ShopService.RushActive(st)
	if serverRush.Until > now() then
		return true
	end
	local b = st.Owner and boosts[st.Owner]
	return b ~= nil and (b.Rush or 0) > now()
end

function ShopService.DeliverySeconds(player, normal)
	if ShopService.ExpressActive(player) then
		return math.min(normal, Shop.ExpressDeliverySeconds)
	end
	return normal
end

local function startServerRush(player, minutes)
	serverRush.Until = math.max(serverRush.Until, now()) + minutes * 60
	serverRush.By = player.DisplayName
	S.MessageService.Broadcast(("⚡ %s started a Mall Rush! %d minutes of extra customers for every store. Thanks, %s!"):format(player.DisplayName, minutes, player.DisplayName), "big")
	Remotes.Effect:FireAllClients({ Kind = "Celebrate" })
	for _, p in ipairs(Players:GetPlayers()) do
		S.ProgressService.Push(p)
	end
end

-- Session rewards ----------------------------------------------------------------------

local function elapsedMinutes(player)
	local s = session[player]
	return s and (now() - s.Start) / 60 or 0
end

function ShopService.Claim(player, index)
	local s = session[player]
	local r = Shop.SessionRewards[tonumber(index) or 0]
	if not s or not r or s.Claimed[index] then
		return false
	end
	if elapsedMinutes(player) < r.Minutes then
		S.MessageService.Toast(player, ("Play %d minutes in this session to claim it."):format(r.Minutes), "info")
		return false
	end
	s.Claimed[index] = true
	if r.Kind == "Cash" then
		S.EconomyService.AddCash(player, r.Amount, "SessionReward")
	elseif r.Kind == "Express" then
		addBoost(player, "Express", r.Minutes2 * 60)
	elseif r.Kind == "Rush" then
		addBoost(player, "Rush", r.Minutes2 * 60)
	end
	S.MessageService.Toast(player, ("🎁 Reward claimed: %s"):format(r.Text), "good")
	Remotes.Effect:FireClient(player, { Kind = "Celebrate", Small = true })
	S.ProgressService.Push(player)
	return true
end

-- Snapshot ------------------------------------------------------------------------------

function ShopService.State(player)
	local s = session[player]
	local b = boosts[player] or {}
	local rewards = {}
	for i, r in ipairs(Shop.SessionRewards) do
		table.insert(rewards, { Index = i, Minutes = r.Minutes, Text = r.Text, Claimed = s and s.Claimed[i] == true })
	end
	local profile = S.DataService.GetProfile(player)
	local accents = {}
	for i, a in ipairs(Shop.Accents) do
		table.insert(accents, { Index = i, Name = a.Name, Color = a.Color, Locked = not accentAllowed(player, i), Requires = a.Requires })
	end
	local passes, products = {}, {}
	for key, p in pairs(Shop.GamePasses) do
		passes[key] = { Id = p.Id, Price = p.Price, Name = p.Name, Icon = p.Icon, Desc = p.Desc, Owned = ShopService.Owns(player, key) }
	end
	for key, p in pairs(Shop.Products) do
		products[key] = { Id = p.Id, Price = p.Price, Name = p.Name, Icon = p.Icon, Desc = p.Desc }
	end
	return {
		SessionStart = s and s.Start or now(),
		Rewards = rewards,
		Boosts = { Express = b.Express or 0, Rush = b.Rush or 0, ServerRush = serverRush.Until, ServerRushBy = serverRush.By },
		Accents = accents,
		Accent = profile and profile.Cosmetic.Accent or 1,
		Neon = profile and profile.Cosmetic.Neon == true,
		Passes = passes,
		Products = products,
		Studio = RunService:IsStudio(),
	}
end

-- Studio-only: simulate a purchase so the features can be tested before the ids exist
function ShopService.TestGrant(player, key)
	if not RunService:IsStudio() then
		return
	end
	if Shop.GamePasses[key] then
		setPass(player, key, true)
		S.MessageService.Toast(player, "Studio test: granted " .. Shop.GamePasses[key].Name, "info")
	elseif key == "MallRush" then
		startServerRush(player, Shop.Products.MallRush.Minutes)
	end
end

-- Studio-only: pretend the session started earlier (tests the playtime rewards)
function ShopService.DebugShiftSession(player, minutes)
	if RunService:IsStudio() and session[player] then
		session[player].Start -= minutes * 60
		S.ProgressService.Push(player)
	end
end

function ShopService.Init(services)
	S = services
end

function ShopService.Start()
	MarketplaceService.ProcessReceipt = function(info)
		local player = Players:GetPlayerByUserId(info.PlayerId)
		local profile = player and S.DataService.GetProfile(player)
		if not profile then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		profile.Receipts = profile.Receipts or {}
		if profile.Receipts[info.PurchaseId] then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if info.ProductId == Shop.Products.MallRush.Id and Shop.Products.MallRush.Id ~= 0 then
			startServerRush(player, Shop.Products.MallRush.Minutes)
		else
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		profile.Receipts[info.PurchaseId] = os.time()
		-- keep the receipt log small: drop entries older than 30 days
		for id, t in pairs(profile.Receipts) do
			if os.time() - t > 30 * 86400 then
				profile.Receipts[id] = nil
			end
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for key, pass in pairs(Shop.GamePasses) do
			if pass.Id == passId then
				setPass(player, key, true)
				S.MessageService.Toast(player, ("%s Thanks for buying %s!"):format(pass.Icon, pass.Name), "good")
				Remotes.Effect:FireClient(player, { Kind = "Celebrate" })
			end
		end
	end)
	local function onJoin(player)
		session[player] = { Start = now(), Claimed = {}, Notified = {} }
		boosts[player] = {}
		checkPasses(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			applyNameTag(player)
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do
		onJoin(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		session[player] = nil
		boosts[player] = nil
	end)
	S.FloorService.OnFloorAssigned:Connect(function(player)
		task.defer(ShopService.ApplyStyleFor, player)
	end)
	-- tell players when a session reward becomes claimable
	task.spawn(function()
		while true do
			task.wait(10)
			for _, p in ipairs(Players:GetPlayers()) do
				local s = session[p]
				if s then
					local mins = elapsedMinutes(p)
					for i, r in ipairs(Shop.SessionRewards) do
						if mins >= r.Minutes and not s.Claimed[i] and not s.Notified[i] then
							s.Notified[i] = true
							S.MessageService.Toast(p, ("🎁 Reward ready: %s. Claim it in Menu ▸ Shop."):format(r.Text), "good")
							S.ProgressService.Push(p)
						end
					end
				end
			end
		end
	end)
end

return ShopService
