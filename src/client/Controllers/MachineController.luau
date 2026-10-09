--!strict
-- The deck machines coming alive on this client (DeviceBuilder; the full
-- show needs their mesh versions, attribute Mesh):
--
--   Stardust Collector  its glass tank fills with Stardust as your stars
--     produce (uncollected / the UncollectedCap player attribute); the gauge
--     lamps light up the column, the core floats above the fill, bobbing and
--     pulsing faster as it fills, and sparkles rise inside. Full, the gauge
--     blinks. Collecting (a "collect" Reward) drains the tank in a rush: the
--     core pops, a shockwave ring spreads and a fountain of sparkles shoots
--     out of the crown. Other players' collectors idle half full.
--   Galaxy Control  a hologram over the table showing the owner's stars as
--     glowing dots in their star colours, turning over a faint disc. Walk up
--     to your own and it wakes: the hologram grows and brightens, scan rings
--     sweep up and the console buttons blink; opening it fires a pulse.
--
-- On the older part-built machines the core still pulses and pops. Purely
-- visual; only machines within DETAIL_DISTANCE of the camera animate.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local RewardMath = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Shared")
		:WaitForChild("Logic")
		:WaitForChild("RewardMath")
)
-- Seconds between the collect effects played while Auto Collect is on.
local AUTO_COLLECT_EFFECT_SECONDS = 12

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local DETAIL_DISTANCE = 160 -- studs from the camera
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local GOLD = Color3.fromRGB(255, 201, 74)
local GOLD_HOT = Color3.fromRGB(255, 240, 190)
local GAUGE_OFF = Color3.fromRGB(58, 48, 32)
local HOLO = Color3.fromRGB(176, 107, 255)
local DRAIN_TIME = 0.6
local FILL_EASE = 3 -- per second, how fast the shown fill follows the real one
local OTHERS_FILL = 0.5
local WAKE_DISTANCE = 14 -- studs: Galaxy Control wakes when you're this close
local HOLO_RADIUS = 2.1 -- studs: the hologram's dots spread this far (asleep)
local STAR_SCAN = 3 -- seconds between looks for the owner's stars

local MachineController = {}

type Collector = {
	model: Model,
	orb: BasePart?,
	orbSize: Vector3,
	fill: BasePart?,
	base: Vector3, -- world point at the bottom of the tank
	up: Vector3,
	rotation: CFrame,
	height: number, -- the tank's inside height
	gauges: { BasePart },
	sparkles: ParticleEmitter?,
	shown: number, -- fill share on screen
	drainFrom: number?,
	drainAt: number,
}

type Holo = {
	model: Model,
	owner: number?,
	centre: Vector3,
	folder: Folder,
	disc: Part,
	core: Part,
	beam: Part,
	dots: { { part: Part, offset: Vector3, size: number } },
	buttons: { BasePart },
	signature: string,
	scale: number,
	angle: number,
	nextScan: number,
	nextRing: number,
	nextBlink: number,
	pulseAt: number,
}

local collectors: { [Model]: Collector } = {}
local holos: { [Model]: Holo } = {}

local function isMine(model: Model): boolean
	return model:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
end

local function localPart(name: string, shape: Enum.PartType, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- A flat glowing ring that spreads out (or rises) and fades.
local function ring(
	at: CFrame,
	from: number,
	to: number,
	color: Color3,
	time: number,
	rise: number?
)
	local part = localPart("GaG_Ring", Enum.PartType.Cylinder, color, Workspace.CurrentCamera)
	part.Material = Enum.Material.ForceField
	part.Size = Vector3.new(0.15, from, from)
	part.CFrame = at * CFrame.Angles(0, 0, math.pi / 2)
	part.Transparency = 0.1
	TweenService
		:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.05, to, to),
			Transparency = 1,
			CFrame = (at + Vector3.new(0, rise or 0, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		})
		:Play()
	Debris:AddItem(part, time + 0.1)
end

local function sparkleBurst(
	at: Vector3,
	amount: number,
	color: Color3,
	speed: NumberRange,
	up: boolean
)
	local attachment = Instance.new("Attachment")
	attachment.WorldCFrame = CFrame.new(at) * CFrame.Angles(0, 0, if up then math.pi / 2 else 0)
	attachment.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Rate = 0
	emitter.Speed = speed
	emitter.SpreadAngle = if up then Vector2.new(25, 25) else Vector2.new(180, 180)
	emitter.EmissionDirection = Enum.NormalId.Right
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Acceleration = Vector3.new(0, if up then -10 else 0, 0)
	emitter.Drag = 1
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Color = ColorSequence.new(GOLD_HOT, color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Parent = attachment
	emitter:Emit(if ClientState.reducedEffects then math.ceil(amount / 3) else amount)
	Debris:AddItem(attachment, 1.6)
end

-- Collector ------------------------------------------------------------------

local function addCollector(model: Model)
	if collectors[model] then
		return
	end
	local orb = model:FindFirstChild("StardustOrb")
	local fill = model:FindFirstChild("StardustFill")
	local state: Collector = {
		model = model,
		orb = if orb and orb:IsA("BasePart") then orb else nil,
		orbSize = if orb and orb:IsA("BasePart") then orb.Size else Vector3.one,
		fill = if fill and fill:IsA("BasePart") then fill else nil,
		base = Vector3.zero,
		up = Vector3.yAxis,
		rotation = CFrame.identity,
		height = 3.9,
		gauges = {},
		sparkles = nil,
		shown = 0,
		drainFrom = nil,
		drainAt = 0,
	}
	local fillPart = state.fill
	if fillPart then
		-- The fill is a cylinder lying along its X axis, which points up.
		state.up = fillPart.CFrame.RightVector
		state.rotation = fillPart.CFrame - fillPart.Position
		state.base = fillPart.Position - state.up * fillPart.Size.X / 2
		local bottom, top = model:GetAttribute("TankBottom"), model:GetAttribute("TankTop")
		if type(bottom) == "number" and type(top) == "number" then
			state.height = top - bottom - 0.2
		end
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = SPARKLE
		sparkles.EmissionDirection = Enum.NormalId.Right
		sparkles.Speed = NumberRange.new(0.8, 1.6)
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Size = NumberSequence.new(0.18, 0)
		sparkles.Color = ColorSequence.new(GOLD_HOT)
		sparkles.LightEmission = 1
		sparkles.LightInfluence = 0
		sparkles.Rate = 0
		sparkles.Parent = fillPart
		state.sparkles = sparkles
	end
	for _, item in model:GetDescendants() do
		local n = if item:IsA("BasePart")
			then tonumber(string.match(item.Name, "^Gauge(%d+)$"))
			else nil
		if n and item:IsA("BasePart") then
			state.gauges[n] = item
		end
	end
	collectors[model] = state
end

local function fillTarget(state: Collector): number
	if not isMine(state.model) then
		return OTHERS_FILL
	end
	local profile = ClientState.profile
	local cap = Players.LocalPlayer:GetAttribute("UncollectedCap")
	if profile == nil or type(cap) ~= "number" or cap <= 0 then
		return 0
	end
	return math.clamp(profile.uncollected / cap, 0, 1)
end

local function stepCollector(state: Collector, now: number, dt: number)
	local target = fillTarget(state)
	local drainFrom = state.drainFrom
	if drainFrom then
		local t = math.clamp((now - state.drainAt) / DRAIN_TIME, 0, 1)
		state.shown = drainFrom * (1 - t) ^ 2
		if t >= 1 then
			state.drainFrom = nil
		end
	else
		state.shown += (target - state.shown) * math.min(1, dt * FILL_EASE)
	end
	local share = state.shown
	local full = target >= 0.999 and drainFrom == nil

	local fill = state.fill
	local level = state.base + state.up * 0.6
	if fill then
		local height = math.max(0.15, share * state.height)
		fill.Size = Vector3.new(height, fill.Size.Y, fill.Size.Z)
		fill.CFrame = state.rotation + (state.base + state.up * height / 2)
		level = state.base + state.up * height
		local sparkles = state.sparkles
		if sparkles then
			sparkles.Rate = if ClientState.reducedEffects then 0 else 2 + share * 12
		end
	end
	local orb = state.orb
	if orb then
		local quick = 2 + share * 6
		local pulse = 1
			+ 0.08 * math.sin(now * quick)
			+ (if full then 0.06 * math.sin(now * 14) else 0)
		orb.Size = state.orbSize * pulse
		if fill then
			local lift =
				math.min(0.75 + math.sin(now * 2) * 0.15, state.height - share * state.height)
			orb.CFrame = CFrame.new(level + state.up * math.max(0.55, lift))
		end
	end
	for n, gauge in state.gauges do
		local lit = share >= (n - 0.5) / #state.gauges
		local color = if lit then GOLD else GAUGE_OFF
		if full and math.floor(now * 4) % 2 == 0 then
			color = GOLD_HOT
		end
		gauge.Color = color
	end
end

-- The tank drains in a rush; the core pops; a ring and a fountain of
-- sparkles go out.
local function collected(state: Collector)
	state.drainFrom = state.shown
	state.drainAt = os.clock()
	local orb = state.orb
	local at = if orb then orb.Position else state.base
	if orb then
		orb.Size = state.orbSize * 1.9
		local light = orb:FindFirstChildOfClass("PointLight")
		if light then
			local brightness = light.Brightness
			light.Brightness = brightness * 5
			TweenService:Create(light, TweenInfo.new(0.8), { Brightness = brightness }):Play()
		end
	end
	ring(CFrame.new(at), 2, 16, GOLD, 0.8)
	ring(CFrame.new(state.base + state.up * 0.2), 4, 10, GOLD_HOT, 0.6)
	local crown = state.base + state.up * (state.height + 1.6)
	sparkleBurst(crown, 45, GOLD, NumberRange.new(10, 18), true)
	sparkleBurst(at, 25, GOLD, NumberRange.new(4, 9), false)
end

-- Galaxy Control ---------------------------------------------------------------

local function addHolo(model: Model)
	if holos[model] or model:GetAttribute("Mesh") ~= true then
		return
	end
	local lens = model:FindFirstChild("Lens", true)
	local height = model:GetAttribute("HoloHeight")
	local centre = if lens and lens:IsA("BasePart")
		then lens.Position + Vector3.new(0, 1.9, 0)
		else model:GetPivot().Position + Vector3.new(
			0,
			if type(height) == "number" then height else 5,
			0
		)
	local folder = Instance.new("Folder")
	folder.Name = "GaG_Holo"
	folder.Parent = model
	local disc = localPart("Disc", Enum.PartType.Cylinder, HOLO, folder)
	disc.Material = Enum.Material.ForceField
	disc.Transparency = 0.3
	local core = localPart("Core", Enum.PartType.Ball, GOLD_HOT, folder)
	local beam = localPart("Beam", Enum.PartType.Cylinder, HOLO, folder)
	beam.Transparency = 0.85
	local buttons: { BasePart } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") and string.match(item.Name, "^Button%d+$") then
			table.insert(buttons, item)
		end
	end
	local owner = model:GetAttribute("OwnerUserId")
	holos[model] = {
		model = model,
		owner = if type(owner) == "number" then owner else nil,
		centre = centre,
		folder = folder,
		disc = disc,
		core = core,
		beam = beam,
		dots = {},
		buttons = buttons,
		signature = "",
		scale = 1,
		angle = 0,
		nextScan = 0,
		nextRing = 0,
		nextBlink = 0,
		pulseAt = -10,
	}
end

-- The owner's stars as dots: positions round their middle, squeezed into
-- the hologram, coloured by type, sized by tier.
local function scanStars(holo: Holo)
	local regions = Workspace:FindFirstChild("Regions")
	if regions == nil or holo.owner == nil then
		return
	end
	local stars: { { position: Vector3, typeId: string } } = {}
	for _, item in regions:GetDescendants() do
		if
			item:IsA("Model")
			and item:GetAttribute("StarId")
			and item:GetAttribute("OwnerUserId") == holo.owner
		then
			local typeId = item:GetAttribute("TypeId")
			local core = item.PrimaryPart
			if core and type(typeId) == "string" then
				table.insert(stars, { position = core.Position, typeId = typeId })
			end
		end
	end
	local parts = {}
	for _, star in stars do
		table.insert(
			parts,
			`{star.typeId}@{math.floor(star.position.X)},{math.floor(star.position.Z)}`
		)
	end
	table.sort(parts)
	local signature = table.concat(parts, ";")
	if signature == holo.signature then
		return
	end
	holo.signature = signature
	for _, dot in holo.dots do
		dot.part:Destroy()
	end
	holo.dots = {}
	if #stars == 0 then
		return
	end
	local middle = Vector3.zero
	for _, star in stars do
		middle += star.position
	end
	middle /= #stars
	local reach = 1
	for _, star in stars do
		local d = star.position - middle
		reach = math.max(reach, Vector2.new(d.X, d.Z).Magnitude)
	end
	for _, star in stars do
		local def = Config.Stars.BY_ID[star.typeId]
		local d = (star.position - middle) / reach * HOLO_RADIUS
		-- Dark stars (the Black Hole, the Void Flame) show their glow colour.
		local body = if def then Color3.fromHex(def.color) else GOLD
		local dark = body.R + body.G + body.B < 0.4
		local color = if def and dark then Color3.fromHex(def.light) else body
		local size = 0.16 + (if def then def.tier else 1) * 0.035
		local part = localPart("Star", Enum.PartType.Ball, color, holo.folder)
		table.insert(
			holo.dots,
			{ part = part, offset = Vector3.new(d.X, d.Y * 0.35, d.Z), size = size }
		)
	end
end

local function stepHolo(holo: Holo, now: number, dt: number)
	if now >= holo.nextScan then
		holo.nextScan = now + STAR_SCAN
		scanStars(holo)
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local awake = holo.owner == Players.LocalPlayer.UserId
		and root ~= nil
		and root:IsA("BasePart")
		and (root.Position - holo.centre).Magnitude < WAKE_DISTANCE
	local pulse = math.max(0, 1 - (now - holo.pulseAt) / 0.6)
	local target = (if awake then 1.35 else 1) + pulse * 0.3
	holo.scale += (target - holo.scale) * math.min(1, dt * 5)
	holo.angle += dt * (if awake then 0.55 else 0.25)
	local s = holo.scale
	local spinFrame = CFrame.new(holo.centre) * CFrame.Angles(0, holo.angle, 0)
	holo.disc.Size = Vector3.new(0.06, HOLO_RADIUS * 2.4 * s, HOLO_RADIUS * 2.4 * s)
	holo.disc.CFrame = spinFrame * CFrame.Angles(0, 0, math.pi / 2)
	holo.disc.Transparency = if awake then 0.12 else 0.35
	holo.core.Size = Vector3.one * (0.35 + 0.05 * math.sin(now * 3)) * s
	holo.core.CFrame = CFrame.new(holo.centre)
	local beamLength = 1.9 * s
	holo.beam.Size = Vector3.new(beamLength, 0.5 * s, 0.5 * s)
	holo.beam.CFrame = CFrame.new(holo.centre - Vector3.new(0, beamLength / 2, 0))
		* CFrame.Angles(0, 0, math.pi / 2)
	holo.beam.Transparency = if awake then 0.7 else 0.88
	for index, dot in holo.dots do
		local twinkle = 1 + 0.15 * math.sin(now * 3 + index) + pulse * 0.8
		dot.part.Size = Vector3.one * dot.size * s * twinkle
		dot.part.CFrame = spinFrame * CFrame.new(dot.offset * s)
	end
	if awake and now >= holo.nextRing then
		holo.nextRing = now + 2.2
		ring(CFrame.new(holo.centre - Vector3.new(0, 1.9, 0)), 4.5, 5.5, HOLO, 1.6, 2.6)
	end
	if #holo.buttons > 0 and now >= holo.nextBlink then
		holo.nextBlink = now + (if awake then 0.12 else 0.7)
		for _, button in holo.buttons do
			button.Transparency = if math.random() < (if awake then 0.4 else 0.15) then 0.75 else 0
		end
	end
end

-- Opening Galaxy Control: the hologram pulses and a ring bursts out.
local function opened(model: Model)
	local holo = holos[model]
	if holo then
		holo.pulseAt = os.clock()
		ring(CFrame.new(holo.centre), 2, 9, HOLO, 0.7)
		sparkleBurst(holo.centre, 20, HOLO, NumberRange.new(3, 6), false)
	end
end

-- Wiring -----------------------------------------------------------------------

local function consider(item: Instance)
	if not item:IsA("Model") then
		return
	end
	if item.Name == "StardustCollector" then
		-- Its parts may stream in a moment after the model.
		task.defer(addCollector, item)
	elseif item.Name == "GalaxyControl" then
		task.defer(addHolo, item)
	end
end

function MachineController.start()
	local regions = Workspace:WaitForChild("Regions", 30)
	if regions == nil then
		return
	end
	for _, item in regions:GetDescendants() do
		consider(item)
	end
	regions.DescendantAdded:Connect(consider)
	regions.DescendantRemoving:Connect(function(item)
		if item:IsA("Model") then
			collectors[item] = nil
			holos[item] = nil
		end
	end)

	-- With the Auto Collect pass, star income goes straight to the wallet,
	-- so nobody presses Collect: play the collect effects every
	-- AUTO_COLLECT_EFFECT_SECONDS instead, so the machine still looks busy.
	task.spawn(function()
		while true do
			task.wait(AUTO_COLLECT_EFFECT_SECONDS)
			local profile = ClientState.profile
			local passes = if profile then profile.passes else nil
			if passes and RewardMath.autoCollect(passes) and (profile :: any).incomeRate > 0 then
				for model, state in collectors do
					if isMine(model) then
						collected(state)
					end
				end
			end
		end
	end)

	Net.Reward.OnClientEvent:Connect(function(kind: unknown)
		if kind ~= "collect" then
			return
		end
		for model, state in collectors do
			if isMine(model) then
				collected(state)
			end
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("OpenPanel") ~= "Galaxy" then
			return
		end
		local item: Instance? = prompt.Parent
		while item and not (item:IsA("Model") and item.Name == "GalaxyControl") do
			item = item.Parent
		end
		if item and item:IsA("Model") then
			opened(item)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if ClientState.reducedEffects and math.random() < 0.5 then
			return -- half the frames are plenty with reduced effects
		end
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local eye = camera.CFrame.Position
		local now = os.clock()
		for model, state in collectors do
			if (model:GetPivot().Position - eye).Magnitude < DETAIL_DISTANCE then
				local ok, problem = pcall(function()
					stepCollector(state, now, dt)
				end)
				if not ok then
					warn(`[MachineController] collector: {problem}`)
					collectors[model] = nil
				end
			end
		end
		for model, holo in holos do
			if (holo.centre - eye).Magnitude < DETAIL_DISTANCE then
				local ok, problem = pcall(function()
					stepHolo(holo, now, dt)
				end)
				if not ok then
					warn(`[MachineController] galaxy control: {problem}`)
					holos[model] = nil
				end
			end
		end
	end)
end

return MachineController
