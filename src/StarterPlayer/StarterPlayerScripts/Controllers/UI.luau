-- Small UI construction helpers shared by the client controllers (code-built GUI, no .rbxm).
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local UI = {}

UI.Colors = {
	Bg = Color3.fromRGB(32, 36, 46),
	Card = Color3.fromRGB(44, 49, 62),
	Card2 = Color3.fromRGB(54, 60, 75),
	Text = Color3.fromRGB(245, 245, 250),
	Muted = Color3.fromRGB(170, 176, 190),
	Accent = Color3.fromRGB(64, 170, 160),
	Coral = Color3.fromRGB(240, 120, 100),
	Good = Color3.fromRGB(90, 200, 120),
	Bad = Color3.fromRGB(230, 90, 80),
	Warn = Color3.fromRGB(250, 190, 70),
	Tip = Color3.fromRGB(120, 160, 240),
}

function UI.IsMobile()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function UI.Scale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local s = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.6, 1.15)
	if UI.IsMobile() then
		s = math.max(s, 0.85) * 1.1
	end
	return s
end

function UI.Corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = inst
	return c
end

function UI.Pad(inst, p)
	local u = Instance.new("UIPadding")
	u.PaddingTop = UDim.new(0, p)
	u.PaddingBottom = UDim.new(0, p)
	u.PaddingLeft = UDim.new(0, p)
	u.PaddingRight = UDim.new(0, p)
	u.Parent = inst
	return u
end

function UI.List(parent, gap, horizontal)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap or 6)
	l.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

function UI.Frame(parent, size, pos, color, name)
	local f = Instance.new("Frame")
	f.Name = name or "Frame"
	f.Size = size
	f.Position = pos or UDim2.new()
	f.BackgroundColor3 = color or UI.Colors.Card
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

function UI.Label(parent, text, size, opts)
	opts = opts or {}
	local l = Instance.new("TextLabel")
	l.Name = opts.Name or "Label"
	l.Size = size or UDim2.new(1, 0, 0, 24)
	l.Position = opts.Pos or UDim2.new()
	l.BackgroundTransparency = opts.Bg and 0 or 1
	l.BackgroundColor3 = opts.Bg or UI.Colors.Card
	l.BorderSizePixel = 0
	l.Font = opts.Font or Enum.Font.Gotham
	l.TextSize = opts.TextSize or 16
	l.TextScaled = opts.Scaled or false
	l.TextWrapped = opts.Wrap ~= false
	l.TextColor3 = opts.Color or UI.Colors.Text
	l.TextXAlignment = opts.Align or Enum.TextXAlignment.Left
	l.TextYAlignment = opts.VAlign or Enum.TextYAlignment.Center
	l.RichText = opts.Rich or false
	l.Text = text or ""
	l.LayoutOrder = opts.Order or 0
	l.AutomaticSize = opts.Auto or Enum.AutomaticSize.None
	l.Parent = parent
	if opts.Bg then
		UI.Corner(l, 8)
	end
	return l
end

function UI.Button(parent, text, size, color, onClick, opts)
	opts = opts or {}
	local b = Instance.new("TextButton")
	b.Name = opts.Name or "Button"
	b.Size = size or UDim2.new(0, 120, 0, 36)
	b.Position = opts.Pos or UDim2.new()
	b.BackgroundColor3 = color or UI.Colors.Accent
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = opts.TextSize or 16
	b.TextScaled = opts.Scaled or false
	b.TextWrapped = true
	b.TextColor3 = opts.TextColor or Color3.new(1, 1, 1)
	b.Text = text
	b.LayoutOrder = opts.Order or 0
	b.Parent = parent
	UI.Corner(b, opts.Radius or 10)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

function UI.Scroll(parent, size, pos)
	local s = Instance.new("ScrollingFrame")
	s.Size = size
	s.Position = pos or UDim2.new()
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 6
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.Parent = parent
	return s
end

function UI.Inset()
	return GuiService:GetGuiInset()
end

return UI
