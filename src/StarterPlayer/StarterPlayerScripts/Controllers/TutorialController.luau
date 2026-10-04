--[[
	TutorialController — guides a new owner with a glowing dotted path on the floor (pathfinding from
	the character to the target) plus a bouncing arrow and label over the target. The server decides
	the phase and step (State.Tutorial): first stock, first sale, first refill, first worker mission.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local UI = require(script.Parent.UI)
local HUD = require(script.Parent.HUDController)

local Tutorial = {}
local player = Players.LocalPlayer
local mobile = UI.IsMobile()
local anchor, bb, textLabel
local pathFolder
local dots = {}
local current -- { Target = Vector3, Text = string }
local lastState
local lastPathFrom, lastPathTarget, lastPathAt = nil, nil, 0
local pathPoints = {}

local DOT_SPACING = 2.2
local MAX_DOTS = 70
local COLOR = Color3.fromRGB(255, 95, 40)

local function key(k)
	return mobile and "" or (" (" .. k .. ")")
end

local TEXT = {
	Store = "Your store is here",
	OrderBox = "Order your first box here" .. key("R"),
	Reorder = "Shelves empty! Order more stock" .. key("R"),
	WaitBox = "Your box is on its way…",
	TakeBox = "Take the box" .. key("E"),
	Restock = "Restock this shelf" .. key("E"),
	Serve = "Serve your first customer" .. key("E"),
	FindBox = "A courier lost this box: pick it up" .. key("E"),
	ReturnBox = "Bring the box back to the courier" .. key("E"),
	HireWorker = "Hire your first worker!" .. key("E"),
	FreeHands = "Put down what you carry (Q), then find the lost box",
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
	bb.Size = mobile and UDim2.fromOffset(170, 80) or UDim2.fromOffset(240, 110)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 500
	textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 0, mobile and 26 or 34)
	textLabel.BackgroundColor3 = UI.Colors.Coral
	textLabel.BorderSizePixel = 0
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = textLabel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = textLabel
	textLabel.Parent = bb
	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.new(1, 0, 0, mobile and 48 or 70)
	arrow.Position = UDim2.fromOffset(0, mobile and 28 or 36)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextScaled = true
	arrow.TextColor3 = UI.Colors.Coral
	arrow.TextStrokeTransparency = 0.5
	arrow.Text = "⬇"
	arrow.Parent = bb
	bb.Enabled = false
	bb.Parent = anchor
	anchor.Parent = workspace

	pathFolder = Instance.new("Folder")
	pathFolder.Name = "TutorialPath"
	pathFolder.Parent = workspace
	for i = 1, MAX_DOTS do
		local d = Instance.new("Part")
		d.Name = "Dot"
		d.Shape = Enum.PartType.Cylinder
		d.Size = Vector3.new(0.12, 1.4, 1.4)
		d.Material = Enum.Material.SmoothPlastic
		d.Color = COLOR
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		d.Transparency = 1
		d.Parent = pathFolder
		dots[i] = d
	end
end

local function rootPos()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

local function resolve(state)
	local t = state and state.Tutorial
	if not t or not t.Targets then
		return nil
	end
	local step, targets = t.Step, t.Targets
	local pos = rootPos()
	if (t.Phase == "Learn" or t.Phase == "Refill") and pos and targets.Store and (pos - targets.Store).Magnitude > 28 then
		return { Target = targets.Store, Text = TEXT.Store }
	end
	local target
	if step == "Restock" then
		target = targets.Shelf
	elseif step == "OrderBox" or step == "Reorder" or step == "WaitBox" or step == "TakeBox" then
		target = targets.Pallet
	elseif step == "Serve" then
		target = targets.Counter
	elseif step == "FindBox" or step == "FreeHands" then
		target = targets.Box
	elseif step == "ReturnBox" then
		target = targets.Courier
	elseif step == "HireWorker" then
		target = targets.Candidate
	end
	return target and { Target = target, Text = TEXT[step] or "" } or nil
end

-- ground path from the character to the target (pathfinding; straight line when it fails)
local function computePath(from, to)
	local feet = from - Vector3.new(0, 3, 0)
	local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 3 })
	local ok = pcall(function()
		path:ComputeAsync(feet, to)
	end)
	local pts = {}
	if ok and path.Status == Enum.PathStatus.Success then
		for _, w in ipairs(path:GetWaypoints()) do
			table.insert(pts, w.Position)
		end
	else
		table.insert(pts, Vector3.new(feet.X, to.Y, feet.Z))
		table.insert(pts, to)
	end
	return pts
end

-- resample the polyline into evenly spaced dot positions, skipping the first stretch under the player
local function layDots(pts)
	local out = {}
	local carry = 1.5
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local seg = (b - a).Magnitude
		local dist = carry
		while dist < seg and #out < MAX_DOTS do
			table.insert(out, a + (b - a).Unit * dist)
			dist += DOT_SPACING
		end
		carry = dist - seg
	end
	return out
end

local function refresh()
	current = resolve(lastState)
	if not current then
		bb.Enabled = false
		pathPoints = {}
		return
	end
	textLabel.Text = current.Text
	bb.Enabled = true
	local pos = rootPos()
	if not pos then
		return
	end
	local moved = not lastPathFrom or (pos - lastPathFrom).Magnitude > 3
	local retarget = not lastPathTarget or (current.Target - lastPathTarget).Magnitude > 1
	if (moved or retarget) and os.clock() - lastPathAt > 0.4 then
		lastPathFrom, lastPathTarget, lastPathAt = pos, current.Target, os.clock()
		local target = current.Target
		task.spawn(function()
			local pts = computePath(pos, target)
			if current and current.Target == target then
				pathPoints = layDots(pts)
			end
		end)
	end
end

function Tutorial.Init() end

function Tutorial.Start()
	build()
	HUD.OnState:Connect(function(state)
		lastState = state
		refresh()
	end)
	task.spawn(function()
		while true do
			task.wait(0.3)
			if lastState then
				refresh()
			end
		end
	end)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if current and bb.Enabled then
			anchor.Position = current.Target + Vector3.new(0, 7 + math.sin(t * 4) * 0.8, 0)
		end
		local pos = rootPos()
		local n = current and #pathPoints or 0
		for i, d in ipairs(dots) do
			local p = i <= n and pathPoints[i]
			-- hide the path close to the target and right under the player
			if p and current and (p - current.Target).Magnitude > 3 and not (pos and (Vector3.new(p.X, 0, p.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < 1.5) then
				-- a pulse runs along the path toward the target
				local wave = (math.sin(t * 6 - i * 0.6) + 1) / 2
				d.Transparency = 0.25 * (1 - wave)
				d.Color = COLOR:Lerp(Color3.new(1, 1, 1), wave * 0.45)
				d.CFrame = CFrame.new(p + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
			else
				d.Transparency = 1
			end
		end
	end)
end

return Tutorial
