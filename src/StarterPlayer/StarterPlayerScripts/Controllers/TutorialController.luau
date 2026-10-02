--[[
	TutorialController — one bouncing arrow in the world that guides a new owner through the first
	store: find it, order a box, take it, restock a shelf, serve the first customer. The server
	decides the step (State.Tutorial); this only draws it and picks "go to the store" when far away.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UI = require(script.Parent.UI)
local HUD = require(script.Parent.HUDController)

local Tutorial = {}
local player = Players.LocalPlayer
local anchor, bb, arrowLabel, textLabel
local current = nil -- { Target = Vector3, Text = string }
local mobile = UI.IsMobile()

local TEXT = {
	Store = "Your store is here",
	OrderBox = mobile and "Order your first box here" or "Order your first box here (R)",
	WaitBox = "Your box is on its way…",
	TakeBox = mobile and "Take the box" or "Take the box (E)",
	Restock = mobile and "Restock this shelf" or "Restock this shelf (E)",
	Serve = mobile and "Serve customers here" or "Serve customers here (E)",
}

local function build()
	anchor = Instance.new("Part")
	anchor.Name = "TutorialArrow"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 110)
	bb.AlwaysOnTop = false -- rendered in the world (AlwaysOnTop billboards also do not show in Studio captures)
	bb.MaxDistance = 400
	bb.StudsOffset = Vector3.new(0, 0, 0)
	textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 0, 34)
	textLabel.BackgroundColor3 = UI.Colors.Coral
	textLabel.BorderSizePixel = 0
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = textLabel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = textLabel
	textLabel.Parent = bb
	arrowLabel = Instance.new("TextLabel")
	arrowLabel.Size = UDim2.new(1, 0, 0, 70)
	arrowLabel.Position = UDim2.fromOffset(0, 36)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Font = Enum.Font.GothamBlack
	arrowLabel.TextScaled = true
	arrowLabel.TextColor3 = UI.Colors.Coral
	arrowLabel.TextStrokeTransparency = 0.5
	arrowLabel.Text = "⬇"
	arrowLabel.Parent = bb
	bb.Parent = anchor
	anchor.Parent = workspace
	anchor.Transparency = 1
	bb.Enabled = false
end

local function myPosition()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

local function resolve(state)
	local t = state and state.Tutorial
	if not t or not t.Targets then
		return nil
	end
	local step = t.Step
	local targets = t.Targets
	local pos = myPosition()
	-- far from the store: point at the storefront first
	if pos and targets.Store and (pos - targets.Store).Magnitude > 28 then
		return { Target = targets.Store, Text = TEXT.Store }
	end
	local target = (step == "Restock" and targets.Shelf) or ((step == "OrderBox" or step == "WaitBox" or step == "TakeBox") and targets.Pallet) or (step == "Serve" and targets.Counter) or nil
	if not target then
		return nil
	end
	return { Target = target, Text = TEXT[step] or "" }
end

local lastState

local function refresh()
	current = resolve(lastState)
	if current then
		textLabel.Text = current.Text
		bb.Enabled = true
	else
		bb.Enabled = false
	end
end

function Tutorial.Init() end

function Tutorial.Start()
	build()
	HUD.OnState:Connect(function(state)
		lastState = state
		refresh()
	end)
	-- re-evaluate the "go to the store" distance rule as the player walks
	task.spawn(function()
		while true do
			task.wait(0.5)
			if lastState then
				refresh()
			end
		end
	end)
	RunService.RenderStepped:Connect(function()
		if current and bb.Enabled then
			local bob = math.sin(os.clock() * 4) * 0.8
			anchor.Position = current.Target + Vector3.new(0, 7 + bob, 0)
		end
	end)
end

return Tutorial
