-- Client bootstrap: builds the HUD, panel, minigame UI and effects.
local controllers = script.Parent:WaitForChild("Controllers")
local ORDER = { "EffectsController", "HUDController", "PanelController", "MinigameController", "TutorialController", "CameraController" }
local loaded = {}
for _, name in ipairs(ORDER) do
	loaded[name] = require(controllers:WaitForChild(name))
end
for _, name in ipairs(ORDER) do
	local c = loaded[name]
	if c.Init then
		local ok, err = pcall(c.Init)
		if not ok then
			warn(("[Shoprise] %s.Init: %s"):format(name, tostring(err)))
		end
	end
end
for _, name in ipairs(ORDER) do
	local c = loaded[name]
	if c.Start then
		local ok, err = pcall(c.Start)
		if not ok then
			warn(("[Shoprise] %s.Start: %s"):format(name, tostring(err)))
		end
	end
end
print("[Shoprise] client ready")
