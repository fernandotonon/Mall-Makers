-- Writes an empty ReplicatedStorage.Assets folder model so Rojo can map it before any import exists.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local folder = roblox.Instance.new("Folder")
folder.Name = "Assets"
fs.writeFile("assets/roblox/Assets.rbxm", roblox.serializeModel({ folder }))
print("wrote assets/roblox/Assets.rbxm")
