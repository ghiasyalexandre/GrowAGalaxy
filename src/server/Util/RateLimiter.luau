--!strict
-- Per-player token bucket for remote handlers. Each limiter allows `burst`
-- calls at once and refills `perSecond` calls every second.

local Players = game:GetService("Players")

export type RateLimiter = {
	allow: (player: Player) -> boolean,
}

local RateLimiter = {}

function RateLimiter.new(burst: number, perSecond: number): RateLimiter
	local buckets: { [Player]: { tokens: number, updated: number } } = {}

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)

	local function allow(player: Player): boolean
		local now = os.clock()
		local bucket = buckets[player]
		if bucket == nil then
			bucket = { tokens = burst, updated = now }
			buckets[player] = bucket
		end
		bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.updated) * perSecond)
		bucket.updated = now
		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
		return true
	end

	return { allow = allow }
end

return RateLimiter
