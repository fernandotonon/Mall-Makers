-- Token bucket per key (player + action). Server-side protection against spammed requests.
local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(maxTokens, refillPerSecond)
	return setmetatable({ max = maxTokens, refill = refillPerSecond, buckets = {} }, RateLimiter)
end

function RateLimiter:Allow(key, cost)
	cost = cost or 1
	local now = os.clock()
	local b = self.buckets[key]
	if not b then
		b = { tokens = self.max, t = now }
		self.buckets[key] = b
	end
	b.tokens = math.min(self.max, b.tokens + (now - b.t) * self.refill)
	b.t = now
	if b.tokens >= cost then
		b.tokens -= cost
		return true
	end
	return false
end

function RateLimiter:Clear(prefix)
	for k in pairs(self.buckets) do
		if type(k) == "string" and k:sub(1, #prefix) == prefix then
			self.buckets[k] = nil
		end
	end
end

return RateLimiter
