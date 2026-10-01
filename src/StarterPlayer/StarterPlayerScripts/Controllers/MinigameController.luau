--[[
	MinigameController — short icon-based tasks the server asks the player to complete:
	  Match    : pick the icon the customer wants
	  Assemble : tap ingredients to build the order, then Serve
	  Repair   : watch a 3-icon sequence, repeat it
	Answers are sent to the server, which holds the expected value and validates distance/time.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Constants = require(ReplicatedStorage.Shared.Constants)
local UI = require(script.Parent.UI)

local Minigame = {}
local player = Players.LocalPlayer
local gui, root, promptLabel, hintLabel, optionsRow, trayLabel, timerBar, resultLabel
local active = nil -- { Token, Kind, Tray }
local ICON = Constants.ICONS

local function close()
	active = nil
	root.Visible = false
end

local function send(answer)
	if not active then
		return
	end
	Remotes.Action:FireServer("MinigameAnswer", { Token = active.Token, Answer = answer })
	-- lock input until the result arrives
	for _, b in ipairs(optionsRow:GetChildren()) do
		if b:IsA("TextButton") then
			b.Active = false
			b.AutoButtonColor = false
		end
	end
end

local function clearOptions()
	for _, c in ipairs(optionsRow:GetChildren()) do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local function optionButton(id, order, onClick)
	local b = UI.Button(optionsRow, ICON[id] or id, UDim2.fromOffset(84, 84), UI.Colors.Card2, onClick, { Order = order, TextSize = 40, Radius = 16 })
	return b
end

local function open(data)
	active = { Token = data.Token, Kind = data.Kind, Tray = {} }
	root.Visible = true
	resultLabel.Text = ""
	promptLabel.Text = data.Prompt or ""
	hintLabel.Text = data.Hint and ("Customer wants:  " .. data.Hint) or ""
	trayLabel.Visible = data.Kind == "Assemble"
	trayLabel.Text = "Tray: (empty)"
	clearOptions()
	-- timer
	timerBar.Size = UDim2.fromScale(1, 1)
	TweenService:Create(timerBar, TweenInfo.new(data.TimeLimit or 12, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()

	if data.Kind == "Match" then
		for i, id in ipairs(data.Options) do
			optionButton(id, i, function()
				send(id)
			end)
		end
	elseif data.Kind == "Assemble" then
		for i, id in ipairs(data.Options) do
			optionButton(id, i, function()
				if not active then
					return
				end
				table.insert(active.Tray, id)
				local s = ""
				for _, it in ipairs(active.Tray) do
					s ..= ICON[it]
				end
				trayLabel.Text = "Tray: " .. s
			end)
		end
		UI.Button(optionsRow, "Clear", UDim2.fromOffset(84, 84), UI.Colors.Card, function()
			if active then
				table.clear(active.Tray)
				trayLabel.Text = "Tray: (empty)"
			end
		end, { Order = 10, TextSize = 16, Radius = 16 })
		UI.Button(optionsRow, "Serve ✔", UDim2.fromOffset(110, 84), UI.Colors.Good, function()
			if active then
				send(active.Tray)
			end
		end, { Order = 11, TextSize = 18, Radius = 16 })
	elseif data.Kind == "Repair" then
		hintLabel.Text = "Watch..."
		local buttons = {}
		for i, id in ipairs(data.Options) do
			buttons[id] = optionButton(id, i, function()
				if not active or active.Showing then
					return
				end
				table.insert(active.Tray, id)
				local s = ""
				for _, it in ipairs(active.Tray) do
					s ..= ICON[it]
				end
				hintLabel.Text = "Your sequence: " .. s
				if #active.Tray >= #data.Sequence then
					send(active.Tray)
				end
			end)
		end
		active.Showing = true
		task.spawn(function()
			local token = active.Token
			for _, id in ipairs(data.Sequence) do
				if not active or active.Token ~= token then
					return
				end
				local b = buttons[id]
				if b then
					b.BackgroundColor3 = UI.Colors.Warn
					task.wait(0.55)
					b.BackgroundColor3 = UI.Colors.Card2
					task.wait(0.25)
				end
			end
			if active and active.Token == token then
				active.Showing = false
				hintLabel.Text = "Now repeat the sequence"
			end
		end)
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "MallMakersMinigame"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")
	local scale = Instance.new("UIScale")
	scale.Scale = UI.Scale()
	scale.Parent = gui
	root = UI.Frame(gui, UDim2.fromOffset(460, 250), UDim2.new(0.5, -230, 0.5, -60), UI.Colors.Bg, "Minigame")
	root.BackgroundTransparency = 0.04
	root.Visible = false
	UI.Corner(root, 18)
	UI.Pad(root, 14)
	promptLabel = UI.Label(root, "", UDim2.new(1, 0, 0, 26), { Font = Enum.Font.GothamBold, TextSize = 18, Align = Enum.TextXAlignment.Center })
	hintLabel = UI.Label(root, "", UDim2.new(1, 0, 0, 40), { Pos = UDim2.fromOffset(0, 28), TextSize = 28, Align = Enum.TextXAlignment.Center, Color = UI.Colors.Warn })
	optionsRow = UI.Frame(root, UDim2.new(1, 0, 0, 90), UDim2.fromOffset(0, 74), UI.Colors.Bg)
	optionsRow.BackgroundTransparency = 1
	local l = UI.List(optionsRow, 10, true)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	trayLabel = UI.Label(root, "", UDim2.new(1, 0, 0, 26), { Pos = UDim2.fromOffset(0, 168), TextSize = 22, Align = Enum.TextXAlignment.Center })
	local tbg = UI.Frame(root, UDim2.new(1, 0, 0, 8), UDim2.new(0, 0, 1, -10), UI.Colors.Card2)
	UI.Corner(tbg, 4)
	timerBar = UI.Frame(tbg, UDim2.fromScale(1, 1), nil, UI.Colors.Accent)
	UI.Corner(timerBar, 4)
	resultLabel = UI.Label(root, "", UDim2.new(1, 0, 0, 26), { Pos = UDim2.fromOffset(0, 196), Font = Enum.Font.GothamBlack, TextSize = 20, Align = Enum.TextXAlignment.Center })
	UI.Button(root, "✕", UDim2.fromOffset(30, 30), UI.Colors.Card2, close, { Pos = UDim2.new(1, -30, 0, -4) })
end

function Minigame.Init() end

function Minigame.Start()
	build()
	Remotes.Minigame.OnClientEvent:Connect(function(data)
		if data.Close then
			if active and active.Token == data.Token then
				if data.Result then
					resultLabel.Text = data.Result == "ok" and "✔ Correct!" or "✖ Wrong"
					resultLabel.TextColor3 = data.Result == "ok" and UI.Colors.Good or UI.Colors.Bad
					task.delay(0.8, function()
						if active and active.Token == data.Token then
							close()
						end
					end)
				else
					close()
				end
			end
			return
		end
		open(data)
	end)
end

return Minigame
