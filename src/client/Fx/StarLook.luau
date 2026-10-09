--!strict
-- A star's living surface, drawn on this client on top of the server's Core
-- ball (Config.StarLooks): a churning plasma shell, turbulent granules,
-- cloud belts, a corona, diffraction spikes, looping flares, stellar wind, for the black hole an accretion disk and jets, and for binary stars two stars circling each other.
--
--   StarLook.new(core, typeId, seed)  builds the layers (a folder beside the
--                                     core, in the star's model)
--   look.step(now, dt, camera, reduced)  call every frame: picks a level of
--                                     detail from the camera's distance
--                                     (checked a few times a second) and
--                                     animates only what that level shows
--   look.destroy()
--
-- The core, its light, its prompt and the star's attributes are never
-- touched: only the server's own Corona and Disk parts are hidden locally
-- (LocalTransparencyModifier), as the look draws its own. Rebuild the look
-- when the star's type or size changes (StarController does).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local L = Config.StarLooks
local WHITE = Color3.new(1, 1, 1)

-- Levels of detail.
local FAR, MID, NEAR = 1, 2, 3

export type Look = {
	typeId: string,
	radius: number,
	step: (now: number, dt: number, camera: Vector3, reduced: boolean) -> (),
	destroy: () -> (),
}

local StarLook = {}

local function hex(color: string): Color3
	return Color3.fromHex(color)
end

local function sequence(colors: { string }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(hex(colors[1]))
	end
	local keys = {}
	for i, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), hex(color)))
	end
	return ColorSequence.new(keys)
end

local function localPart(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- A camera-facing glow of `diameter` studs at the core's centre: about three
-- big, slowly turning additive particles that overlap and fade in and out in
-- turn, so the glow's ragged edge keeps shifting. Additive light means the
-- texture's dark surround adds nothing, and the core hides the middle,
-- leaving a halo round its edge.
local function glow(
	core: BasePart,
	name: string,
	texture: string,
	diameter: number,
	color: Color3,
	transparency: number
): ParticleEmitter
	local anchor = Instance.new("Attachment")
	anchor.Name = name
	anchor.Parent = core
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = texture
	emitter.Speed = NumberRange.new(0)
	emitter.LockedToPart = true
	emitter.Lifetime = NumberRange.new(4)
	emitter.Rate = 0.75
	emitter.Size = NumberSequence.new(diameter)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, transparency),
		NumberSequenceKeypoint.new(0.7, transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-6, 6)
	emitter.Parent = anchor
	emitter:Emit(2)
	return emitter
end

-- A random direction on the sphere, kept within `maxLatitude` radians of the
-- equator (flares live in belts, like the Sun's).
local function surfaceDirection(rng: Random, maxLatitude: number): Vector3
	local lon = rng:NextNumber(0, 2 * math.pi)
	local lat = rng:NextNumber(-maxLatitude, maxLatitude)
	return Vector3.new(math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * math.sin(lon))
end

-- Any vector at right angles to `v`.
local function perpendicular(v: Vector3): Vector3
	local other = if math.abs(v.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	return v:Cross(other).Unit
end

type Flare = {
	beam: Beam,
	a: Attachment,
	b: Attachment,
	started: number,
	active: boolean,
}

function StarLook.new(core: BasePart, typeId: string, seed: number): Look
	local look = L.LOOKS[typeId]
	local radius = core.Size.X / 2
	local rng = Random.new(seed)
	local folder = Instance.new("Folder")
	folder.Name = "GaG_StarLook"
	folder.Parent = core.Parent

	-- The server's simple extras give way to the look's own.
	local model = core.Parent
	local hidden: { BasePart } = {}
	if model then
		for _, name in { "Corona", "Disk" } do
			local extra = model:FindFirstChild(name)
			if extra and extra:IsA("BasePart") then
				extra.LocalTransparencyModifier = 1
				table.insert(hidden, extra)
			end
		end
	end

	-- The core's own colour, deeper than the server's neon, so the surface
	-- layers read on it (put back on destroy).
	local serverColor = core.Color
	if look and look.core then
		core.Color = hex(look.core)
	end

	local emitters: { [string]: ParticleEmitter } = {}
	local shells: { { part: Part, offset: CFrame } } = {} -- follow the core
	local disk: Model? = nil
	local flares: { Flare } = {}
	local nextFlare = 0
	local spin = 0
	local level = 0
	local nextLod = 0
	local lastCFrame = core.CFrame

	if look == nil then
		return {
			typeId = typeId,
			radius = radius,
			step = function() end,
			destroy = function()
				folder:Destroy()
			end,
		}
	end

	-- The first orbit stays clear of the corona.
	local firstOrbit = Config.Stars.SLOTS[1].orbit
	local maxGlow = 2 * (firstOrbit - L.CORONA_ORBIT_MARGIN)

	local plasma = look.plasma
	if plasma then
		local shell = localPart(
			"Plasma",
			Enum.PartType.Ball,
			Vector3.one * radius * 2 * plasma.scale,
			hex(plasma.color),
			Enum.Material.ForceField,
			folder
		)
		shell.Transparency = plasma.transparency
		table.insert(shells, { part = shell, offset = CFrame.identity })
	end

	local bands = look.bands
	if bands then
		for i = 1, bands.count do
			-- Latitude of the belt's middle, from -0.8r to 0.8r.
			local y = radius * 0.8 * ((i - 0.5) / bands.count * 2 - 1)
			local width = 2 * math.sqrt(radius * radius - y * y) * 1.006
			local belt = localPart(
				"Band",
				Enum.PartType.Cylinder,
				Vector3.new(radius * 1.6 / bands.count * 0.7, width, width),
				hex(bands.colors[(i - 1) % #bands.colors + 1]),
				Enum.Material.Neon,
				folder
			)
			table.insert(shells, {
				part = belt,
				offset = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
			})
		end
	end

	local granules = look.granules
	if granules then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Granules"
		emitter.Texture = granules.texture
		emitter.Shape = Enum.ParticleEmitterShape.Sphere
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		emitter.Speed = NumberRange.new(0)
		emitter.LockedToPart = true
		emitter.Lifetime = NumberRange.new(granules.life[1], granules.life[2])
		emitter.Rate = math.min(granules.rate * (radius / 10) ^ 2, 60)
		local s = radius * granules.size
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, s * 0.5),
			NumberSequenceKeypoint.new(0.5, s),
			NumberSequenceKeypoint.new(1, s * 0.8),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Color = sequence(granules.colors)
		emitter.LightEmission = 0.25
		emitter.LightInfluence = 0
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-20, 20)
		emitter.Parent = core
		emitters.Granules = emitter
	end

	local wind = look.wind
	if wind then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Wind"
		emitter.Texture = wind.texture
		emitter.Shape = Enum.ParticleEmitterShape.Sphere
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		emitter.Speed = NumberRange.new(radius * wind.speed * 0.6, radius * wind.speed)
		emitter.Lifetime = NumberRange.new(wind.life * 0.7, wind.life)
		emitter.Rate = wind.rate
		emitter.Size = NumberSequence.new(radius * wind.size * 0.4, radius * wind.size)
		-- Additive, so the smoke texture's grey reads as a faint tinted haze.
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Color = ColorSequence.new(hex(wind.color))
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Parent = core
		emitters.Wind = emitter
	end

	local corona = look.corona
	if corona then
		local diameter = math.min(radius * 2 * corona.scale, maxGlow)
		emitters.Corona =
			glow(core, "Corona", L.GLOW_TEXTURE, diameter, hex(corona.color), corona.transparency)
		-- A brighter, tighter inner glow hugging the limb.
		emitters.Limb = glow(
			core,
			"Limb",
			L.GLOW_TEXTURE,
			math.min(radius * 2 * 1.3, maxGlow),
			hex(corona.color):Lerp(WHITE, 0.35),
			math.max(corona.transparency - 0.12, 0)
		)
	end

	local spikes = look.spikes
	if spikes then
		-- A starburst glint (diffraction spikes) over the star.
		emitters.Spikes = glow(
			core,
			"Spikes",
			L.GLINT_TEXTURE,
			math.min(radius * 2 * spikes.scale, maxGlow * 2),
			hex(spikes.color),
			spikes.transparency
		)
	end

	local flareDef = look.flares
	if flareDef then
		for i = 1, 2 do
			local a = Instance.new("Attachment")
			a.Name = `FlareA{i}`
			a.Parent = core
			local b = Instance.new("Attachment")
			b.Name = `FlareB{i}`
			b.Parent = core
			local beam = Instance.new("Beam")
			beam.Name = "Flare"
			beam.Attachment0 = a
			beam.Attachment1 = b
			beam.Texture = L.FLARE_TEXTURE
			beam.TextureMode = Enum.TextureMode.Stretch
			beam.TextureSpeed = 0.6
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Brightness = 3
			beam.FaceCamera = true
			beam.Segments = 12
			beam.Color =
				ColorSequence.new(hex(flareDef.color):Lerp(WHITE, 0.35), hex(flareDef.color))
			beam.Width0 = radius * flareDef.width
			beam.Width1 = radius * flareDef.width
			beam.Transparency = NumberSequence.new(1)
			beam.Enabled = false
			beam.Parent = core
			table.insert(flares, { beam = beam, a = a, b = b, started = 0, active = false })
		end
		if flareDef.burst then
			local sparks = Instance.new("ParticleEmitter")
			sparks.Name = "FlareBurst"
			sparks.Texture = L.SPARKLE_TEXTURE
			sparks.Rate = 0
			sparks.Speed = NumberRange.new(radius * 0.6, radius * 1.4)
			sparks.SpreadAngle = Vector2.new(40, 40)
			sparks.Lifetime = NumberRange.new(0.6, 1.2)
			sparks.Size = NumberSequence.new(radius * 0.08, 0)
			sparks.Color = ColorSequence.new(WHITE, hex(flareDef.color))
			sparks.LightEmission = 1
			sparks.LightInfluence = 0
			sparks.Drag = 1
			sparks.EmissionDirection = Enum.NormalId.Right
			sparks.Parent = flares[1].a
			emitters.FlareBurst = sparks
		end
		nextFlare = rng:NextNumber(0.5, flareDef.every[1])
	end

	local diskDef = look.disk
	if diskDef then
		local group = Instance.new("Model")
		group.Name = "Accretion"
		local outer = localPart(
			"Disk",
			Enum.PartType.Cylinder,
			Vector3.new(0.4, radius * 2 * diskDef.scale, radius * 2 * diskDef.scale),
			hex(diskDef.outer),
			Enum.Material.ForceField,
			group
		)
		outer.Transparency = 0.05
		local inner = localPart(
			"InnerDisk",
			Enum.PartType.Cylinder,
			Vector3.new(0.6, radius * 2 * 1.35, radius * 2 * 1.35),
			hex(diskDef.inner),
			Enum.Material.Neon,
			group
		)
		inner.Transparency = 0.35
		-- Hot clumps orbiting in the disk, so its turning shows.
		for i = 1, 6 do
			local angle = i / 6 * 2 * math.pi
			local r = radius * rng:NextNumber(1.3, diskDef.scale * 0.95)
			local clump = localPart(
				"Clump",
				Enum.PartType.Ball,
				Vector3.new(radius * 0.5, radius * 0.18, radius * 0.5),
				hex(diskDef.inner):Lerp(hex(diskDef.outer), rng:NextNumber()),
				Enum.Material.Neon,
				group
			)
			clump:SetAttribute("Radius", r)
			clump:SetAttribute("Angle", angle)
		end
		group.Parent = folder
		disk = group
	end

	local jetDef = look.jets
	if jetDef then
		for _, sign in { 1, -1 } do
			local a = Instance.new("Attachment")
			a.Name = "JetBase"
			a.Parent = core
			local b = Instance.new("Attachment")
			b.Name = "JetTip"
			b.Parent = core
			local tilt = CFrame.Angles(0, 0, math.rad(if diskDef then diskDef.tilt else 0))
			local axis = tilt:VectorToWorldSpace(Vector3.yAxis) * sign
			a.Position = axis * radius * 0.9
			b.Position = axis * radius * jetDef.length
			local beam = Instance.new("Beam")
			beam.Name = "Jet"
			beam.Attachment0 = a
			beam.Attachment1 = b
			beam.Texture = L.FLARE_TEXTURE
			beam.TextureMode = Enum.TextureMode.Stretch
			beam.TextureSpeed = 2
			beam.TextureLength = 1
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.FaceCamera = true
			beam.Segments = 4
			beam.Width0 = radius * 0.45
			beam.Width1 = radius * 0.08
			beam.Color = ColorSequence.new(WHITE, hex(jetDef.color))
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			})
			beam.Parent = core
		end
	end

	-- A binary star: two stars circling their shared centre (the server's
	-- core, hidden on this client), each with its own corona and light, and
	-- a stream of gas pulled from the second onto the first.
	local binaryDef = look and look.binary
	local twins: { Part } = {}
	local binaryAngle = 0
	if binaryDef then
		core.LocalTransparencyModifier = 1
		for index, def in { binaryDef.a, binaryDef.b } do
			local made = localPart(
				`Twin{index}`,
				Enum.PartType.Ball,
				Vector3.one * radius * 2 * def.size,
				hex(def.color),
				Enum.Material.Neon,
				folder
			)
			local light = Instance.new("PointLight")
			light.Color = hex(def.glow)
			light.Range = math.min(radius * 2.5, 50)
			light.Brightness = 1.5
			light.Shadows = false
			light.Parent = made
			emitters[`TwinGlow{index}`] = glow(
				made,
				`TwinGlow{index}`,
				L.GLOW_TEXTURE,
				radius * 2 * def.size * 2.4,
				hex(def.glow),
				0.55
			)
			table.insert(twins, made)
		end
		local from = Instance.new("Attachment")
		from.Name = "StreamFrom"
		from.Parent = twins[2]
		local to = Instance.new("Attachment")
		to.Name = "StreamTo"
		to.Parent = twins[1]
		local stream = Instance.new("Beam")
		stream.Name = "Stream"
		stream.Attachment0 = from
		stream.Attachment1 = to
		stream.Texture = L.FLARE_TEXTURE
		stream.TextureMode = Enum.TextureMode.Stretch
		stream.TextureSpeed = 1.5
		stream.LightEmission = 1
		stream.LightInfluence = 0
		stream.FaceCamera = true
		stream.Segments = 12
		stream.Width0 = radius * 0.3
		stream.Width1 = radius * 0.12
		stream.Color = ColorSequence.new(hex(binaryDef.stream), hex(binaryDef.a.color))
		stream.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0.85),
		})
		stream.CurveSize0 = radius * 0.5
		stream.CurveSize1 = radius * 0.3
		stream.Parent = twins[2]
	end

	-- Puts the core-following parts where the core is now.
	local function place(cframe: CFrame)
		for _, item in shells do
			item.part.CFrame = cframe * item.offset
		end
		if binaryDef and #twins == 2 then
			local plane = CFrame.new(cframe.Position)
				* CFrame.Angles(math.rad(binaryDef.tilt), 0, 0)
				* CFrame.Angles(0, binaryAngle, 0)
			local a = plane * CFrame.new(radius * binaryDef.distance, 0, 0)
			local b = plane * CFrame.new(-radius * binaryDef.distance, 0, 0)
			twins[1].CFrame = a
			twins[2].CFrame = b
			-- The stream leaves the second star's near side and lands a
			-- little ahead on the first, so it curves like gas spiralling in.
			local toward = (a.Position - b.Position).Unit
			local ahead = plane:VectorToWorldSpace(Vector3.zAxis)
			local from = twins[2]:FindFirstChild("StreamFrom")
			local to = twins[1]:FindFirstChild("StreamTo")
			if from and from:IsA("Attachment") and to and to:IsA("Attachment") then
				local start = b.Position + toward * radius * binaryDef.b.size
				local land = a.Position
					- (toward * 0.8 + ahead * 0.6).Unit * radius * binaryDef.a.size
				from.WorldCFrame = CFrame.lookAt(start, start + toward)
				to.WorldCFrame = CFrame.lookAt(land, a.Position)
			end
		end
		local diskGroup = disk
		if diskGroup and diskDef then
			local plane = CFrame.new(cframe.Position) * CFrame.Angles(0, 0, math.rad(diskDef.tilt))
			for _, part in diskGroup:GetChildren() do
				if part:IsA("BasePart") then
					local r = part:GetAttribute("Radius")
					local angle = part:GetAttribute("Angle")
					if type(r) == "number" and type(angle) == "number" then
						-- Inner clumps go round faster.
						local orbit = angle + spin * (radius * 1.3 / r)
						part.CFrame = plane * CFrame.Angles(0, orbit, 0) * CFrame.new(r, 0, 0)
					else
						part.CFrame = plane * CFrame.Angles(0, 0, math.pi / 2)
					end
				end
			end
		end
	end
	place(core.CFrame)

	local function setLevel(newLevel: number)
		if newLevel == level then
			return
		end
		level = newLevel
		if emitters.Granules then
			emitters.Granules.Enabled = level >= NEAR
		end
		if emitters.Wind then
			emitters.Wind.Enabled = level >= NEAR
		end
		for _, item in shells do
			if item.part.Name == "Plasma" then
				item.part.Transparency = if level >= MID and plasma then plasma.transparency else 1
			end
		end
		if level < MID then
			for _, flare in flares do
				flare.beam.Enabled = false
				flare.active = false
			end
		end
	end

	-- Prominences show best against the sky, so a flare erupts on the star's
	-- edge as this camera sees it (in the core's own space).
	local function startFlare(now: number, camera: Vector3)
		if flareDef == nil then
			return
		end
		local view = core.CFrame:VectorToObjectSpace(camera - core.Position).Unit
		for _, flare in flares do
			if not flare.active then
				local dir = surfaceDirection(rng, math.rad(60))
				dir = (dir - view * dir:Dot(view))
				dir = if dir.Magnitude > 1e-3
					then (dir.Unit + view * 0.12).Unit
					else perpendicular(view)
				local side = perpendicular(dir)
				local spread = rng:NextNumber(0.25, 0.45)
				local pa = (CFrame.fromAxisAngle(side, spread):VectorToWorldSpace(dir)).Unit
				local pb = (CFrame.fromAxisAngle(side, -spread):VectorToWorldSpace(dir)).Unit
				-- Attachment axes point outwards at A and inwards at B, so the
				-- beam's curve rises off the surface between them.
				flare.a.CFrame = CFrame.fromMatrix(pa * radius, pa, side)
				flare.b.CFrame = CFrame.fromMatrix(pb * radius, -pb, side)
				flare.started = now
				flare.active = true
				flare.beam.Enabled = true
				local burst = emitters.FlareBurst
				if burst and level >= NEAR then
					burst.Parent = flare.a
					burst:Emit(14)
				end
				return
			end
		end
	end

	local function stepFlares(now: number, camera: Vector3)
		if flareDef == nil then
			return
		end
		if now >= nextFlare then
			startFlare(now, camera)
			nextFlare = now + rng:NextNumber(flareDef.every[1], flareDef.every[2])
		end
		local height = radius * flareDef.height
		for _, flare in flares do
			if flare.active then
				local t = (now - flare.started) / flareDef.life
				if t >= 1 then
					flare.active = false
					flare.beam.Enabled = false
				else
					-- Rise and brighten, hold, then lift off and fade.
					local rise = math.min(t / 0.3, 1)
					local fade = if t < 0.7 then 0 else (t - 0.7) / 0.3
					local alpha = 1 - (1 - (1 - rise) ^ 2) * (1 - fade)
					local curve = height * (0.3 + 0.7 * rise + 0.4 * fade)
					flare.beam.CurveSize0 = curve
					flare.beam.CurveSize1 = curve
					flare.beam.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, math.min(1, alpha + 0.3)),
						NumberSequenceKeypoint.new(0.5, alpha),
						NumberSequenceKeypoint.new(1, math.min(1, alpha + 0.3)),
					})
				end
			end
		end
	end

	local function step(now: number, dt: number, camera: Vector3, reduced: boolean)
		if now >= nextLod then
			nextLod = now + L.LOD_INTERVAL
			local distance = (camera - core.Position).Magnitude - radius
			local wanted = if distance < L.NEAR then NEAR elseif distance < L.MID then MID else FAR
			if reduced then
				wanted = math.min(wanted, MID)
			end
			setLevel(wanted)
		end
		local cframe = core.CFrame
		local moved = cframe ~= lastCFrame
		lastCFrame = cframe
		if binaryDef then
			binaryAngle += dt * 2 * math.pi / binaryDef.period
			place(cframe)
		end
		if level >= MID then
			spin += look.spin * dt
			if diskDef then
				spin += diskDef.spin * dt
			end
			if disk or moved then
				place(cframe)
			end
			stepFlares(now, camera)
			local coronaGlow = emitters.Corona
			if coronaGlow and corona and corona.pulse then
				coronaGlow.Brightness = 1 + math.sin(now * 1.4) * corona.pulse * 4
			end
		elseif moved then
			place(cframe)
		end
	end

	setLevel(NEAR)

	return {
		typeId = typeId,
		radius = radius,
		step = step,
		destroy = function()
			for _, part in hidden do
				part.LocalTransparencyModifier = 0
			end
			core.Color = serverColor
			core.LocalTransparencyModifier = 0
			for _, emitter in emitters do
				emitter:Destroy()
			end
			for _, flare in flares do
				flare.beam:Destroy()
				flare.a:Destroy()
				flare.b:Destroy()
			end
			for _, child in core:GetChildren() do
				local jet = (child:IsA("Beam") and child.Name == "Jet")
					or (
						child:IsA("Attachment")
						and (
							child.Name == "JetBase"
							or child.Name == "JetTip"
							or child.Name == "StreamTo"
						)
					)
				if jet then
					child:Destroy()
				end
			end
			folder:Destroy()
		end,
	}
end

return StarLook
