--!strict
-- What Death Star raids look like on this client (Config.Raids). Purely
-- visual; RaidSystem decides queues, hits and rewards.
--
--   Queue chip   While you're queued (player attribute RaidQueue): the
--                difficulty, how many are queued and the countdown (read
--                from the pad's Count / StartsAt / Busy attributes), with a
--                Leave button (RaidRequest "leave").
--   Boss bar     While you're raiding (player attribute Raid): the Death
--                Star's health (boss attribute Health), time left (EndsAt)
--                and raiders still flying (Raiders).
--   Attacks      RaidEvent "bolt": a green turbolaser bolt flying to where
--                it was aimed. "charge": the dish glows and a thin aiming
--                line appears, with a warning banner. "superlaser": a huge
--                beam down that line, shaking nearby cameras. "drone": a
--                drone bursts. "shockCharge": the plane a shockwave will
--                sweep glows red; "shockwave": a ring of light races out
--                along it. "bombard": red zones swell where blasts will
--                land; "bombardBlast": they explode.
--   Boss         "weakMoved": a streak from the old weak point to the new
--                one and a WEAK POINT MOVED banner. "enraged": a banner and a
--                shake; the boss bar says ENRAGED.
--   Finale       "bossDown": a chain of explosions over the Death Star and a
--                blinding flash. "result": a victory or defeat banner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local CombatController = require(script.Parent.CombatController)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))

local R = Config.Raids
local player = Players.LocalPlayer

local LASER_GREEN = Color3.fromRGB(110, 255, 130)
local LASER_CORE = Color3.fromRGB(225, 255, 230)
local DANGER = Color3.fromRGB(255, 70, 70)
local GOLD = Color3.fromRGB(255, 211, 107)
local BOLT_LENGTH = 22
local REFRESH = 0.2

type Bolt = { part: Part, from: Vector3, to: Vector3, started: number, travel: number }
type Ring = {
	segments: { Part },
	center: Vector3,
	u: Vector3,
	w: Vector3,
	normal: Vector3,
	started: number,
}

local RaidController = {}

local bolts: { Bolt } = {}
local rings: { Ring } = {}
local warningToken = 0
local fx: Folder? = nil
local gui: ScreenGui
local chip: Frame
local chipTitle: TextLabel
local chipStatus: TextLabel
local bar: Frame
local barTitle: TextLabel
local barFill: Frame
local barPercent: TextLabel
local barInfo: TextLabel
local warning: TextLabel
local padArea: Instance? = nil
local sinceRefresh = 0

local function colorOf(difficulty: string): Color3
	local def = R.BY_ID[difficulty]
	return if def then Color3.fromHex(def.color) else GOLD
end

local function fxFolder(): Folder
	local existing = fx
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "GaG_RaidFx"
	made.Parent = Workspace.CurrentCamera
	fx = made
	return made
end

local function glowPart(shape: Enum.PartType, color: Color3, size: Vector3): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = fxFolder()
	return part
end

-- A cylinder from `a` to `b` (a cylinder's axis is its X).
local function beamBetween(part: Part, a: Vector3, b: Vector3, width: number)
	local length = (b - a).Magnitude
	part.Size = Vector3.new(length, width, width)
	part.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
end

local function fadeAway(part: Instance, seconds: number)
	if part:IsA("BasePart") then
		TweenService:Create(part, TweenInfo.new(seconds), { Transparency = 1 }):Play()
	end
	task.delay(seconds, function()
		part:Destroy()
	end)
end

local function shakeFrom(at: Vector3, amount: number, radius: number)
	local distance = (Workspace.CurrentCamera.CFrame.Position - at).Magnitude
	if distance < radius then
		ClientState.shake:Fire(amount * (1 - distance / radius))
	end
end

-- A flashing banner mid-screen, for raiders only. A newer one replaces it.
local function showWarning(text: string, color: Color3, seconds: number)
	if player:GetAttribute("Raid") == nil then
		return
	end
	warningToken += 1
	local token = warningToken
	warning.Text = text
	warning.TextColor3 = color
	warning.Visible = true
	task.delay(seconds, function()
		if warningToken == token then
			warning.Visible = false
		end
	end)
end

-- Attacks ------------------------------------------------------------------

local function onBolt(from: unknown, to: unknown, travel: unknown)
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or type(travel) ~= "number" then
		return
	end
	local part = glowPart(Enum.PartType.Cylinder, LASER_GREEN, Vector3.new(BOLT_LENGTH, 1.6, 1.6))
	local light = Instance.new("PointLight")
	light.Color = LASER_GREEN
	light.Range = 24
	light.Brightness = 3
	light.Parent = part
	table.insert(
		bolts,
		{ part = part, from = from, to = to, started = os.clock(), travel = travel }
	)
end

local function onCharge(from: unknown, to: unknown, seconds: unknown)
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or type(seconds) ~= "number" then
		return
	end
	local orb = glowPart(Enum.PartType.Ball, LASER_GREEN, Vector3.one * 4)
	orb.CFrame = CFrame.new(from)
	orb.Transparency = 0.2
	TweenService
		:Create(orb, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = Vector3.one * R.SUPERLASER_WIDTH * 1.4,
		})
		:Play()
	local light = Instance.new("PointLight")
	light.Color = LASER_GREEN
	light.Range = 120
	light.Brightness = 6
	light.Parent = orb
	local aim = glowPart(Enum.PartType.Cylinder, DANGER, Vector3.one)
	aim.Transparency = 0.6
	beamBetween(aim, from, to, 1.2)
	task.delay(seconds, function()
		orb:Destroy()
		aim:Destroy()
	end)
	showWarning("SUPERLASER CHARGING: MOVE!", DANGER, seconds)
end

local function onSuperlaser(from: unknown, to: unknown)
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local width = R.SUPERLASER_WIDTH
	local outer = glowPart(Enum.PartType.Cylinder, LASER_GREEN, Vector3.one)
	beamBetween(outer, from, to, width)
	outer.Transparency = 0.35
	local inner = glowPart(Enum.PartType.Cylinder, LASER_CORE, Vector3.one)
	beamBetween(inner, from, to, width * 0.4)
	fadeAway(outer, 0.9)
	fadeAway(inner, 0.6)
	shakeFrom((from + to) / 2, 3, 900)
end

local function onBossDown(pivot: unknown, size: unknown)
	if typeof(pivot) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return
	end
	local radius = size.X / 2
	local reduced = ClientState.reducedEffects
	local count = if reduced then 4 else 10
	for i = 1, count do
		task.delay((i - 1) * 0.16, function()
			local direction =
				Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
			local at = CFrame.new(pivot.Position + direction * radius * (0.6 + math.random() * 0.4))
			CombatController.explode(at, Vector3.new(40, 20, 40), "#8A8F99", 0)
		end)
	end
	task.delay(count * 0.16, function()
		local flash = glowPart(Enum.PartType.Ball, LASER_CORE, Vector3.one * radius)
		flash.CFrame = pivot
		flash.Transparency = 0.1
		TweenService:Create(flash, TweenInfo.new(1.4, Enum.EasingStyle.Quad), {
			Size = Vector3.one * radius * 5,
			Transparency = 1,
		}):Play()
		task.delay(1.5, function()
			flash:Destroy()
		end)
		shakeFrom(pivot.Position, 4, 1600)
	end)
end

local function onResult(won: unknown, difficulty: unknown)
	if type(difficulty) ~= "string" or R.BY_ID[difficulty] == nil then
		return
	end
	local reward = R.BY_ID[difficulty].reward
	if won == true then
		local details = `+{Format.abbreviate(reward.stardust)} Stardust`
		if reward.boost then
			local what = if reward.boost.source == "mining"
				then "2x Mining"
				else "2x Star Production"
			details ..= ` and {math.floor(reward.boost.seconds / 60)} min of {what}`
		end
		ClientState.celebrate:Fire(
			"RAID VICTORY",
			`{difficulty} Death Star destroyed`,
			details,
			GOLD,
			true
		)
	elseif won == false then
		ClientState.notify:Fire(
			`The {difficulty} raid ended without a reward. Deal more damage or stay alive to share it.`
		)
	end
end

local DRONE_RED = Color3.fromRGB(255, 70, 60)
local WAVE_COLOR = Color3.fromRGB(255, 120, 90)
local RING_SEGMENTS = 36

local function onDrone(at: unknown)
	if typeof(at) ~= "Vector3" then
		return
	end
	CombatController.explode(CFrame.new(at), Vector3.new(10, 6, 10), "#FF4A3D", 0)
end

-- Two unit vectors spanning the plane with this normal.
local function planeBasis(normal: Vector3): (Vector3, Vector3)
	local other = if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local u = normal:Cross(other).Unit
	return u, normal:Cross(u).Unit
end

local function onShockCharge(center: unknown, normal: unknown, seconds: unknown)
	if typeof(center) ~= "Vector3" or typeof(normal) ~= "Vector3" or type(seconds) ~= "number" then
		return
	end
	-- The plane the ring will sweep, shown as a faint red disc.
	local disc = glowPart(Enum.PartType.Cylinder, DANGER, Vector3.one)
	disc.Material = Enum.Material.ForceField
	disc.Size = Vector3.new(1, R.SHOCKWAVE_RANGE * 2, R.SHOCKWAVE_RANGE * 2)
	local u, w = planeBasis(normal)
	-- A cylinder's axis is X: lay it along the normal.
	disc.CFrame = CFrame.fromMatrix(center, normal, u, w)
	disc.Transparency = 0.35
	TweenService:Create(disc, TweenInfo.new(seconds), { Transparency = 0.1 }):Play()
	task.delay(seconds, function()
		disc:Destroy()
	end)
	showWarning("SHOCKWAVE: GET OUT OF THE RED PLANE!", WAVE_COLOR, seconds + 0.6)
end

local function onShockwave(center: unknown, normal: unknown)
	if typeof(center) ~= "Vector3" or typeof(normal) ~= "Vector3" then
		return
	end
	local u, w = planeBasis(normal)
	local segments: { Part } = {}
	for _ = 1, if ClientState.reducedEffects then RING_SEGMENTS // 2 else RING_SEGMENTS do
		table.insert(segments, glowPart(Enum.PartType.Block, WAVE_COLOR, Vector3.one))
	end
	table.insert(rings, {
		segments = segments,
		center = center,
		u = u,
		w = w,
		normal = normal,
		started = os.clock(),
	})
	shakeFrom(center, 2, 1200)
end

-- Grows every shockwave ring at SHOCKWAVE_SPEED, fading as it goes.
local function stepRings()
	local now = os.clock()
	for i = #rings, 1, -1 do
		local ring = rings[i]
		local radius = (now - ring.started) * R.SHOCKWAVE_SPEED
		if radius > R.SHOCKWAVE_RANGE then
			for _, segment in ring.segments do
				segment:Destroy()
			end
			table.remove(rings, i)
			continue
		end
		local count = #ring.segments
		local length = 2 * math.pi * math.max(radius, 1) / count
		local fade = radius / R.SHOCKWAVE_RANGE
		for index, segment in ring.segments do
			local angle = (index - 1) / count * 2 * math.pi
			local out = ring.u * math.cos(angle) + ring.w * math.sin(angle)
			local tangent = ring.normal:Cross(out)
			segment.Size = Vector3.new(length * 1.05, R.SHOCKWAVE_THICKNESS, R.SHOCKWAVE_BAND)
			segment.CFrame = CFrame.fromMatrix(ring.center + out * radius, tangent, ring.normal)
			segment.Transparency = 0.15 + 0.75 * fade
		end
	end
end

local function onBombard(spots: unknown, seconds: unknown)
	if type(spots) ~= "table" or type(seconds) ~= "number" then
		return
	end
	for _, spot in spots :: { any } do
		if typeof(spot) ~= "Vector3" then
			continue
		end
		local zone = glowPart(Enum.PartType.Ball, DRONE_RED, Vector3.one * 4)
		zone.Material = Enum.Material.ForceField
		zone.CFrame = CFrame.new(spot)
		TweenService:Create(zone, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
			Size = Vector3.one * R.BOMBARD_RADIUS * 2,
		}):Play()
		local core = glowPart(Enum.PartType.Ball, DRONE_RED, Vector3.one * 3)
		core.CFrame = CFrame.new(spot)
		Theme.animate(core, function(now)
			core.Transparency = if math.floor(now * 8) % 2 == 0 then 0 else 0.7
		end)
		task.delay(seconds, function()
			zone:Destroy()
			core:Destroy()
		end)
	end
	showWarning("BOMBARDMENT INCOMING: MOVE!", DRONE_RED, seconds)
end

local function onBombardBlast(spots: unknown)
	if type(spots) ~= "table" then
		return
	end
	for _, spot in spots :: { any } do
		if typeof(spot) == "Vector3" then
			CombatController.explode(
				CFrame.new(spot),
				Vector3.new(R.BOMBARD_RADIUS, R.BOMBARD_RADIUS / 2, R.BOMBARD_RADIUS),
				"#FF6A3D",
				0
			)
		end
	end
end

local function onWeakMoved(from: unknown, to: unknown)
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local streak = glowPart(Enum.PartType.Cylinder, LASER_GREEN, Vector3.one)
	beamBetween(streak, from, to, 3)
	fadeAway(streak, 0.7)
	local flash = glowPart(Enum.PartType.Ball, LASER_CORE, Vector3.one * 10)
	flash.CFrame = CFrame.new(to)
	TweenService:Create(flash, TweenInfo.new(0.6), { Size = Vector3.one * 60, Transparency = 1 })
		:Play()
	task.delay(0.65, function()
		flash:Destroy()
	end)
	showWarning("WEAK POINT MOVED!", LASER_GREEN, 1.4)
end

local function onEnraged(at: unknown)
	if typeof(at) ~= "Vector3" then
		return
	end
	shakeFrom(at, 3, 1500)
	showWarning("THE DEATH STAR IS ENRAGED!", DANGER, 2.5)
end

local function onEvent(kind: unknown, ...: unknown)
	if kind == "bolt" then
		onBolt(...)
	elseif kind == "charge" then
		onCharge(...)
	elseif kind == "superlaser" then
		onSuperlaser(...)
	elseif kind == "bossDown" then
		onBossDown(...)
	elseif kind == "result" then
		onResult(...)
	elseif kind == "drone" then
		onDrone(...)
	elseif kind == "shockCharge" then
		onShockCharge(...)
	elseif kind == "shockwave" then
		onShockwave(...)
	elseif kind == "bombard" then
		onBombard(...)
	elseif kind == "bombardBlast" then
		onBombardBlast(...)
	elseif kind == "weakMoved" then
		onWeakMoved(...)
	elseif kind == "enraged" then
		onEnraged(...)
	end
end

local function stepBolts()
	local now = os.clock()
	for i = #bolts, 1, -1 do
		local bolt = bolts[i]
		local t = if bolt.travel > 0 then (now - bolt.started) / bolt.travel else 1
		if t >= 1.15 then
			bolt.part:Destroy()
			table.remove(bolts, i)
			continue
		end
		-- Keeps going a little past its aim point, so a dodged bolt flies by.
		local direction = (bolt.to - bolt.from).Unit
		local head = bolt.from:Lerp(bolt.to, t)
		bolt.part.CFrame = CFrame.lookAt(head - direction * BOLT_LENGTH / 2, head)
			* CFrame.Angles(0, math.pi / 2, 0)
	end
end

-- HUD ----------------------------------------------------------------------

local function findPad(difficulty: string): Instance?
	if padArea == nil or padArea.Parent == nil then
		padArea = Workspace:FindFirstChild("RaidBeaconArea", true)
	end
	local area = padArea
	if area == nil then
		return nil
	end
	for _, child in area:GetChildren() do
		if child:GetAttribute("Difficulty") == difficulty then
			return child
		end
	end
	return nil
end

local function findBoss(difficulty: string): Instance?
	local raids = Workspace:FindFirstChild("Raids")
	if raids == nil then
		return nil
	end
	for _, child in raids:GetChildren() do
		if child:GetAttribute("Difficulty") == difficulty then
			return child
		end
	end
	return nil
end

local function refresh()
	local now = Workspace:GetServerTimeNow()
	local raid = player:GetAttribute("Raid")
	local queued = player:GetAttribute("RaidQueue")

	local boss = if type(raid) == "string" then findBoss(raid) else nil
	bar.Visible = boss ~= nil
	if boss and type(raid) == "string" then
		local health = boss:GetAttribute("Health")
		local endsAt = boss:GetAttribute("EndsAt")
		local raiders = boss:GetAttribute("Raiders")
		local share = if type(health) == "number" then math.clamp(health, 0, 1) else 1
		local enraged = boss:GetAttribute("Enraged") == true
		barTitle.Text =
			`DEATH STAR  ·  {string.upper(raid)}{if enraged then "  ·  ENRAGED" else ""}`
		barTitle.TextColor3 = colorOf(raid)
		barFill.Size = UDim2.fromScale(share, 1)
		barPercent.Text = `{math.ceil(share * 100)}%`
		local left = if type(endsAt) == "number" then math.max(math.ceil(endsAt - now), 0) else 0
		barInfo.Text = string.format(
			"%d:%02d left  ·  %d raider%s flying",
			left // 60,
			left % 60,
			if type(raiders) == "number" then raiders else 0,
			if raiders == 1 then "" else "s"
		)
	end

	chip.Visible = type(queued) == "string" and boss == nil
	if type(queued) == "string" then
		local pad = findPad(queued)
		local count = pad and pad:GetAttribute("Count")
		local startsAt = pad and pad:GetAttribute("StartsAt")
		local busy = pad and pad:GetAttribute("Busy")
		chipTitle.Text = `{string.upper(queued)} RAID QUEUE  ·  {if type(count) == "number"
			then count
			else 1} / {R.MAX_RAIDERS}`
		chipTitle.TextColor3 = colorOf(queued)
		chipStatus.Text = if busy == true
			then "A raid is in progress: you're next"
			elseif type(startsAt) == "number" and startsAt > 0 then `Launching in {math.max(
				math.ceil(startsAt - now),
				0
			)}s`
			else "Waiting for raiders"
		local stroke = chip:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = colorOf(queued)
		end
	end
end

local function buildHud()
	gui = Theme.screen("Raid", player:WaitForChild("PlayerGui"))
	gui.DisplayOrder = 4

	-- Queue chip, top centre.
	chip = Theme.panel(gui, "QueueChip")
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.Position = UDim2.new(0.5, 0, 0, 64)
	chip.Size = UDim2.fromOffset(340, 58)
	chip.Visible = false
	local chipStroke = chip:FindFirstChildOfClass("UIStroke")
	if chipStroke then
		chipStroke.Transparency = 0.1
		Theme.pulse(chipStroke, 0, 0.6, 4)
	end
	chipTitle = Theme.label(chip, {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -110, 0, 22),
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
	})
	chipStatus = Theme.label(chip, {
		Position = UDim2.fromOffset(14, 30),
		Size = UDim2.new(1, -110, 0, 18),
		TextSize = 13,
		TextColor3 = Theme.COLORS.subtle,
	})
	local leave = Theme.button(chip, "Leave", "primary", function()
		Net.RaidRequest:FireServer("leave")
	end)
	leave.AnchorPoint = Vector2.new(1, 0.5)
	leave.Position = UDim2.new(1, -10, 0.5, 0)
	leave.Size = UDim2.fromOffset(84, 36)

	-- Boss bar, top centre.
	bar = Theme.panel(gui, "BossBar")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 64)
	bar.Size = UDim2.new(0.5, 0, 0, 74)
	bar.Visible = false
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(300, 74)
	limit.MaxSize = Vector2.new(620, 74)
	limit.Parent = bar
	local barStroke = bar:FindFirstChildOfClass("UIStroke")
	if barStroke then
		barStroke.Color = DANGER
		barStroke.Transparency = 0.2
	end
	barTitle = Theme.label(bar, {
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -90, 0, 22),
		Font = Enum.Font.GothamBlack,
		TextSize = 17,
	})
	barPercent = Theme.label(bar, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 6),
		Size = UDim2.fromOffset(70, 22),
		Font = Enum.Font.GothamBlack,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(14, 32)
	track.Size = UDim2.new(1, -28, 0, 14)
	track.BackgroundColor3 = Color3.fromRGB(10, 12, 26)
	track.BorderSizePixel = 0
	track.Parent = bar
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 7)
	trackCorner.Parent = track
	barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = Color3.new(1, 1, 1)
	barFill.BorderSizePixel = 0
	barFill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 7)
	fillCorner.Parent = barFill
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 150, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 60)),
	})
	fillGradient.Parent = barFill
	Theme.animate(fillGradient, function(now)
		fillGradient.Offset = Vector2.new(math.sin(now * 1.5) * 0.3, 0)
	end)
	barInfo = Theme.label(bar, {
		Position = UDim2.fromOffset(14, 50),
		Size = UDim2.new(1, -28, 0, 18),
		TextSize = 13,
		TextColor3 = Theme.COLORS.subtle,
	})

	-- Superlaser warning, mid-screen.
	warning = Theme.label(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(520, 44),
		Font = Enum.Font.GothamBlack,
		TextSize = 30,
		TextColor3 = DANGER,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "SUPERLASER CHARGING: MOVE!",
		Visible = false,
	})
	Theme.animate(warning, function(now)
		warning.TextTransparency = if math.floor(now * 6) % 2 == 0 then 0 else 0.45
	end)
end

function RaidController.init() end

function RaidController.start()
	buildHud()
	Net.RaidEvent.OnClientEvent:Connect(onEvent)
	RunService.Heartbeat:Connect(function(dt)
		stepBolts()
		stepRings()
		sinceRefresh += dt
		if sinceRefresh >= REFRESH then
			sinceRefresh = 0
			refresh()
		end
	end)
end

return RaidController
