--!strict
-- Developer product receipts, step by step. The server's ProcessReceipt
-- (MonetizationSystem) runs process() with real dependencies; the tests run
-- it with fakes, so every failure path is checked without Roblox.
--
-- A receipt is acknowledged ("granted") only when the reward and its
-- PurchaseId are in the player's *saved* profile. Anything else returns
-- "retry" (NotProcessedYet), and Roblox asks again later, including when the
-- player next joins. The reward and the PurchaseId live in the same profile
-- document and are written together, so a retry after a failed save grants
-- again exactly once, and a retry after a successful save grants nothing.
-- Pure module: no Roblox services.

local Config = require(script.Parent.Parent.Config)
local EconomyMath = require(script.Parent.EconomyMath)
local RewardMath = require(script.Parent.RewardMath)

type ProductDef = any

export type Outcome = "granted" | "retry"
export type ApplyResult = "granted" | "duplicate" | "invalid"

export type Deps = {
	-- The allowlisted product for a ProductId, or nil (unknown, disabled,
	-- unconfigured, or not a developer product).
	productFor: (productId: number) -> ProductDef?,
	playerFor: (userId: number) -> any?, -- nil when not in this server
	profileFor: (player: any) -> boolean, -- waits for the profile; false if unavailable
	apply: (player: any, purchaseId: string, def: ProductDef) -> ApplyResult,
	waitSaved: (player: any, purchaseId: string) -> boolean, -- true once saved
	wait: () -> (), -- yields briefly (task.wait in the game)
	log: (message: string) -> (),
}

local ReceiptFlow = {}

-- Adds a developer product's reward and its PurchaseId to profile data in one
-- step. Never applies a reward twice for the same PurchaseId. Fixed rewards:
-- no multiplier is involved.
function ReceiptFlow.applyTo(data: any, purchaseId: string, grants: any): ApplyResult
	local receipts = data.receipts
	if table.find(receipts, purchaseId) then
		return "duplicate"
	end
	if grants.stardust then
		data.stardust += math.floor(grants.stardust)
	elseif grants.productionHours then
		-- Hours of production B as it is now (at least 1/s).
		local rate = math.max(EconomyMath.production(data), 1)
		data.stardust += math.floor(rate * 3600 * grants.productionHours)
	elseif grants.boost then
		local source = grants.boost.source
		data.boosts[source] = RewardMath.extend(data.boosts[source] or 0, grants.boost.seconds)
	else
		return "invalid"
	end
	table.insert(receipts, purchaseId)
	while #receipts > Config.Products.MAX_RECEIPTS do
		table.remove(receipts, 1)
	end
	return "granted"
end

-- One receipt. `inFlight` is shared by every call on this server, so the
-- same PurchaseId is never worked on twice at once.
function ReceiptFlow.process(receipt: any, deps: Deps, inFlight: { [string]: boolean }): Outcome
	local purchaseId = tostring(receipt.PurchaseId)
	local def = deps.productFor(receipt.ProductId)
	if def == nil then
		-- Not silently discarded: logged, and left for Roblox to retry once
		-- the product is configured.
		deps.log(`receipt {purchaseId}: product {receipt.ProductId} is not in the catalog`)
		return "retry"
	end
	local player = deps.playerFor(receipt.PlayerId)
	if player == nil then
		return "retry" -- fulfilled when they're in a server
	end

	while inFlight[purchaseId] do
		deps.wait()
	end
	inFlight[purchaseId] = true
	local outcome: Outcome = "retry"
	local function work()
		if not deps.profileFor(player) then
			return
		end
		local result = deps.apply(player, purchaseId, def)
		if result == "invalid" then
			deps.log(`receipt {purchaseId}: {def.key} has no developer product reward`)
			return
		end
		if deps.waitSaved(player, purchaseId) then
			outcome = "granted"
		end
	end
	local ok, problem = pcall(work :: any)
	inFlight[purchaseId] = nil
	if not ok then
		deps.log(`receipt {purchaseId}: {problem}`)
		return "retry"
	end
	return outcome
end

return ReceiptFlow
