--[[
	NpcService — cheap part-built humanoid NPCs (customers, workers, couriers) driven by
	Humanoid:MoveTo on the server. One shared rig: HumanoidRootPart, Torso, Head, arms, legs.
]]
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

local NpcService = {}
local S

local SKIN = { Color3.fromRGB(250, 220, 190), Color3.fromRGB(220, 180, 140), Color3.fromRGB(160, 110, 80), Color3.fromRGB(120, 80, 60) }
local PANTS = { Color3.fromRGB(60, 80, 130), Color3.fromRGB(80, 80, 90), Color3.fromRGB(200, 190, 170) }

local function mk(parent, name, size, color, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

local function weld(a, b, offset)
	b.CFrame = a.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = a
	w.Part1 = b
	w.C0 = offset
	w.Parent = a
end

local npcFolder

local function ensureFolder()
	if not npcFolder or not npcFolder.Parent then
		npcFolder = Workspace:FindFirstChild("NPCs") or Instance.new("Folder")
		npcFolder.Name = "NPCs"
		npcFolder.Parent = Workspace
	end
	return npcFolder
end

-- opts: { Name, Shirt = Color3, Pants = Color3?, Skin = Color3?, Hat = Color3?, Scale = number?, Position = Vector3 }
function NpcService.Create(opts)
	local model = Instance.new("Model")
	model.Name = opts.Name or "NPC"
	local scale = opts.Scale or 1
	local skin = opts.Skin or SKIN[math.random(#SKIN)]
	local pants = opts.Pants or PANTS[math.random(#PANTS)]

	local root = mk(model, "HumanoidRootPart", Vector3.new(2, 2, 1) * scale, Color3.new(1, 1, 1), 1)
	root.CanCollide = true
	root.CollisionGroup = "NPC"
	root.CFrame = CFrame.new(opts.Position or Vector3.new(0, 10, 0)) * CFrame.new(0, 3 * scale, 0)
	local torso = mk(model, "Torso", Vector3.new(2, 2, 1) * scale, opts.Shirt or Color3.fromRGB(200, 200, 200))
	weld(root, torso, CFrame.new())
	local head = mk(model, "Head", Vector3.new(1.3, 1.3, 1.3) * scale, skin)
	head.Shape = Enum.PartType.Ball
	weld(torso, head, CFrame.new(0, 1.65 * scale, 0))
	local hair = mk(model, "Hair", Vector3.new(1.4, 0.5, 1.4) * scale, opts.Hat or Color3.fromRGB(70, 45, 30))
	weld(head, hair, CFrame.new(0, 0.5 * scale, 0))
	local la = mk(model, "LeftArm", Vector3.new(0.8, 2, 0.8) * scale, skin)
	weld(torso, la, CFrame.new(-1.4 * scale, 0, 0))
	local ra = mk(model, "RightArm", Vector3.new(0.8, 2, 0.8) * scale, skin)
	weld(torso, ra, CFrame.new(1.4 * scale, 0, 0))
	local ll = mk(model, "LeftLeg", Vector3.new(0.9, 2, 0.9) * scale, pants)
	weld(torso, ll, CFrame.new(-0.5 * scale, -2 * scale, 0))
	local rl = mk(model, "RightLeg", Vector3.new(0.9, 2, 0.9) * scale, pants)
	weld(torso, rl, CFrame.new(0.5 * scale, -2 * scale, 0))
	-- face
	local eye1 = mk(model, "Eye1", Vector3.new(0.18, 0.28, 0.1) * scale, Color3.fromRGB(30, 30, 30))
	weld(head, eye1, CFrame.new(-0.25 * scale, 0.1 * scale, -0.62 * scale))
	local eye2 = mk(model, "Eye2", Vector3.new(0.18, 0.28, 0.1) * scale, Color3.fromRGB(30, 30, 30))
	weld(head, eye2, CFrame.new(0.25 * scale, 0.1 * scale, -0.62 * scale))

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 2 * scale
	humanoid.WalkSpeed = opts.WalkSpeed or 11
	humanoid.AutoRotate = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	model.PrimaryPart = root

	-- thought bubble
	local bb = Instance.new("BillboardGui")
	bb.Name = "Bubble"
	bb.Size = UDim2.fromOffset(120, 44)
	bb.StudsOffset = Vector3.new(0, 2.2 * scale, 0)
	bb.AlwaysOnTop = true
	bb.Enabled = false
	bb.MaxDistance = 80
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(40, 40, 50)
	label.Text = ""
	label.Parent = frame
	frame.Parent = bb
	bb.Parent = head

	model.Parent = ensureFolder()
	root:SetNetworkOwner(nil)
	return model
end

function NpcService.SetBubble(npc, text, color)
	local head = npc and npc:FindFirstChild("Head")
	local bb = head and head:FindFirstChild("Bubble")
	if not bb then
		return
	end
	if text and text ~= "" then
		bb.Enabled = true
		bb.Frame.Text.Text = text
		bb.Frame.Text.TextColor3 = color or Color3.fromRGB(40, 40, 50)
	else
		bb.Enabled = false
	end
end

function NpcService.Teleport(npc, position, lookAt)
	local root = npc and npc.PrimaryPart
	if not root then
		return
	end
	local hum = npc:FindFirstChildOfClass("Humanoid")
	local y = position.Y + (hum and hum.HipHeight or 2) + root.Size.Y / 2
	local p = Vector3.new(position.X, y, position.Z)
	if lookAt then
		root.CFrame = CFrame.lookAt(p, Vector3.new(lookAt.X, y, lookAt.Z))
	else
		root.CFrame = CFrame.new(p)
	end
end

function NpcService.Face(npc, target)
	local root = npc and npc.PrimaryPart
	if not root then
		return
	end
	local p = root.Position
	root.CFrame = CFrame.lookAt(p, Vector3.new(target.X, p.Y, target.Z))
end

-- Walks to position (ground point). Yields. Returns true on arrival, false on timeout / destroyed.
function NpcService.MoveTo(npc, position, timeout)
	local hum = npc and npc:FindFirstChildOfClass("Humanoid")
	local root = npc and npc.PrimaryPart
	if not hum or not root then
		return false
	end
	timeout = timeout or 12
	local deadline = os.clock() + timeout
	while npc.Parent and os.clock() < deadline do
		local flat = Vector3.new(position.X, root.Position.Y, position.Z)
		if (root.Position - flat).Magnitude < 1.5 then
			return true
		end
		hum:MoveTo(Vector3.new(position.X, root.Position.Y - hum.HipHeight, position.Z))
		local arrived = false
		local conn
		conn = hum.MoveToFinished:Connect(function(reached)
			arrived = reached
		end)
		local t0 = os.clock()
		while npc.Parent and os.clock() - t0 < 7.5 do
			task.wait(0.15)
			local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
			if d < 1.5 or arrived then
				break
			end
		end
		conn:Disconnect()
	end
	if not npc.Parent then
		return false
	end
	local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
	if d >= 3 then
		-- stuck: snap, so gameplay never blocks on physics
		NpcService.Teleport(npc, position)
	end
	return true
end

function NpcService.WalkPath(npc, points, timeoutEach)
	for _, p in ipairs(points) do
		if not npc.Parent then
			return false
		end
		NpcService.MoveTo(npc, p, timeoutEach)
	end
	return npc.Parent ~= nil
end

function NpcService.Destroy(npc)
	if npc then
		npc:Destroy()
	end
end

function NpcService.Init(services)
	S = services
	pcall(function()
		PhysicsService:RegisterCollisionGroup("NPC")
		PhysicsService:RegisterCollisionGroup("Players")
		PhysicsService:CollisionGroupSetCollidable("NPC", "NPC", false)
		PhysicsService:CollisionGroupSetCollidable("NPC", "Players", false)
		PhysicsService:CollisionGroupSetCollidable("NPC", "Default", true)
	end)
end

function NpcService.Start() end

return NpcService
