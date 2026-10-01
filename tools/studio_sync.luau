-- Paste into Studio (Edit mode, e.g. via the MCP execute_luau tool) while `python3 -m http.server 8765`
-- serves the project root. Pulls every file listed in build/files.txt and sets the matching
-- instance's Source, creating ModuleScripts/Scripts/LocalScripts that do not exist yet.
local HttpService = game:GetService("HttpService")
HttpService.HttpEnabled = true
local BASE = "http://127.0.0.1:8765/"
local list = HttpService:GetAsync(BASE .. "build/files.txt")
local changed, created = 0, 0
local function resolve(path)
	local rel = path:gsub("^src/", "")
	local parts = string.split(rel, "/")
	local file = table.remove(parts)
	local class = "ModuleScript"
	local name = file:gsub("%.luau$", "")
	if name:match("%.server$") then class = "Script"; name = name:gsub("%.server$", "")
	elseif name:match("%.client$") then class = "LocalScript"; name = name:gsub("%.client$", "") end
	local node = game:GetService(parts[1])
	table.remove(parts, 1)
	if node.ClassName == "ServerScriptService" then node = node:FindFirstChild("Server") or Instance.new("Folder", node); node.Name = "Server" end
	for _, seg in ipairs(parts) do
		local child = node:FindFirstChild(seg)
		if not child then child = Instance.new("Folder"); child.Name = seg; child.Parent = node end
		node = child
	end
	local inst = node:FindFirstChild(name)
	if not inst then inst = Instance.new(class); inst.Name = name; inst.Parent = node; created += 1 end
	return inst
end
for _, line in ipairs(string.split(list, "\n")) do
	if line:match("%.luau$") then
		local src = HttpService:GetAsync(BASE .. line:gsub(" ", "%%20"))
		local inst = resolve(line)
		if inst.Source ~= src then inst.Source = src; changed += 1 end
	end
end
return ("synced: %d changed, %d created"):format(changed, created)
