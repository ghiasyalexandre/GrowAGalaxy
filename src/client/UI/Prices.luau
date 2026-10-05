--!strict
-- Current Robux prices of Config.Products offers on this client, asked from
-- Roblox (MarketplaceService:GetProductInfoAsync) once per session, so a
-- shown price always matches the purchase prompt. get() starts loading and
-- returns nil until the price arrives (or if it can't be loaded, or the
-- offer isn't configured or isn't for sale); `changed` fires when one loads.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local P = Config.Products

local Prices = {}

Prices.changed = Signal.new() :: Signal.Signal<string>

local loaded: { [string]: number } = {}
-- Offers being asked about, or known to have no price this session.
local pending: { [string]: boolean } = {}

-- The offer's price in Robux, or nil (loading, unavailable or not set up).
function Prices.get(key: string): number?
	local cached = loaded[key]
	if cached ~= nil or pending[key] then
		return cached
	end
	local def = P.BY_KEY[key]
	pending[key] = true -- one request at a time
	if def == nil or not (P.PURCHASES_ENABLED and def.enabled and def.id > 0) then
		return nil
	end
	task.spawn(function()
		local infoType = if def.kind == "GamePass"
			then Enum.InfoType.GamePass
			else Enum.InfoType.Product
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(def.id, infoType)
		end)
		local robux = if ok and type(info) == "table" then info.PriceInRobux else nil
		local forSale = not (ok and type(info) == "table" and info.IsForSale == false)
		if type(robux) == "number" and forSale then
			loaded[key] = robux
			Prices.changed:Fire(key)
		else
			-- Try again next time someone asks.
			pending[key] = nil
		end
	end)
	return nil
end

return Prices
