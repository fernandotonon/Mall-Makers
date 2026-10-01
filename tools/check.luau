-- Syntax-checks every .luau under src/ with Lune's luau.compile (no Roblox globals needed).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local bad = 0
local count = 0
local function walk(dir)
	for _, name in ipairs(fs.readDir(dir)) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then
			walk(p)
		elseif name:match("%.luau$") then
			count += 1
			local src = fs.readFile(p)
			local ok, err = pcall(luau.compile, src)
			if not ok then
				bad += 1
				print("SYNTAX ERROR in " .. p .. ":\n  " .. tostring(err))
			end
		end
	end
end
walk("src")
print(("checked %d files, %d with errors"):format(count, bad))
process.exit(bad == 0 and 0 or 1)
