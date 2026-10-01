-- Money pops, celebrations, fades and a few sounds (client-side feedback only; no game state).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Format = require(ReplicatedStorage.Shared.Format)
local UI = require(script.Parent.UI)

local Effects = {}
local player = Players.LocalPlayer
local gui, fadeFrame, fadeLabel
local sounds = {}

local function sound(name, id, volume)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Volume = volume or 0.5
	s.Parent = workspace
	sounds[name] = s
end

local function play(name)
	local s = sounds[name]
	if s then
		s:Play()
	end
end

local function moneyPop(pos, amount)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = pos + Vector3.new(0, 4, 0)
	part.Parent = workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 36)
	bb.AlwaysOnTop = true
	bb.StudsOffset = Vector3.new(0, 0, 0)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.Text = (amount > 0 and "+" or "") .. Format.Cash(amount)
	l.TextColor3 = amount > 0 and Color3.fromRGB(110, 230, 140) or Color3.fromRGB(255, 130, 110)
	l.TextStrokeTransparency = 0.4
	l.Parent = bb
	bb.Parent = part
	TweenService:Create(part, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = part.Position + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(1.1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(part, 1.2)
	if amount > 0 then
		play("Cash")
	else
		play("Spend")
	end
end

local function celebrate(small)
	play("Fanfare")
	local cam = workspace.CurrentCamera
	local emitterPart = Instance.new("Part")
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(10, 1, 10)
	emitterPart.CFrame = cam.CFrame * CFrame.new(0, 6, -10)
	emitterPart.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Rate = 0
	e.Lifetime = NumberRange.new(1.5, 2.5)
	e.Speed = NumberRange.new(12, 22)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Size = NumberSequence.new(0.6, 0.2)
	e.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 80)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(240, 120, 100)), ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 200, 220)) })
	e.Acceleration = Vector3.new(0, -20, 0)
	e.Parent = emitterPart
	e:Emit(small and 40 or 140)
	Debris:AddItem(emitterPart, 3)
end

local function fade(text)
	fadeLabel.Text = text or ""
	fadeFrame.BackgroundTransparency = 1
	fadeLabel.TextTransparency = 1
	fadeFrame.Visible = true
	TweenService:Create(fadeFrame, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(fadeLabel, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
	play("Ding")
	task.delay(0.9, function()
		TweenService:Create(fadeFrame, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(fadeLabel, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.wait(0.5)
		fadeFrame.Visible = false
	end)
end

function Effects.Init() end

function Effects.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "ShopriseEffects"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")
	fadeFrame = UI.Frame(gui, UDim2.fromScale(1, 1), nil, Color3.new(0, 0, 0))
	fadeFrame.Visible = false
	fadeLabel = UI.Label(fadeFrame, "", UDim2.new(1, 0, 0, 60), { Pos = UDim2.new(0, 0, 0.5, -30), Font = Enum.Font.GothamBlack, TextSize = 40, Align = Enum.TextXAlignment.Center })
	sound("Cash", "rbxasset://sounds/electronicpingshort.wav", 0.5)
	sound("Spend", "rbxasset://sounds/button.wav", 0.4)
	sound("Ding", "rbxasset://sounds/snap.mp3", 0.6)
	sound("Fanfare", "rbxasset://sounds/action_get_up.mp3", 0.6)
	sound("Bad", "rbxasset://sounds/uuhhh.mp3", 0.3)
	Remotes.Effect.OnClientEvent:Connect(function(data)
		if data.Kind == "Money" and data.Pos then
			moneyPop(data.Pos, data.Amount or 0)
		elseif data.Kind == "Celebrate" then
			celebrate(data.Small)
		elseif data.Kind == "Fade" then
			fade(data.Text)
		end
	end)
	Remotes.Toast.OnClientEvent:Connect(function(data)
		if data.Kind == "bad" then
			play("Bad")
		end
	end)
end

return Effects
