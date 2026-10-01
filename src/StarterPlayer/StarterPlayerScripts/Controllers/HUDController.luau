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
local gui, cashLabel, placeLabel, objectiveLabel, toastHolder, saveLabel
local shownCash = 0

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "MallMakersHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	local scale = Instance.new("UIScale")
	scale.Scale = UI.Scale()
	scale.Parent = gui
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		scale.Scale = UI.Scale()
	end)

	-- cash card (top-left)
	local cash = UI.Frame(gui, UDim2.fromOffset(230, 74), UDim2.fromOffset(12, 12), UI.Colors.Bg, "CashCard")
	cash.BackgroundTransparency = 0.1
	UI.Corner(cash, 14)
	UI.Pad(cash, 10)
	cashLabel = UI.Label(cash, "$0", UDim2.new(1, 0, 0, 34), { Font = Enum.Font.GothamBlack, TextSize = 30, Color = UI.Colors.Good })
	placeLabel = UI.Label(cash, "", UDim2.new(1, 0, 0, 20), { Pos = UDim2.fromOffset(0, 36), TextSize = 14, Color = UI.Colors.Muted })

	-- objective card (top-right)
	local obj = UI.Frame(gui, UDim2.fromOffset(300, 64), UDim2.new(1, -312, 0, 12), UI.Colors.Bg, "ObjectiveCard")
	obj.BackgroundTransparency = 0.1
	UI.Corner(obj, 14)
	UI.Pad(obj, 10)
	UI.Label(obj, "OBJECTIVE", UDim2.new(1, 0, 0, 14), { Font = Enum.Font.GothamBold, TextSize = 11, Color = UI.Colors.Muted })
	objectiveLabel = UI.Label(obj, "…", UDim2.new(1, 0, 0, 34), { Pos = UDim2.fromOffset(0, 14), Font = Enum.Font.GothamBold, TextSize = 15, VAlign = Enum.TextYAlignment.Top })
	saveLabel = UI.Label(gui, "", UDim2.fromOffset(300, 18), { Pos = UDim2.new(1, -312, 0, 78), TextSize = 12, Color = UI.Colors.Warn, Align = Enum.TextXAlignment.Right })

	-- bottom bar
	local mobile = UI.IsMobile()
	local bh = mobile and 58 or 44
	local bar = UI.Frame(gui, UDim2.fromOffset(mobile and 440 or 470, bh + 16), UDim2.new(0.5, mobile and -220 or -235, 1, -(bh + 16) - 12), UI.Colors.Bg, "Bar")
	bar.BackgroundTransparency = 0.1
	UI.Corner(bar, 16)
	UI.Pad(bar, 8)
	UI.List(bar, 8, true)
	local tabs = { { "Business", "💼" }, { "Stores", "🏬" }, { "Workers", "🧑‍💼" }, { "Mall", "🏢" } }
	for i, t in ipairs(tabs) do
		UI.Button(bar, (mobile and "" or t[2] .. " ") .. t[1], UDim2.new(0.25, -6, 1, 0), UI.Colors.Card2, function()
			HUD.OnOpenPanel:Fire(t[1])
		end, { Order = i, TextSize = mobile and 15 or 15 })
	end

	-- toasts
	toastHolder = UI.Frame(gui, UDim2.fromOffset(420, 200), UDim2.new(0.5, -210, 1, -(bh + 16) - 12 - 210), Color3.new(), "Toasts")
	toastHolder.BackgroundTransparency = 1
	local l = UI.List(toastHolder, 6)
	l.VerticalAlignment = Enum.VerticalAlignment.Bottom
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- hint (desktop)
	if not mobile then
		UI.Label(gui, "B: Business panel   ·   E / R: interact (prompts)   ·   M: Mall tab", UDim2.fromOffset(520, 18), { Pos = UDim2.new(0.5, -260, 1, -14), TextSize = 12, Color = UI.Colors.Muted, Align = Enum.TextXAlignment.Center })
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
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.B then
			HUD.OnOpenPanel:Fire("Business")
		elseif input.KeyCode == Enum.KeyCode.M then
			HUD.OnOpenPanel:Fire("Mall")
		end
	end)
	Remotes.Action:FireServer("RequestState")
end

return HUD
