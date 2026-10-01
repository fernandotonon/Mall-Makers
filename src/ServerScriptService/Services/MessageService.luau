-- Toasts, tips (shown once per profile) and broadcasts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MessageService = {}
local S

function MessageService.Init(services)
	S = services
end

-- kind: "info" | "good" | "bad" | "tip" | "big"
function MessageService.Toast(player, text, kind)
	Remotes.Toast:FireClient(player, { Text = text, Kind = kind or "info" })
end

function MessageService.Broadcast(text, kind)
	for _, p in ipairs(Players:GetPlayers()) do
		MessageService.Toast(p, text, kind or "big")
	end
end

-- contextual teaching message, once per profile
function MessageService.Tip(player, tipId, text)
	local profile = S.DataService.GetProfile(player)
	if not profile then
		return
	end
	if profile.TipsSeen[tipId] then
		return
	end
	profile.TipsSeen[tipId] = true
	MessageService.Toast(player, text, "tip")
end

return MessageService
