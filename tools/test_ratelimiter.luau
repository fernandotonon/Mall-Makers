-- Unit test (Lune): RateLimiter and Format behave as documented.
local RateLimiter = require("../src/ReplicatedStorage/Shared/RateLimiter")
local Format = require("../src/ReplicatedStorage/Shared/Format")
local rl = RateLimiter.new(12, 4)
local allowed = 0
for _ = 1, 40 do
	if rl:Allow("u1:OrderStock") then allowed += 1 end
end
assert(allowed == 12, "burst should allow exactly 12, got " .. allowed)
assert(rl:Allow("u2:OrderStock"), "other key independent")
assert(Format.Cash(1234) == "$1.2K" and Format.Cash(950) == "$950" and Format.Cash(2500000) == "$2.5M" and Format.Cash(120000) == "$120K", "format")
print("ratelimiter burst=" .. allowed .. " ok; format ok")
