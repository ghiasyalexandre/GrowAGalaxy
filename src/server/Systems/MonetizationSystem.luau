--!strict
-- Optional Robux purchases (Config.Products). The only place that talks to
-- MarketplaceService on the server, and the game's single ProcessReceipt
-- handler: nothing else may assign MarketplaceService.ProcessReceipt.
--
-- Passes: ownership comes from Roblox (UserOwnsGamePassAsync) when the
-- profile loads, and from PromptGamePassPurchaseFinished (a server-side
-- event) for purchases made in this session. A failed check retries; until
-- one succeeds the passes Roblox last confirmed (saved in the profile) stay
-- active, and the player is told. Verified passes go to Entitlements; a ship
-- pass also adds the ship to the player's owned ships (no-op if earned).
--
-- Developer products: ProcessReceipt runs Logic/ReceiptFlow, which grants the
-- reward and records the PurchaseId together, and acknowledges the receipt
-- only once the profile has saved both. Otherwise Roblox retries later
-- (also when the player rejoins, including for purchases made elsewhere).
--
-- Studio only: DevSystem can mock a pass or a receipt through the same code
-- paths (mockPass, mockReceipt). Never available in a live server.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local Entitlements = require(script.Parent.Parent.Util.Entitlements)
local Notify = require(script.Parent.Parent.Util.Notify)
local ReceiptFlow = require(ReplicatedStorage.Shared.Logic.ReceiptFlow)
local RewardMath = require(ReplicatedStorage.Shared.Logic.RewardMath)

local P = Config.Products

type ProductDef = typeof(P.BY_KEY.MiningBoost)

local MonetizationSystem = {}

local inFlight: { [string]: boolean } = {}
local passById: { [number]: ProductDef } = {}
local productById: { [number]: ProductDef } = {}
-- Studio mocks: passes switched on for this session only.
local mockPasses: { [Player]: { [string]: boolean } } = {}

local function configured(def: ProductDef): boolean
	return P.PURCHASES_ENABLED and def.enabled and def.id > 0
end

-- Makes `owned` the player's active passes and applies their one-off effects.
local function applyPasses(player: Player, owned: { [string]: boolean }, persist: boolean)
	local merged = table.clone(owned)
	local mocks = mockPasses[player]
	if mocks then
		for key in mocks do
			merged[key] = true
		end
	end
	Entitlements.set(player, merged)
	if persist then
		DataSystem.setVerifiedPasses(player, owned)
	end
	DataSystem.showPasses(player, merged)
	local profile = DataSystem.getProfile(player)
	for key in merged do
		local def = P.BY_KEY[key]
		local ship = def and def.grants.ship
		if ship and profile and not profile.ownedShips[ship] then
			DataSystem.grantShip(player, ship)
			Notify.send(
				player,
				`{Config.Ships.BY_ID[ship].displayName} unlocked. Select it in the Shipyard.`
			)
		end
	end
end

-- Asks Roblox about every configured pass. Returns false if any check
-- failed (those keep their last confirmed state).
local function verify(player: Player): boolean
	local profile = DataSystem.getProfile(player)
	if profile == nil then
		return false
	end
	local owned = table.clone(profile.verifiedPasses)
	local allOk = true
	for key, def in P.BY_KEY do
		if def.kind ~= "GamePass" then
			continue
		end
		if not configured(def) then
			owned[key] = nil
			continue
		end
		local result: boolean? = nil
		for attempt = 1, P.OWNERSHIP_TRIES do
			local ok, value = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.id)
			end)
			if ok then
				result = value == true
				break
			end
			if attempt < P.OWNERSHIP_TRIES then
				task.wait(P.OWNERSHIP_RETRY * attempt)
			end
		end
		if result == nil then
			allOk = false
		else
			(owned :: any)[key] = if result == true then true else nil
		end
	end
	if player.Parent == Players then
		applyPasses(player, owned, true)
	end
	return allOk
end

local function watchPasses(player: Player)
	if DataSystem.waitForProfile(player) == nil then
		return
	end
	local warned = false
	while player.Parent == Players do
		if verify(player) then
			if warned then
				Notify.send(player, "Your passes are confirmed.")
			end
			return
		end
		if not warned then
			warned = true
			Notify.send(
				player,
				"Couldn't confirm your passes with Roblox right now. Your last confirmed passes stay active; checking again shortly."
			)
		end
		task.wait(P.RECHECK_SECONDS)
	end
end

local function grantNotice(player: Player, def: ProductDef)
	local grants = def.grants
	if grants.stardust then
		Notify.send(player, `+{grants.stardust} Stardust added. Thank you!`)
	elseif grants.productionHours then
		Notify.send(
			player,
			`{grants.productionHours} hours of your production added to your Stardust. Thank you!`
		)
	elseif grants.boost then
		local profile = DataSystem.getProfile(player)
		local left = if profile then profile.boosts[grants.boost.source] else 0
		Notify.send(player, `{def.displayName} active: {RewardMath.clock(left)} left. Thank you!`)
	end
end

local function deps(lookup: (number) -> ProductDef?): ReceiptFlow.Deps
	return {
		productFor = lookup,
		playerFor = function(userId: number)
			return Players:GetPlayerByUserId(userId)
		end,
		profileFor = function(player: Player)
			return DataSystem.waitForProfile(player, 30) ~= nil
		end,
		apply = function(player: Player, purchaseId: string, def: ProductDef)
			local result = DataSystem.applyPurchase(player, purchaseId, def.grants)
			if result == "granted" then
				grantNotice(player, def)
			end
			return result :: any
		end,
		waitSaved = function(player: Player, purchaseId: string)
			return DataSystem.waitForSave(player, purchaseId, P.SAVE_TIMEOUT)
		end,
		wait = function()
			task.wait(0.2)
		end,
		log = function(message: string)
			warn(`[MonetizationSystem] {message}`)
		end,
	}
end

local liveDeps = deps(function(productId: number)
	local def = productById[productId]
	return if def and configured(def) then def else nil
end)

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local outcome = ReceiptFlow.process(receipt, liveDeps, inFlight)
	return if outcome == "granted"
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Studio only: pretend Roblox sent a receipt for `key` (same pipeline, a
-- fresh PurchaseId, the product's id ignored). Returns the outcome.
function MonetizationSystem.mockReceipt(player: Player, key: string, purchaseId: string?): string
	assert(RunService:IsStudio(), "mock purchases only exist in Studio")
	local def = P.BY_KEY[key]
	if def == nil or def.kind ~= "DeveloperProduct" then
		return "unknown product"
	end
	local mockDeps = deps(function()
		return def
	end)
	local receipt = {
		PurchaseId = purchaseId or `MOCK-{key}-{os.clock()}`,
		ProductId = -1,
		PlayerId = player.UserId,
	}
	return ReceiptFlow.process(receipt, mockDeps, inFlight)
end

-- Studio only: switch a pass on or off for this session (not saved).
function MonetizationSystem.mockPass(player: Player, key: string, on: boolean): boolean
	assert(RunService:IsStudio(), "mock purchases only exist in Studio")
	local def = P.BY_KEY[key]
	if def == nil or def.kind ~= "GamePass" then
		return false
	end
	local mocks = mockPasses[player] or {}
	mocks[key] = if on then true else nil
	mockPasses[player] = mocks
	local profile = DataSystem.getProfile(player)
	applyPasses(player, if profile then profile.verifiedPasses else {}, false)
	return true
end

function MonetizationSystem.init()
	for _, def in P.BY_KEY do
		if def.id > 0 then
			if def.kind == "GamePass" then
				passById[def.id] = def
			else
				productById[def.id] = def
			end
		end
	end
end

function MonetizationSystem.start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local def = passById[passId]
		if not purchased or def == nil or not configured(def) then
			return
		end
		-- Fired by Roblox on the server, so it can be trusted; a fresh check
		-- follows to keep the saved copy right.
		local profile = DataSystem.getProfile(player)
		local owned = if profile then table.clone(profile.verifiedPasses) else {}
		owned[def.key] = true
		applyPasses(player, owned, true)
		Notify.send(player, `{def.displayName} is yours. Thank you!`)
		task.spawn(verify, player)
	end)

	DataSystem.profileLoaded:Connect(function(player)
		task.spawn(watchPasses, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		mockPasses[player] = nil
	end)
end

return MonetizationSystem
