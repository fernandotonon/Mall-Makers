-- Number / currency formatting shared by server messages and client UI.
local Format = {}

local SUFFIXES = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }

function Format.Short(n)
	n = math.floor(n + 0.5)
	local neg = n < 0
	n = math.abs(n)
	for _, s in ipairs(SUFFIXES) do
		if n >= s[1] then
			local v = n / s[1]
			local str = v >= 100 and string.format("%d", v) or string.format("%.1f", v)
			str = str:gsub("%.0$", "")
			return (neg and "-" or "") .. str .. s[2]
		end
	end
	return (neg and "-" or "") .. tostring(n)
end

function Format.Cash(n)
	return "$" .. Format.Short(n)
end

function Format.Seconds(s)
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

return Format
