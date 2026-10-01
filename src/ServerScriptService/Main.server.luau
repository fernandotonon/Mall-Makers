--[[
	Main (server bootstrap)
	Requires every service, runs Init(services) on all of them, then Start().
	Order matters only for Init dependencies (MallService builds geometry the others place things on).
]]
local ORDER = {
	"DataService",
	"MessageService",
	"EconomyService",
	"MallService",
	"NpcService",
	"FloorService",
	"StoreService",
	"CustomerService",
	"WorkerService",
	"AssistService",
	"ProjectService",
	"TransitService",
	"RecoveryService",
	"ProgressService",
	"ActionService",
}

local servicesFolder = script.Parent:WaitForChild("Services")
local Services = {}

for _, name in ipairs(ORDER) do
	Services[name] = require(servicesFolder:WaitForChild(name))
end

for _, name in ipairs(ORDER) do
	local svc = Services[name]
	if svc.Init then
		local ok, err = pcall(svc.Init, Services)
		if not ok then
			warn(("[MallMakers] %s.Init failed: %s"):format(name, tostring(err)))
		end
	end
end

for _, name in ipairs(ORDER) do
	local svc = Services[name]
	if svc.Start then
		local ok, err = pcall(svc.Start)
		if not ok then
			warn(("[MallMakers] %s.Start failed: %s"):format(name, tostring(err)))
		end
	end
end

-- Studio-only debug hook so tests (and the MCP agent) can call service functions:
--   game.ServerStorage.MMDebug:Invoke("EconomyService", "AddCash", player, 500, "debug")
if game:GetService("RunService"):IsStudio() then
	local ServerStorage = game:GetService("ServerStorage")
	local bf = ServerStorage:FindFirstChild("MMDebug") or Instance.new("BindableFunction")
	bf.Name = "MMDebug"
	bf.Parent = ServerStorage
	bf.OnInvoke = function(serviceName, fnName, ...)
		if serviceName == "Run" then
			-- run a test ModuleScript inside the live server context (tables returned through a
			-- BindableFunction are copies, so tests pass code in instead). The module must return
			-- function(Services, ...) -> string.
			return require(fnName)(Services, ...)
		end
		local svc = Services[serviceName]
		assert(svc, "no service " .. tostring(serviceName))
		local fn = svc[fnName]
		assert(fn, "no function " .. tostring(fnName) .. " on " .. serviceName)
		return fn(...)
	end
end

print("[MallMakers] server booted")
