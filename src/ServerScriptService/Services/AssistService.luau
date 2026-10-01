--[[
	AssistService — pays a helper (non-owner) a separate bonus for helping in someone else's store.
	The owner's earnings are untouched. Capped per minute and per object so spam cannot farm it.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Config.Economy)
local Format = require(ReplicatedStorage.Shared.Format)

local AssistService = {}
local S
local history = {} -- helper -> { times = {t...}, keys = { key -> lastTime }, warnedAt }

function AssistService.Init(services)
	S = services
end
function AssistService.Start() end

-- returns the amount paid (0 when nothing was paid)
function AssistService.Reward(helper, owner, key, pos)
	if helper == owner or not helper or not S.DataService.GetProfile(helper) then
		return 0
	end
	local h = history[helper]
	if not h then
		h = { times = {}, keys = {}, warnedAt = 0 }
		history[helper] = h
	end
	local now = os.clock()
	if h.keys[key] and now - h.keys[key] < Economy.Assist.SameActionCooldown then
		return 0
	end
	for i = #h.times, 1, -1 do
		if now - h.times[i] > 60 then
			table.remove(h.times, i)
		end
	end
	if #h.times >= Economy.Assist.MaxRewardsPerMinute then
		if now - h.warnedAt > 30 then
			h.warnedAt = now
			S.MessageService.Toast(helper, "Assist bonus limit reached for this minute. Keep helping, bonuses resume shortly.", "info")
		end
		return 0
	end
	table.insert(h.times, now)
	h.keys[key] = now
	local amount = Economy.Assist.RewardPerAction
	S.EconomyService.AddCash(helper, amount, "Assist", pos)
	local profile = S.DataService.GetProfile(helper)
	profile.Stats.AssistEarned += amount
	S.MessageService.Toast(helper, ("Assist bonus +%s (helping %s)"):format(Format.Cash(amount), owner and owner.DisplayName or "a friend"), "good")
	S.MessageService.Tip(helper, "AssistBonus", "Helping another player's store pays you a separate bonus. Their earnings are not reduced.")
	return amount
end

return AssistService
