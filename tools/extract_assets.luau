-- lune run tools/extract_assets.luau [build/Shoprise.rbxl]
-- Pulls ReplicatedStorage.Assets out of a saved place and writes assets/roblox/Assets.rbxm for Rojo.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local path = process.args[1] or "build/Shoprise.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))
local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
assert(assets, "no ReplicatedStorage.Assets in " .. path)
fs.writeFile("assets/roblox/Assets.rbxm", roblox.serializeModel({ assets }))
local n = 0
for _, c in ipairs(assets:GetChildren()) do n += 1 end
print(("wrote assets/roblox/Assets.rbxm with %d assets"):format(n))
