--[[
	CameraController — the default camera only stops at collidable parts. Decorative meshes that people
	walk past through invisible surfaces (escalators) are tagged "CameraBlocker": after the default
	camera update, if one of them sits between the character and the camera, move the camera in front of it.
]]
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local CameraController = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

local function refreshFilter()
	params.FilterDescendantsInstances = CollectionService:GetTagged("CameraBlocker")
end

function CameraController.Init() end

function CameraController.Start()
	refreshFilter()
	CollectionService:GetInstanceAddedSignal("CameraBlocker"):Connect(refreshFilter)
	CollectionService:GetInstanceRemovedSignal("CameraBlocker"):Connect(refreshFilter)
	RunService:BindToRenderStep("ShopriseCameraBlockers", Enum.RenderPriority.Camera.Value + 1, function()
		local cam = workspace.CurrentCamera
		if not cam or cam.CameraType ~= Enum.CameraType.Custom then
			return
		end
		local focus = cam.Focus.Position
		local offset = cam.CFrame.Position - focus
		if offset.Magnitude < 1 then
			return
		end
		local hit = workspace:Raycast(focus, offset, params)
		if hit then
			local pos = hit.Position - offset.Unit * 0.5
			cam.CFrame = cam.CFrame - cam.CFrame.Position + pos
		end
	end)
end

return CameraController
