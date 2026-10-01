--[[
	ActionService — the single client -> server entry point. Every action is rate-limited, requires a
	loaded profile and is validated by the service that owns the data. Clients never send prices.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)

local ActionService = {}
local S
local limiter = RateLimiter.new(12, 4) -- burst 12, 4 per second

local handlers = {}

handlers.RequestState = function(player)
	S.ProgressService.PushNow(player)
end

handlers.BuyLot = function(player, p)
	S.StoreService.BuyLot(player, tonumber(p.MallId), tostring(p.LotId))
end

handlers.BuyUpgrade = function(player, p)
	S.StoreService.BuyUpgrade(player, tonumber(p.MallId), tostring(p.LotId), tostring(p.UpgradeId))
end

handlers.OrderStock = function(player, p)
	local floor = S.FloorService.GetFloor(player)
	local st = floor and S.StoreService.Get(tonumber(p.MallId), floor, tostring(p.LotId))
	if st then
		S.StoreService.OrderStock(player, st)
	end
end

handlers.OrderDelivery = function(player, p)
	local floor = S.FloorService.GetFloor(player)
	local lg = floor and S.StoreService.Logistics(tonumber(p.MallId), floor)
	if lg then
		S.StoreService.OrderDelivery(player, lg)
	end
end

handlers.UpgradeStockroom = function(player, p)
	S.StoreService.UpgradeStockroom(player, tonumber(p.MallId))
end

handlers.MinigameAnswer = function(player, p)
	S.StoreService.AnswerMinigame(player, tostring(p.Token), p.Answer)
end

handlers.Contribute = function(player, p)
	S.ProjectService.Contribute(player, tonumber(p.MallId))
end

handlers.AssignWorker = function(player, p)
	S.WorkerService.Assign(player, tonumber(p.MallId), tostring(p.WorkerId), tostring(p.LotId))
end

handlers.AssignManager = function(player, p)
	S.WorkerService.AssignManager(player, tonumber(p.MallId))
end

handlers.UnlockMall = function(player, p)
	S.ProgressService.UnlockNextMall(player, tonumber(p.MallId))
end

handlers.Travel = function(player, p)
	S.TransitService.Travel(player, tonumber(p.MallId))
end

handlers.SetAccent = function(player, p)
	S.ProgressService.SetAccent(player, p.Index)
end

handlers.DropCarry = function(player)
	local Carry = require(script.Parent.Carry)
	if not Carry.Drop(player) then
		S.MessageService.Toast(player, "You are not carrying anything.", "info")
	end
end

handlers.GoHome = function(player)
	S.FloorService.TeleportHome(player)
end

function ActionService.Init(services)
	S = services
end

function ActionService.Start()
	Remotes.Action.OnServerEvent:Connect(function(player, name, payload)
		if type(name) ~= "string" or not handlers[name] then
			return
		end
		if not S.DataService.GetProfile(player) then
			return
		end
		if not limiter:Allow(player.UserId .. ":" .. name) then
			return
		end
		payload = type(payload) == "table" and payload or {}
		local ok, err = pcall(handlers[name], player, payload)
		if not ok then
			warn(("[Shoprise] action %s by %s failed: %s"):format(name, player.Name, tostring(err)))
		end
	end)
end

return ActionService
