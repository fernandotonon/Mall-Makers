--[[
	Remotes
	One RemoteEvent per name, created by the server inside ReplicatedStorage.Remotes.
	Server -> client: State (player snapshot), Toast (message/tip), Minigame (open/close a task UI),
	                  Effect (money pop, celebration), WorldState (projects / floors for everyone)
	Client -> server: Action (name, payload)  -- every client intent goes through here and is validated
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = { "State", "Toast", "Minigame", "Effect", "WorldState", "Action" }

local folder = ReplicatedStorage:WaitForChild("Remotes")
local Remotes = {}

for _, name in ipairs(NAMES) do
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		Remotes[name] = remote
	else
		Remotes[name] = folder:WaitForChild(name)
	end
end

return Remotes
