--[[
	HUDController — cash, mall/floor, current objective, bottom action bar, toasts.
	Holds the latest state snapshot for the other controllers (HUD.State, HUD.OnState).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Format = require(ReplicatedStorage.Shared.Format)
local Signal = require(ReplicatedStorage.Shared.Signal)
local UI = require(script.Parent.UI)

local HUD = {}
HUD.State = nil
HUD.OnState = Signal.new()
HUD.OnOpenPanel = Signal.new() -- (tabName)

local player = Players.LocalPlayer
local gui, cashLabel, placeLabel, objectiveLabel, toastHolder, saveLabel, dropButton, boostLabel
local shownCash = 0

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "ShopriseHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	local scale = Instance.new("UIScale")
	scale.Scale = UI.Scale()
	scale.Parent = gui
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		scale.Scale = UI.Scale()
	end)
	local mobile = UI.IsMobile()

	-- cash pill (top centre): the number everyone glances at, with mall / floor in small text under it
	local cashW, cashH = mobile and 170 or 210, mobile and 50 or 58
	local cash = UI.Frame(gui, UDim2.fromOffset(cashW, cashH), UDim2.new(0.5, -cashW / 2, 0, 6), UI.Colors.Bg, "CashCard")
	cash.BackgroundTransparency = 0.15
	UI.Corner(cash, 14)
	cashLabel = UI.Label(cash, "$0", UDim2.new(1, 0, 0, mobile and 28 or 32), { Pos = UDim2.fromOffset(0, 3), Font = Enum.Font.GothamBlack, TextSize = mobile and 24 or 28, Color = UI.Colors.Good, Align = Enum.TextXAlignment.Center })
	placeLabel = UI.Label(cash, "", UDim2.new(1, 0, 0, 16), { Pos = UDim2.fromOffset(0, mobile and 30 or 35), TextSize = mobile and 11 or 12, Color = UI.Colors.Muted, Align = Enum.TextXAlignment.Center })
	-- active boosts (Rush / Express Delivery) under the cash pill
	boostLabel = UI.Label(gui, "", UDim2.fromOffset(260, 18), { Pos = UDim2.new(0.5, -130, 0, cashH + 8), TextSize = 12, Color = UI.Colors.Good, Align = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold })
	task.spawn(function()
		while true do
			task.wait(1)
			local shop = HUD.State and HUD.State.Shop
			local parts = {}
			if shop then
				local t = workspace:GetServerTimeNow()
				local function mmss(x)
					x = math.max(0, math.floor(x))
					return ("%d:%02d"):format(x // 60, x % 60)
				end
				local rushEnd = math.max(shop.Boosts.ServerRush, shop.Boosts.Rush)
				if rushEnd > t then
					table.insert(parts, "⚡ Rush " .. mmss(rushEnd - t))
				end
				if shop.Boosts.Express > t then
					table.insert(parts, "🚚 Express " .. mmss(shop.Boosts.Express - t))
				end
			end
			boostLabel.Text = table.concat(parts, "   ")
		end
	end)

	-- objective card: flush with the top-right corner, compact
	local objW, objH = mobile and 230 or 300, mobile and 46 or 56
	local obj = UI.Frame(gui, UDim2.fromOffset(objW, objH), UDim2.new(1, -objW - 6, 0, 6), UI.Colors.Bg, "ObjectiveCard")
	obj.BackgroundTransparency = 0.15
	UI.Corner(obj, 12)
	UI.Label(obj, "OBJECTIVE", UDim2.new(1, -12, 0, 12), { Pos = UDim2.fromOffset(8, 3), Font = Enum.Font.GothamBold, TextSize = 9, Color = UI.Colors.Muted })
	objectiveLabel = UI.Label(obj, "…", UDim2.new(1, -12, 1, -16), { Pos = UDim2.fromOffset(8, 14), Font = Enum.Font.GothamBold, TextSize = mobile and 12 or 14, VAlign = Enum.TextYAlignment.Top })
	saveLabel = UI.Label(gui, "", UDim2.fromOffset(objW, 14), { Pos = UDim2.new(1, -objW - 6, 0, objH + 8), TextSize = 10, Color = UI.Colors.Warn, Align = Enum.TextXAlignment.Right })

	-- one Menu button at the bottom; it opens the panel directly and hides while the panel is open
	local bh = mobile and 50 or 44
	local menuW = mobile and 110 or 120
	local menuButton = UI.Button(gui, "📋 Menu", UDim2.fromOffset(menuW, bh), UI.Colors.Bg, function()
		HUD.OnOpenPanel:Fire("Business")
	end, { Pos = UDim2.new(0.5, -menuW / 2, 1, -bh - 10), TextSize = 16, Name = "Menu", Radius = 16 })
	menuButton.BackgroundTransparency = 0.1
	function HUD.SetPanelOpen(open)
		menuButton.Visible = not open
		-- on phones the panel is full screen: hide the cards behind it
		if mobile then
			cash.Visible = not open
			obj.Visible = not open
			saveLabel.Visible = not open
		end
	end

	-- drop button (visible while carrying something); sits left of the Menu button, clear of the touch controls
	local dropW = mobile and 110 or 130
	dropButton = UI.Button(gui, mobile and "📦 Drop" or "📦 Drop (Q)", UDim2.fromOffset(dropW, bh), UI.Colors.Coral, function()
		Remotes.Action:FireServer("DropCarry")
	end, { Pos = UDim2.new(0.5, -menuW / 2 - 10 - dropW, 1, -bh - 10), TextSize = 16, Name = "Drop", Radius = 16 })
	dropButton.Visible = false

	-- toasts
	toastHolder = UI.Frame(gui, UDim2.fromOffset(420, 200), UDim2.new(0.5, -210, 1, -bh - 10 - 210), Color3.new(), "Toasts")
	toastHolder.BackgroundTransparency = 1
	local l = UI.List(toastHolder, 6)
	l.VerticalAlignment = Enum.VerticalAlignment.Bottom
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- hint (desktop)
	if not mobile then
		UI.Label(gui, "B: Business panel   ·   E / R: interact (prompts)   ·   Q: drop (beside the pallet = put back)   ·   M: Mall tab   ·   Menu opens the panel", UDim2.fromOffset(520, 18), { Pos = UDim2.new(0.5, -260, 1, -14), TextSize = 12, Color = UI.Colors.Muted, Align = Enum.TextXAlignment.Center })
	end
end

local KIND_COLOR = { info = UI.Colors.Card2, good = UI.Colors.Good, bad = UI.Colors.Bad, tip = UI.Colors.Tip, big = UI.Colors.Coral }

function HUD.Toast(text, kind)
	kind = kind or "info"
	local f = UI.Frame(toastHolder, UDim2.new(1, 0, 0, 0), nil, UI.Colors.Bg)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundTransparency = 0.08
	UI.Corner(f, 12)
	UI.Pad(f, 10)
	local stripe = UI.Frame(f, UDim2.new(0, 5, 1, 0), UDim2.fromOffset(-10, 0), KIND_COLOR[kind] or UI.Colors.Card2)
	UI.Corner(stripe, 3)
	local l = UI.Label(f, (kind == "tip" and "💡 " or kind == "big" and "🎉 " or "") .. text, UDim2.new(1, 0, 0, 0), { TextSize = kind == "big" and 17 or 15, Font = kind == "big" and Enum.Font.GothamBold or Enum.Font.Gotham, Auto = Enum.AutomaticSize.Y })
	l.Size = UDim2.new(1, 0, 0, 0)
	local children = toastHolder:GetChildren()
	local frames = {}
	for _, c in ipairs(children) do
		if c:IsA("Frame") then
			table.insert(frames, c)
		end
	end
	if #frames > 4 then
		frames[1]:Destroy()
	end
	task.delay(kind == "tip" and 7 or kind == "big" and 6 or 4, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.4)
			f:Destroy()
		end
	end)
end

local function applyState(state)
	HUD.State = state
	local mall = state.Malls[tostring(state.CurrentMall)]
	placeLabel.Text = ("%s · Floor %s"):format(mall and mall.Name or "", tostring(state.Floor or "?"))
	objectiveLabel.Text = state.CurrentObjective or "All objectives complete. Keep growing!"
	if state.NoSave then
		saveLabel.Text = "⚠ Progress is not being saved (no DataStore access)"
	elseif state.MockSave then
		saveLabel.Text = "Studio: saves live in memory for this session only"
	elseif state.DevMode then
		saveLabel.Text = "Dev save slot"
	else
		saveLabel.Text = ""
	end
	HUD.OnState:Fire(state)
end

function HUD.Init() end

function HUD.Start()
	build()
	Remotes.State.OnClientEvent:Connect(applyState)
	Remotes.Toast.OnClientEvent:Connect(function(data)
		HUD.Toast(data.Text, data.Kind)
	end)
	-- animated cash counter
	task.spawn(function()
		while true do
			task.wait(0.03)
			local target = HUD.State and HUD.State.Cash or 0
			if shownCash ~= target then
				local diff = target - shownCash
				shownCash += math.sign(diff) * math.max(1, math.floor(math.abs(diff) * 0.2))
				if math.abs(target - shownCash) < 1 then
					shownCash = target
				end
				cashLabel.Text = Format.Cash(shownCash)
			end
		end
	end)
	-- show the drop button while the character carries something (server-set attribute)
	local function watchCharacter(character)
		local function refresh()
			dropButton.Visible = character:GetAttribute("Carrying") ~= nil
		end
		character:GetAttributeChangedSignal("Carrying"):Connect(refresh)
		refresh()
	end
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q then
			if player.Character and player.Character:GetAttribute("Carrying") then
				Remotes.Action:FireServer("DropCarry")
			end
		elseif input.KeyCode == Enum.KeyCode.B then
			HUD.OnOpenPanel:Fire("Business")
		elseif input.KeyCode == Enum.KeyCode.M then
			HUD.OnOpenPanel:Fire("Mall")
		end
	end)
	Remotes.Action:FireServer("RequestState")
end

return HUD
