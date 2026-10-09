--!strict
-- The hangar incubator on this client: every chamber of every station
-- (parts tagged "GaG_Incubator", see StationBuilder) and the Incubator panel.
--
-- Chambers, for everyone nearby (owners and visitors): a label with the
-- chamber's status, time left and a progress bar, and inside the dome a
-- planet forming in its rarity's colour that grows and brightens as it
-- hatches. When one hatches (HatchedType / HatchedAt) the new planet pops
-- out with a burst for a few seconds; its owner also gets a banner. All of
-- it is drawn from the attributes HatchSystem writes; a mystery egg's planet
-- is only known once it has hatched.
--
-- Only the owner's chamber prompts are enabled. A prompt opens the panel:
-- the five chambers with their timers, and your waiting eggs, each with an
-- Incubate button. The server (HatchSystem) checks every request.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local PlanetLook = require(script.Parent.Parent.Fx.PlanetLook)
local StarFx = require(script.Parent.Parent.Fx.StarFx)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EggMath = require(Shared:WaitForChild("Logic"):WaitForChild("EggMath"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local StarMath = require(Shared:WaitForChild("Logic"):WaitForChild("StarMath"))
local Types = require(Shared:WaitForChild("Types"))

local P = Config.Planets
local E = Config.Eggs
local C = Theme.COLORS
local TAG = "GaG_Incubator"
local EGG_COLOR = Color3.fromRGB(255, 110, 200)
local REVEAL_SECONDS = 5
local DOME_CENTER = Vector3.new(0, 2.8, 0) -- above the chamber base's centre
local EGG_MAX = 2.4 -- studs across when ready to hatch (taller by the mesh)
local EGG_MIN_SHARE = 0.3 -- its size when it starts, as a share of EGG_MAX

local HatchController = {}

type Chamber = {
	part: BasePart,
	gui: BillboardGui,
	title: TextLabel,
	status: TextLabel,
	fill: Frame,
	forming: Part?,
	formingKey: string, -- the rarity and tier the forming egg was made for
	reveal: Part?,
	revealUntil: number,
	connections: { RBXScriptConnection },
}

local chambers: { [BasePart]: Chamber } = {}

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local list: ScrollingFrame
local targetChamber: number? = nil
local busy = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function isMine(part: BasePart): boolean
	return part:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
end

local function rarityColor(rarity: unknown): Color3
	local def = if type(rarity) == "string" then P.RARITIES[rarity] else nil
	return if def then Color3.fromHex(def.color) else EGG_COLOR
end

-- Time left as "m:ss" or "h:mm:ss".
local function clockText(seconds: number): string
	local s = math.max(math.ceil(seconds), 0)
	local h, m, sec = s // 3600, (s % 3600) // 60, s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- Chamber state from its attributes: (rarity, progress 0..1, seconds left)
-- while hatching, or nil when empty.
local function state(part: BasePart): (string?, number, number)
	local rarity = part:GetAttribute("Rarity")
	local started = part:GetAttribute("StartedAt")
	local ends = part:GetAttribute("EndsAt")
	if type(rarity) ~= "string" or type(started) ~= "number" or type(ends) ~= "number" then
		return nil, 0, 0
	end
	local total = math.max(ends - started, 1)
	local left = ends - now()
	return rarity, math.clamp(1 - left / total, 0, 1), left
end

local function makeLabel(part: BasePart): (BillboardGui, TextLabel, TextLabel, Frame)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GaG_ChamberLabel"
	billboard.Size = UDim2.fromOffset(170, 58)
	-- Above the dome, drawn over everything so the glass, walls and the other
	-- chambers never hide it; only shown nearby so it doesn't show through
	-- the station from far away.
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 8.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 10
	billboard.Adornee = part
	billboard.Parent = part
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(16, 12, 30)
	back.BackgroundTransparency = 0.25
	back.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = back
	local title = Theme.label(back, {
		Position = UDim2.fromOffset(8, 3),
		Size = UDim2.new(1, -16, 0, 18),
		TextSize = 14,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local status = Theme.label(back, {
		Position = UDim2.fromOffset(8, 21),
		Size = UDim2.new(1, -16, 0, 16),
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextColor3 = C.subtle,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 10, 1, -14)
	track.Size = UDim2.new(1, -20, 0, 7)
	track.BackgroundColor3 = Color3.fromRGB(40, 36, 60)
	track.BorderSizePixel = 0
	track.Parent = back
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	return billboard, title, status, fill
end

-- The chamber's glowing ring and cap light, in `color` (or back to pink).
local function tint(chamber: Chamber, color: Color3?)
	for _, name in { "ChamberRing", "CapLight" } do
		local item = chamber.part:FindFirstChild(name)
		if item and item:IsA("BasePart") then
			item.Color = color or EGG_COLOR
		end
	end
end

local function clearForming(chamber: Chamber)
	if chamber.forming then
		chamber.forming:Destroy()
		chamber.forming = nil
		chamber.formingKey = ""
		tint(chamber, nil)
	end
end

-- The egg inside the dome: an egg-shaped shell in the rarity's colour,
-- dressed with its tier's effects (PlanetLook.tierFx: glow, sparkles,
-- halo, aura, motes, rainbow), a warm light and a swirl of sparks. Made
-- again if the rarity or tier changes.
local function formingPart(chamber: Chamber, color: Color3, tier: number): Part
	local key = `{color:ToHex()}#{tier}`
	local egg = chamber.forming
	if egg and chamber.formingKey == key then
		return egg
	end
	clearForming(chamber)
	local reduced = ClientState.reducedEffects == true
	local made = Instance.new("Part")
	made.Name = "GaG_Forming"
	made.Shape = Enum.PartType.Ball
	made.Material = Enum.Material.SmoothPlastic
	made.Reflectance = 0.15
	made.Anchored = true
	made.CanCollide = false
	made.CanQuery = false
	made.CanTouch = false
	made.CastShadow = false
	made.Color = color
	made.Size = Vector3.one * EGG_MAX
	made.CFrame = CFrame.new(chamber.part.Position)
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "Shape"
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.35, 1) * EGG_MIN_SHARE
	mesh.Parent = made
	PlanetLook.tierFx(made, tier, EGG_MAX / 2, reduced)
	if not reduced then
		local swirl = Instance.new("ParticleEmitter")
		swirl.Rate = 6
		swirl.Lifetime = NumberRange.new(0.6, 1.1)
		swirl.Speed = NumberRange.new(0.5, 1.5)
		swirl.SpreadAngle = Vector2.new(180, 180)
		swirl.Size = NumberSequence.new(0.2, 0)
		swirl.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.5), color)
		swirl.LightEmission = 1
		swirl.LockedToPart = true
		swirl.Parent = made
	end
	local light = Instance.new("PointLight")
	light.Name = "Warmth"
	light.Color = color
	light.Range = 8
	light.Brightness = 1
	light.Parent = made
	made.Parent = chamber.part
	chamber.forming = made
	chamber.formingKey = key
	tint(chamber, color)
	return made
end

local function domeCenter(part: BasePart): Vector3
	-- The base is a cylinder standing on its X axis: its up is the part's +X.
	return part.Position + Vector3.new(0, DOME_CENTER.Y, 0)
end

local function refreshChamber(chamber: Chamber, t: number)
	local part = chamber.part
	local index = part:GetAttribute("Chamber")
	local rarity, progress, left = state(part)
	chamber.title.Text = `Chamber {if type(index) == "number" then index else "?"}`
	if rarity then
		local color = rarityColor(rarity)
		local rarityName = P.RARITIES[rarity] and P.RARITIES[rarity].displayName or rarity
		local tierAttr = part:GetAttribute("Tier")
		local tierName = if type(tierAttr) == "number"
				and tierAttr > 1
				and P.TIERS[tierAttr]
			then `{P.TIERS[tierAttr].name} `
			else ""
		chamber.title.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.3)
		chamber.status.Text = if left > 0
			then `{tierName}{rarityName} egg  ·  {math.floor(progress * 100)}%  ·  {clockText(
				left
			)}`
			else "Hatching..."
		chamber.fill.BackgroundColor3 = color
		chamber.fill.Size = UDim2.fromScale(progress, 1)
		local rawTier = part:GetAttribute("Tier")
		local tier = if type(rawTier) == "number" and P.TIERS[rawTier] then rawTier else 1
		local egg = formingPart(chamber, color, tier)
		local calm = ClientState.reducedEffects == true
		-- Grows from a small seed to full size, shell clearing as it ripens.
		local share = EGG_MIN_SHARE + (1 - EGG_MIN_SHARE) * progress
		local mesh = egg:FindFirstChild("Shape")
		if mesh and mesh:IsA("SpecialMesh") then
			mesh.Scale = Vector3.new(1, 1.35, 1) * share
		end
		egg.Transparency = 0.35 - progress * 0.35
		-- Glows brighter with its tier, and pulses like a heartbeat.
		local warmth = egg:FindFirstChild("Warmth")
		if warmth and warmth:IsA("PointLight") then
			local beat = 0.5 + 0.5 * math.sin(t * (2 + progress * 4))
			warmth.Brightness = (0.4 + tier * 0.25) * (0.6 + 0.4 * beat) * (0.4 + progress)
			warmth.Range = 5 + tier * 1.2
		end
		-- Sits on its cradle (1.5 below the dome centre) and rocks: gently at first, then in sudden
		-- jolts and little hops as hatching nears.
		local bottom = domeCenter(part) - Vector3.new(0, 1.5 - EGG_MAX * 1.35 * share / 2, 0)
		local wobble, hop = 0, 0
		if not calm then
			wobble = math.sin(t * 3) * 0.05 + progress ^ 3 * math.sin(t * 23) * 0.22
			if progress > 0.8 and math.sin(t * 5) > 0.6 then
				wobble += math.sin(t * 40) * 0.25
				hop = (math.sin(t * 5) - 0.6) * 0.4
			end
		end
		egg.CFrame = CFrame.new(bottom + Vector3.new(0, hop, 0))
			* CFrame.Angles(wobble, t * 0.3, wobble * 0.6)
	else
		clearForming(chamber)
		chamber.title.TextColor3 = C.text
		chamber.status.Text = "Empty"
		chamber.fill.Size = UDim2.fromScale(0, 1)
	end
	if chamber.reveal then
		if t > chamber.revealUntil or chamber.reveal.Parent == nil then
			chamber.reveal:Destroy()
			chamber.reveal = nil
		else
			local spinAngle = if ClientState.reducedEffects then 0 else t * 1.5
			chamber.reveal.CFrame = CFrame.new(domeCenter(part) + Vector3.new(0, 3.5, 0))
				* CFrame.Angles(0, spinAngle, 0)
		end
	end
end

-- The planet that just hatched, shown above its chamber for a few seconds.
local function onHatched(chamber: Chamber)
	local typeId = chamber.part:GetAttribute("HatchedType")
	local at = chamber.part:GetAttribute("HatchedAt")
	local rawTier = chamber.part:GetAttribute("HatchedTier")
	local tier = if type(rawTier) == "number" and P.TIERS[rawTier] then rawTier else 1
	local def = if type(typeId) == "string" then P.BY_ID[typeId] else nil
	if def == nil or type(at) ~= "number" or now() - at > REVEAL_SECONDS then
		return
	end
	if chamber.reveal then
		chamber.reveal:Destroy()
	end
	clearForming(chamber)
	local body = PlanetLook.build(def, 1.6, ClientState.reducedEffects == true, tier)
	body.Name = "GaG_Hatched"
	body.Parent = chamber.part
	chamber.reveal = body
	chamber.revealUntil = now() + REVEAL_SECONDS
	local color = Color3.fromHex(P.RARITIES[def.rarity].color)
	local center = domeCenter(chamber.part) + Vector3.new(0, 3.5, 0)
	body.CFrame = CFrame.new(center)
	StarFx.levelUp(center, 2.5, color)
	StarFx.materialize(body, Color3.fromHex(def.color))
	if isMine(chamber.part) then
		local rarity = P.RARITIES[def.rarity]
		local tierDef = P.TIERS[tier]
		ClientState.celebrate:Fire(
			"PLANET HATCHED",
			`{tierDef.name} {def.displayName}`,
			`{rarity.displayName}  ·  tier {tier} x{tierDef.multiplier}  ·  +{Format.rate(
				StarMath.planetFactor(def.id, 1, tier) * 100
			)}% of its star's output  ·  equip it from Planets (P)`,
			color,
			rarity.index >= 3 or tier >= E.ANNOUNCE_TIER
		)
	end
end

local function addChamber(instance: Instance)
	if not instance:IsA("BasePart") or chambers[instance] then
		return
	end
	local part = instance :: BasePart
	local billboard, title, status, fill = makeLabel(part)
	local chamber: Chamber = {
		part = part,
		gui = billboard,
		title = title,
		status = status,
		fill = fill,
		forming = nil,
		formingKey = "",
		reveal = nil,
		revealUntil = 0,
		connections = {},
	}
	chambers[part] = chamber
	local prompt = part:FindFirstChild("Incubate")
	if prompt and prompt:IsA("ProximityPrompt") then
		-- Visitors can look but not act.
		prompt.Enabled = isMine(part)
	end
	table.insert(
		chamber.connections,
		part:GetAttributeChangedSignal("HatchedAt"):Connect(function()
			local ok, problem = pcall(onHatched :: any, chamber)
			if not ok then
				warn(`[HatchController] hatch effect failed: {problem}`)
			end
		end)
	)
	refreshChamber(chamber, now())
end

local function removeChamber(instance: Instance)
	local chamber = chambers[instance :: BasePart]
	if chamber == nil then
		return
	end
	for _, connection in chamber.connections do
		connection:Disconnect()
	end
	clearForming(chamber)
	if chamber.reveal then
		chamber.reveal:Destroy()
	end
	chamber.gui:Destroy()
	chambers[instance :: BasePart] = nil
end

-- Panel ------------------------------------------------------------------

local refresh: () -> ()

local function close()
	gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local function incubate(eggId: string, chamber: number)
	if busy then
		return
	end
	busy = true
	local ok, message = Net.HatchRequest:InvokeServer("start", eggId, chamber)
	busy = false
	ClientState.notify:Fire(
		if type(message) == "string" then message else if ok then "Done" else "Failed"
	)
	refresh()
end

local function fillAll()
	if busy then
		return
	end
	busy = true
	local ok, message = Net.HatchRequest:InvokeServer("fill")
	busy = false
	ClientState.notify:Fire(
		if type(message) == "string" then message else if ok then "Done" else "Failed"
	)
	refresh()
end

local function freeChamber(): number?
	local profile = ClientState.profile
	local hatches = if profile and profile.hatches then profile.hatches else {}
	if targetChamber and hatches[tostring(targetChamber)] == nil then
		return targetChamber
	end
	for index = 1, E.HATCH_SLOTS do
		if hatches[tostring(index)] == nil then
			return index
		end
	end
	return nil
end

local timerLabels: { [number]: TextLabel } = {}

local function timerText(index: number): string
	local profile = ClientState.profile
	local hatch = if profile and profile.hatches then profile.hatches[tostring(index)] else nil
	if hatch == nil then
		return "Empty"
	end
	local rarity = P.RARITIES[hatch.rarity]
	local left = hatch.endsAt - now()
	local total = math.max(hatch.endsAt - hatch.startedAt, 1)
	local progress = math.clamp(1 - left / total, 0, 1)
	return `{if rarity then rarity.displayName else "?"} egg  ·  {math.floor(progress * 100)}%  ·  {if left
			> 0
		then `{clockText(left)} left`
		else "hatching..."}`
end

refresh = function()
	if not gui.Enabled then
		return
	end
	local profile = ClientState.profile
	local eggs: { [string]: Types.EggView } = if profile and profile.eggs then profile.eggs else {}
	local hatches: { [string]: Types.HatchView } = if profile and profile.hatches
		then profile.hatches
		else {}
	local waiting = 0
	for _ in eggs do
		waiting += 1
	end
	local running = 0
	for _ in hatches do
		running += 1
	end
	header.Text =
		`{running}/{E.HATCH_SLOTS} chambers hatching  ·  {waiting} eggs waiting  ·  eggs keep hatching while you're away`
	Theme.clear(list)
	table.clear(timerLabels)
	local order = 0
	-- Fill every free chamber at once, and the auto-incubate switch.
	local tools = Theme.row(list, 40, order)
	tools.BackgroundTransparency = 1
	local free = running < E.HATCH_SLOTS and waiting > 0
	local fill = Theme.button(
		tools,
		if free then "Fill all chambers" else "Nothing to fill",
		if free then "buy" else "disabled",
		if free then fillAll else nil
	)
	fill.Size = UDim2.new(0.5, -4, 1, -4)
	local settings = if profile then profile.settings else nil
	local auto = settings == nil or settings.autoIncubate ~= false
	local toggle = Theme.button(
		tools,
		if auto then "Auto-incubate: ON" else "Auto-incubate: off",
		if auto then "special" else "primary",
		function()
			if settings then
				settings.autoIncubate = not auto
			end
			Net.SettingChanged:FireServer("autoIncubate", not auto)
			refresh()
		end
	)
	toggle.Position = UDim2.new(0.5, 4, 0, 0)
	toggle.Size = UDim2.new(0.5, -4, 1, -4)
	for index = 1, E.HATCH_SLOTS do
		order += 1
		local row = Theme.row(list, 40, order)
		local hatch = hatches[tostring(index)]
		local color = if hatch then rarityColor(hatch.rarity) else C.subtle
		Theme.label(row, {
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(0, 110, 1, 0),
			Text = `Chamber {index}{if index == targetChamber then " ◀" else ""}`,
			TextColor3 = color,
		})
		timerLabels[index] = Theme.label(row, {
			Position = UDim2.fromOffset(124, 0),
			Size = UDim2.new(1, -136, 1, 0),
			Text = timerText(index),
			Font = Enum.Font.Gotham,
			TextSize = 14,
			TextColor3 = C.subtle,
		})
	end
	order += 1
	local title = Theme.row(list, 30, order)
	title.BackgroundTransparency = 1
	Theme.label(title, {
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 1, -4),
		Text = "Your eggs",
		TextSize = 16,
		Font = Enum.Font.GothamBlack,
		TextColor3 = C.gold,
	})
	local ids: { string } = {}
	for id in eggs do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return (tonumber(string.sub(a, 2)) or 0) < (tonumber(string.sub(b, 2)) or 0)
	end)
	if #ids == 0 then
		order += 1
		local row = Theme.row(list, 46, order)
		Theme.label(row, {
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -24, 1, 0),
			Text = "No eggs waiting. Roll and keep them at your Planet Egg Lab, beside the Stardust Collector.",
			Font = Enum.Font.Gotham,
			TextSize = 14,
			TextColor3 = C.subtle,
		})
		return
	end
	local chamber = freeChamber()
	local first: TextButton? = nil
	for _, id in ids do
		order += 1
		local egg = eggs[id]
		local def = if egg.outcome then P.BY_ID[egg.outcome] else nil
		local rarity = P.RARITIES[egg.rarity] or P.RARITIES[P.RARITY_ORDER[1]]
		local tierDef = P.TIERS[egg.tier] or P.TIERS[1]
		local row = Theme.row(list, 52, order)
		local dot = Theme.planetIcon(
			row,
			if def then Color3.fromHex(def.color) else Color3.fromHex(rarity.color),
			32,
			if egg.tier > 1 then Color3.fromHex(tierDef.color) else nil
		)
		dot.Position = UDim2.fromOffset(10, 10)
		Theme.label(row, {
			Position = UDim2.fromOffset(52, 6),
			Size = UDim2.new(1, -240, 0, 20),
			Text = if def
				then `{tierDef.name} {def.displayName} egg`
				else `{tierDef.name} {rarity.displayName} egg`,
			TextColor3 = Color3.fromHex(rarity.color),
		})
		Theme.label(row, {
			Position = UDim2.fromOffset(52, 27),
			Size = UDim2.new(1, -240, 0, 18),
			Text = `Tier {egg.tier} x{tierDef.multiplier}  ·  hatches in {EggMath.durationText(
				rarity.hatchSeconds
			)}`,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = C.subtle,
		})
		local button = Theme.button(
			row,
			if chamber then `Incubate · chamber {chamber}` else "All chambers busy",
			if chamber then "buy" else "disabled",
			if chamber
				then function()
					incubate(id, chamber :: number)
				end
				else nil
		)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.Size = UDim2.fromOffset(180, 36)
		first = first or button
	end
	if Input.device() == "gamepad" and first then
		GuiService.SelectedObject = first
	end
end

local function open(chamber: number?)
	targetChamber = chamber
	gui.Enabled = true
	local ok, problem = pcall(refresh :: any)
	if not ok then
		warn(`[Incubator] Could not show the incubator: {problem}`)
	end
	Theme.popIn(panel)
end

function HatchController.init()
	gui = Theme.screen("Incubator", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0.8, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(640, 680)
	size.Parent = panel
	Theme.label(panel, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -120, 0, 28),
		Text = "Incubator",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextColor3 = EGG_COLOR,
	})
	header = Theme.label(panel, {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 18),
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = C.subtle,
	})
	Theme.closeButton(panel, close)
	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(14, 66)
	list.Size = UDim2.new(1, -28, 1, -78)
end

function HatchController.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(addChamber)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(removeChamber)
	for _, part in CollectionService:GetTagged(TAG) do
		addChamber(part)
	end
	local tick = 0
	RunService.RenderStepped:Connect(function(dt)
		local t = now()
		for _, chamber in chambers do
			local ok, problem = pcall(refreshChamber :: any, chamber, t)
			if not ok then
				warn(`[HatchController] chamber update failed: {problem}`)
			end
		end
		tick += dt
		if gui.Enabled and tick >= 0.5 then
			tick = 0
			for index, label in timerLabels do
				label.Text = timerText(index)
			end
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local index = prompt:GetAttribute("HatchChamber")
		local part = prompt.Parent
		if type(index) == "number" and part and part:IsA("BasePart") and isMine(part) then
			open(index)
		end
	end)
	ClientState.profileChanged:Connect(function(field)
		if field == "eggs" or field == "hatches" or field == "settings" or field == "*" then
			refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and gui.Enabled and input.KeyCode == Enum.KeyCode.Backspace then
			close()
		end
	end)
end

return HatchController
