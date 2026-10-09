--!strict
-- Hangar upgrades on each player's station deck (Config.Hangar). For every
-- upgrade the station's "Hangar" model holds either its finished building
-- (built) or a red ground circle (on offer: its requirements are built), or
-- nothing yet. Stepping on a circle, or its Build prompt, buys it through
-- DataSystem; only the station's owner can.
--
-- Buildings are tagged "HangarStructure" (one bought just now also has
-- BuiltAt, server time, so clients animate it rising and celebrate); pads
-- are tagged "HangarPad" (clients make them pulse). A building with a `site`
-- stands there instead of on its pad.
--
-- The Showcase Dock holds the player's chosen ships (profile.showcase)
-- turning on its cradles; refreshShowcase rebuilds them when the choice
-- or a ship's colours change.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local HangarBuilder = require(script.Parent.Parent.World.HangarBuilder)
local HangarMath = require(ReplicatedStorage.Shared.Logic.HangarMath)
local RegionSystem = require(script.Parent.RegionSystem)
local ShipBuilder = require(script.Parent.Parent.World.ShipBuilder)
local Notify = require(script.Parent.Parent.Util.Notify)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local StationSystem = require(script.Parent.StationSystem)
local Types = require(ReplicatedStorage.Shared.Types)

local H = Config.Hangar
local STRUCTURE_TAG = "HangarStructure"
local PAD_TAG = "HangarPad"

local HangarSystem = {}

local limit = RateLimiter.new(4, 1)
local lastTouch: { [Player]: number } = {}

local refresh: (player: Player, justBuilt: string?) -> ()

local SHOWCASE_ID = "ShowcaseDock"
local DISPLAY_SPIN = 0.25 -- radians per second
-- Each showcased ship is shrunk so it turns inside its cradle's glow pad.
local PAD_DIAMETER = 12 -- studs (the white glow ring is 12.8 across)
local PAD_CLEARANCE = 1 -- studs between the pad and the ship's underside

-- A ship for show: the real ship model in its colours, with everything
-- that makes it flyable or boardable removed (and its engine glow and laser
-- emitter: a parked ship shows no boosters), anchored, turning slowly.
local function display(shipId: string, look: Types.ShipLook, at: CFrame, accent: string): Model
	local model = ShipBuilder.build(shipId, at, accent, look)
	for _, item in model:GetDescendants() do
		if
			item:IsA("ProximityPrompt")
			or item:IsA("Constraint")
			or item:IsA("Seat")
			or item:IsA("ParticleEmitter")
			or item:IsA("Trail")
			or item:IsA("Beam")
			or (item:IsA("BasePart") and (item.Name == "EngineGlow" or item.Name == "BeamEmitter"))
		then
			item:Destroy()
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		elseif part:IsA("JointInstance") or part:IsA("WeldConstraint") then
			part:Destroy()
		end
	end
	model.Name = `Display_{shipId}`
	-- Sent to clients whole, so it never turns with half its parts missing.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("SpinSpeed", DISPLAY_SPIN)
	CollectionService:AddTag(model, "GaG_Spin")
	local def = Config.Ships.BY_ID[shipId]
	local hull = model.PrimaryPart
	if def and hull then
		local tag = Instance.new("BillboardGui")
		tag.Name = "ShipName"
		tag.Size = UDim2.fromOffset(200, 30)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
		tag.MaxDistance = 250
		tag.LightInfluence = 0
		tag.Adornee = hull
		tag.Parent = hull
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromHex("#FFD36B")
		label.TextStrokeTransparency = 0.3
		label.Text = def.displayName
		label.Parent = tag
	end
	return model
end

-- Shrinks a display ship so it turns inside its cradle's glow pad (its
-- widest turning circle, the box's diagonal, fits PAD_DIAMETER) and sets it
-- just above the pad, centred.
local function fitOnPad(ship: Model, cradle: BasePart)
	local _, size = ship:GetBoundingBox()
	local reach = math.sqrt(size.X * size.X + size.Z * size.Z)
	if reach > PAD_DIAMETER then
		ship:ScaleTo(ship:GetScale() * PAD_DIAMETER / reach)
	end
	local box, scaled = ship:GetBoundingBox()
	local top = cradle.Position.Y + cradle.Size.X / 2 -- the cradle stands on its X axis
	local goal =
		Vector3.new(cradle.Position.X, top + PAD_CLEARANCE + scaled.Y / 2, cradle.Position.Z)
	ship:PivotTo(ship:GetPivot() + (goal - box.Position))
end

-- Rebuilds the ships on the player's Showcase Dock, if it's built.
function HangarSystem.refreshShowcase(player: Player)
	local station = StationSystem.getStation(player)
	local profile = DataSystem.getProfile(player)
	local folder = station and station.model:FindFirstChild("Hangar")
	local dock = folder and folder:FindFirstChild(SHOWCASE_ID)
	if profile == nil or dock == nil or dock:GetAttribute("State") ~= "built" then
		return
	end
	for _, child in dock:GetChildren() do
		if child:IsA("Model") and string.sub(child.Name, 1, 8) == "Display_" then
			child:Destroy()
		end
	end
	local region = RegionSystem.getRegion(player)
	local accent = if region then region.color else Config.World.COLORS.accent
	for index, shipId in profile.showcase do
		local cradle = dock:FindFirstChild(`Cradle{index}`)
		local loadout = profile.loadouts[shipId]
		if cradle and cradle:IsA("BasePart") and Config.Ships.BY_ID[shipId] then
			-- Nose towards the deck, hovering over the cradle.
			local at = CFrame.new(cradle.Position + Vector3.new(0, 6, 0))
				* (cradle.CFrame - cradle.Position)
				* CFrame.Angles(0, 0, -math.pi / 2)
				* CFrame.Angles(0, math.pi / 2, 0)
			local look = {
				laserColor = loadout and loadout.laserColor,
				boostColor = loadout and loadout.boostColor,
			}
			local ship = display(shipId, look, at, accent)
			fitOnPad(ship, cradle)
			ship.Parent = dock
		end
	end
end

local function buy(player: Player, upgradeId: string, fromTouch: boolean)
	local profile = DataSystem.getProfile(player)
	if profile == nil or not limit.allow(player) then
		return
	end
	local cost, reason = HangarMath.canBuy(
		upgradeId,
		profile.hangar,
		profile.stardust,
		DataSystem.rewardRate(player)
	)
	if cost == nil then
		-- Standing on a pad you can't afford shouldn't spam messages.
		local now = os.clock()
		if not fromTouch or now - (lastTouch[player] or 0) >= H.TOUCH_COOLDOWN * 2 then
			lastTouch[player] = now
			Notify.send(player, reason or "You can't build that yet.")
		end
		return
	end
	-- Income up to now at the old rate (the Refinery changes it).
	DataSystem.settleIncome(player)
	if not DataSystem.spendStardust(player, cost, "hangar_buy") then
		return
	end
	DataSystem.grantHangar(player, upgradeId)
	DataSystem.addStat(player, "hangarUpgrades", 1)
	local def = H.BY_ID[upgradeId]
	Notify.send(
		player,
		if def.stats
			then `{def.displayName} built: {def.effect}. Ships get it from their next launch.`
			else `{def.displayName} built: {def.effect}.`
	)
	refresh(player, upgradeId)
end

local function ownerOf(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	return if character then Players:GetPlayerFromCharacter(character) else nil
end

local function hookPad(player: Player, pad: Model, upgradeId: string)
	local circle = pad:FindFirstChild("Circle") :: BasePart?
	if circle == nil then
		return
	end
	circle.Touched:Connect(function(hit)
		if ownerOf(hit) ~= player then
			return
		end
		local now = os.clock()
		if now - (lastTouch[player] or 0) < H.TOUCH_COOLDOWN then
			return
		end
		lastTouch[player] = now
		buy(player, upgradeId, true)
	end)
	local prompt = circle:FindFirstChild("BuildPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Triggered:Connect(function(who)
			if who == player then
				buy(player, upgradeId, false)
			else
				Notify.send(who, "Only this hangar's owner can build here.")
			end
		end)
	end
end

-- Brings the station's Hangar model in line with the player's upgrades.
refresh = function(player: Player, justBuilt: string?)
	local station = StationSystem.getStation(player)
	local profile = DataSystem.getProfile(player)
	if station == nil or profile == nil then
		return
	end
	local folder = station.model:FindFirstChild("Hangar")
	if folder == nil then
		local made = Instance.new("Model")
		made.Name = "Hangar"
		made.Parent = station.model
		folder = made
	end
	local changed = false
	for _, upgradeId in H.ORDER do
		local def = H.BY_ID[upgradeId]
		-- A built upgrade the owner switched off (Settings) isn't shown.
		local wanted = if profile.hangar[upgradeId] and profile.hangarOff[upgradeId]
			then nil
			elseif profile.hangar[upgradeId] then "built"
			elseif HangarMath.available(upgradeId, profile.hangar) then "pad"
			else nil
		local existing = (folder :: Instance):FindFirstChild(upgradeId)
		local state = if existing then existing:GetAttribute("State") else nil
		if state == wanted then
			continue
		end
		if existing then
			existing:Destroy()
		end
		if wanted == nil then
			continue
		end
		local floor = station.floor * CFrame.new(def.pad.x, 0, def.pad.z)
		local site = def.site
		local model = if wanted == "built"
			then HangarBuilder.structure(
				def,
				if site then station.floor * CFrame.new(site.x, site.y or 0, site.z) else floor
			)
			else HangarBuilder.pad(def, floor)
		model:SetAttribute("OwnerUserId", player.UserId)
		if wanted == "built" then
			if upgradeId == justBuilt then
				model:SetAttribute("BuiltAt", Workspace:GetServerTimeNow())
			end
			CollectionService:AddTag(model, STRUCTURE_TAG)
		end
		model.Parent = folder
		if wanted == "pad" then
			CollectionService:AddTag(model, PAD_TAG)
			hookPad(player, model, upgradeId)
		elseif upgradeId == SHOWCASE_ID then
			HangarSystem.refreshShowcase(player)
		end
		changed = true
	end
	-- New buildings take the station's highlight colour on their accents.
	if changed then
		StationSystem.recolor(player)
	end
end

-- Rebuilds the player's hangar upgrades (after one is switched on or off).
function HangarSystem.refresh(player: Player)
	refresh(player, nil)
end

function HangarSystem.start()
	StationSystem.stationAdded:Connect(function(player)
		refresh(player, nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTouch[player] = nil
	end)
end

return HangarSystem
