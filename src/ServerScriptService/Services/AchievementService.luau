--[[
	AchievementService — checks Config.Achievements against each player's profile, records earned ones
	in profile.Achievements, celebrates, and awards the matching Roblox badge when one is configured.
	Badges for achievements earned before a BadgeId was configured are awarded on the next join.
]]
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Config.Achievements)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AchievementService = {}
local S

local function readPath(profile, path)
	local v = profile
	for seg in path:gmatch("[^.]+") do
		v = type(v) == "table" and v[seg] or nil
	end
	return tonumber(v) or 0
end

local function progress(player, profile, a)
	if a.Check == "Always" then
		return 1, 1
	elseif a.Stat then
		local v = a.Stat == "Cash" and S.EconomyService.GetCash(player) or readPath(profile, a.Stat)
		return v, a.Goal
	elseif a.Check == "Workers" then
		local n = 0
		for _, m in pairs(profile.Malls) do
			n += #(m.Workers or {})
		end
		return n, a.Goal
	elseif a.Check == "Stores" then
		local n = 0
		for _, m in pairs(profile.Malls) do
			for _ in pairs(m.Lots or {}) do
				n += 1
			end
		end
		return n, a.Goal
	elseif a.Check == "Project" then
		local m = profile.Malls[tostring(a.Mall)]
		local done = m and m.ProjectComplete and (m.ProjectContribution or 0) > 0
		return done and 1 or 0, 1
	elseif a.Check == "Mall" then
		return profile.UnlockedMalls[tostring(a.Mall)] and 1 or 0, 1
	end
	return 0, 1
end

local function awardBadge(player, a)
	if not a.BadgeId or a.BadgeId == 0 then
		return
	end
	task.spawn(function()
		local okHas, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, a.BadgeId)
		if okHas and not has then
			local ok, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, a.BadgeId)
			if not ok then
				warn(("[Shoprise] badge %s (%d) not awarded: %s"):format(a.Id, a.BadgeId, tostring(err)))
			end
		end
	end)
end

function AchievementService.Check(player)
	local profile = S.DataService.GetProfile(player)
	if not profile then
		return
	end
	profile.Achievements = profile.Achievements or {}
	for _, a in ipairs(Achievements) do
		if not profile.Achievements[a.Id] then
			local v, goal = progress(player, profile, a)
			if v >= goal then
				profile.Achievements[a.Id] = os.time()
				S.MessageService.Toast(player, ("%s Achievement unlocked: %s"):format(a.Icon, a.Name), "good")
				Remotes.Effect:FireClient(player, { Kind = "Celebrate", Small = a.Check == "Always" })
				awardBadge(player, a)
				S.ProgressService.Push(player)
			end
		end
	end
end

-- for the client snapshot: every achievement with progress
function AchievementService.List(player)
	local profile = S.DataService.GetProfile(player)
	if not profile then
		return {}
	end
	local list = {}
	for _, a in ipairs(Achievements) do
		local v, goal = progress(player, profile, a)
		table.insert(list, { Id = a.Id, Name = a.Name, Icon = a.Icon, Desc = a.Desc, Done = (profile.Achievements or {})[a.Id] ~= nil, Progress = math.min(v, goal), Goal = goal, Badge = (a.BadgeId or 0) ~= 0 })
	end
	return list
end

function AchievementService.Init(services)
	S = services
end

function AchievementService.Start()
	local function onJoin(player)
		task.delay(6, function()
			if not player.Parent then
				return
			end
			local profile = S.DataService.GetProfile(player)
			if profile then
				-- badges configured after the achievement was earned
				for _, a in ipairs(Achievements) do
					if (profile.Achievements or {})[a.Id] then
						awardBadge(player, a)
					end
				end
			end
			AchievementService.Check(player)
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do
		onJoin(p)
	end
	task.spawn(function()
		while true do
			task.wait(5)
			for _, p in ipairs(Players:GetPlayers()) do
				pcall(AchievementService.Check, p)
			end
		end
	end)
end

return AchievementService
