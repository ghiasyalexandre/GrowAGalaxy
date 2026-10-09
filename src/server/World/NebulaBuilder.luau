--!strict
-- The Helix Nebula backdrop far below the ISS (Config.World.NEBULA), seen
-- face-on from above like the "Eye of God". Visual only: nothing here
-- collides or can be clicked.
--
-- It's painted (tools/nebula/helix.py) as four transparent image layers,
-- each on an invisible flat part stacked a little above the one below, so
-- the nebula has depth and parallax as you fly over it: the red outer halo
-- and ring, the fiery inner ring with its cometary knots, the blue-teal
-- core and the star's glow. The layers turn very slowly, each at its own
-- speed and direction (SpinController), so the gas seems to drift. At the
-- centre burns the white dwarf, and drifting clouds of glowing gas hang
-- over the rings (particles, drawn by each client) for a sense of volume.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)
local WorldConfig = require(ReplicatedStorage.Shared.Config.World)

local N = Config.World.NEBULA
local SPIN_TAG = "GaG_Spin"
-- Gas clouds: how many emitters on each ring, its radius (share of the
-- nebula's size), height above the bottom layer and colours.
local CLOUDS = {
	{ count = 6, radius = 0.17, height = 75, colors = { "#5FC8E8", "#8FE8D8" } },
	{ count = 8, radius = 0.26, height = 55, colors = { "#FF8A3D", "#FFC060" } },
	{ count = 10, radius = 0.42, height = 25, colors = { "#E0402F", "#FF6A3D" } },
}

local NebulaBuilder = {}

local function spin(instance: Instance, speed: number)
	instance:SetAttribute("SpinSpeed", speed)
	CollectionService:AddTag(instance, SPIN_TAG)
end

-- One image layer, N.SIZE across. A Part can be at most 2048 studs, so the
-- layer is a Model of 2 x 2 flat tiles, each showing its quarter of the
-- image, turning together about the centre. On a Top-face SurfaceGui the
-- image's u axis runs towards the part's -Z and its v axis towards +X
-- (checked in Studio), so the tile centred at (ox, oz) shows the region
-- from u = 0.5 - (oz + S/4)/S, v = 0.5 + (ox - S/4)/S.
local function layer(model: Model, centre: Vector3, def: WorldConfig.NebulaLayer)
	local holder = Build.model(def.name, model)
	local at = centre + Vector3.new(0, def.height, 0)
	local size = N.SIZE
	local half = size / 2
	for _, ox in { -size / 4, size / 4 } do
		for _, oz in { -size / 4, size / 4 } do
			local part = Build.part({
				name = "Tile",
				size = Vector3.new(half, 0.2, half),
				cframe = CFrame.new(at + Vector3.new(ox, 0, oz)),
				transparency = 1,
				collide = false,
				parent = holder,
			})
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Image"
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
			gui.CanvasSize = Vector2.new(512, 512)
			gui.ClipsDescendants = true
			gui.LightInfluence = 0
			gui.Brightness = def.brightness
			gui.Parent = part
			local u0 = 0.5 - (oz + size / 4) / size
			local v0 = 0.5 + (ox - size / 4) / size
			local image = Instance.new("ImageLabel")
			image.BackgroundTransparency = 1
			image.Size = UDim2.fromScale(2, 2)
			image.Position = UDim2.fromScale(-2 * u0, -2 * v0)
			image.Image = def.image
			image.ImageTransparency = def.transparency
			image.Parent = gui
		end
	end
	holder.WorldPivot = CFrame.new(at)
	spin(holder, def.spin)
end

local function cloud(model: Model, at: Vector3, colors: { string }, index: number)
	local holder = Build.part({
		name = "GasCloud",
		size = Vector3.one,
		cframe = CFrame.new(at),
		transparency = 1,
		collide = false,
		parent = model,
	})
	holder.CanQuery = false
	holder.CanTouch = false
	local gas = Instance.new("ParticleEmitter")
	gas.Rate = 0.25
	gas.Lifetime = NumberRange.new(30, 45)
	gas.Speed = NumberRange.new(1, 4)
	gas.SpreadAngle = Vector2.new(180, 180)
	gas.Rotation = NumberRange.new(0, 360)
	gas.RotSpeed = NumberRange.new(-3, 3)
	gas.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 80),
		NumberSequenceKeypoint.new(0.5, 160),
		NumberSequenceKeypoint.new(1, 220),
	})
	gas.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.86),
		NumberSequenceKeypoint.new(0.7, 0.88),
		NumberSequenceKeypoint.new(1, 1),
	})
	gas.Color = ColorSequence.new(Color3.fromHex(colors[1]), Color3.fromHex(colors[2]))
	gas.LightEmission = 0.6
	gas.LightInfluence = 0
	gas.Texture = "rbxasset://textures/particles/smoke_main.dds"
	-- Staggered so the clouds don't all breathe in step.
	gas.Rate = 0.2 + (index % 3) * 0.05
	gas.Parent = holder
end

function NebulaBuilder.build(): Model
	local model = Build.model("Nebula")
	local c = N.CENTER
	local centre = Vector3.new(c.x, c.y, c.z)

	for _, def in N.LAYERS do
		layer(model, centre, def)
	end

	-- The white dwarf: a hot blue-white star, its light, and a soft halo.
	local starAt = centre + Vector3.new(0, N.STAR_HEIGHT, 0)
	local star = Build.part({
		name = "WhiteDwarf",
		shape = Enum.PartType.Ball,
		size = Vector3.one * 26,
		cframe = CFrame.new(starAt),
		color = "#E8F4FF",
		material = Enum.Material.Neon,
		collide = false,
		parent = model,
	})
	star.CanQuery = false
	star.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("#BFE4FF")
	light.Range = 60
	light.Brightness = 3
	light.Shadows = false
	light.Parent = star
	local corona = Instance.new("ParticleEmitter")
	corona.Rate = 3
	corona.Lifetime = NumberRange.new(2, 3)
	corona.Speed = NumberRange.new(0)
	corona.LockedToPart = true
	corona.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 40),
		NumberSequenceKeypoint.new(1, 90),
	})
	corona.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	corona.Color = ColorSequence.new(Color3.fromHex("#CFEFFF"))
	corona.LightEmission = 1
	corona.LightInfluence = 0
	corona.Parent = star

	-- Glowing gas clouds over the core and both rings.
	for _, ring in CLOUDS do
		for index = 1, ring.count do
			local angle = (index + ring.radius * 7) / ring.count * 2 * math.pi
			local radius = N.SIZE * ring.radius * (0.9 + 0.2 * ((index * 37) % 10) / 10)
			cloud(
				model,
				centre
					+ Vector3.new(math.cos(angle) * radius, ring.height, math.sin(angle) * radius),
				ring.colors,
				index
			)
		end
	end

	model.WorldPivot = CFrame.new(centre)
	return model
end

return NebulaBuilder
