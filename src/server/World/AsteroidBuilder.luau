--!strict
-- Greybox asteroid: a main rock ball with two smaller lumps for a lumpier
-- silhouette, and a glowing weak point set into the surface. Everything is
-- anchored, so no welds are needed.
--
--   Asteroid_<id>    Model, PrimaryPart = Rock, streams persistently
--                    attributes: AsteroidId, Size, Progress (0 to 1),
--                    ReservedBy (UserId, 0 = free), Broken
--     Rock           Ball, the main body
--     Lump1, Lump2   Balls, part of the rock
--     WeakPoint      Neon ball, non-colliding; hitting it extracts fastest

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local AsteroidConfig = require(ReplicatedStorage.Shared.Config.Asteroids)
local Config = require(ReplicatedStorage.Shared.Config)

local A = Config.Asteroids

export type Parts = {
	model: Model,
	rock: BasePart,
	weakPoint: BasePart,
	parts: { BasePart }, -- every part, the weak point included
}

local AsteroidBuilder = {}

-- A random unit vector. `rng` returns numbers in [0, 1).
local function direction(rng: () -> number): Vector3
	local z = rng() * 2 - 1
	local angle = rng() * 2 * math.pi
	local r = math.sqrt(1 - z * z)
	return Vector3.new(r * math.cos(angle), r * math.sin(angle), z)
end

function AsteroidBuilder.build(
	id: number,
	size: AsteroidConfig.SizeDef,
	position: Vector3,
	rng: () -> number
): Parts
	local model = Build.model(`Asteroid_{id}`)
	-- Always on every client, however far away: asteroids are scattered
	-- further than the default streaming radius, and players need to see
	-- distant ones to find them. About 4 anchored parts each.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("AsteroidId", id)
	model:SetAttribute("Size", size.id)
	model:SetAttribute("Progress", 0)
	model:SetAttribute("ReservedBy", 0)
	model:SetAttribute("Broken", false)

	local colors = A.ROCK_COLORS
	local color = colors[math.floor(rng() * #colors) + 1]
	local radius = size.radius
	local parts: { BasePart } = {}

	local rock = Build.part({
		name = "Rock",
		size = Vector3.one * radius * 2,
		cframe = CFrame.new(position),
		color = color,
		material = Enum.Material.Slate,
		shape = Enum.PartType.Ball,
		parent = model,
	})
	table.insert(parts, rock)
	model.PrimaryPart = rock

	-- Lumps go on the far side from the weak point so they never hide it.
	local weakDirection = direction(rng)
	for index = 1, 2 do
		local lumpRadius = radius * (0.45 + rng() * 0.2)
		local lumpDirection = direction(rng)
		if lumpDirection:Dot(weakDirection) > 0 then
			lumpDirection = -lumpDirection
		end
		local lump = Build.part({
			name = `Lump{index}`,
			size = Vector3.one * lumpRadius * 2,
			cframe = CFrame.new(position + lumpDirection * radius * 0.7),
			color = color,
			material = Enum.Material.Slate,
			shape = Enum.PartType.Ball,
			parent = model,
		})
		table.insert(parts, lump)
	end

	-- Set into the main rock's surface, bulging out of it.
	local weakRadius = size.weakPointRadius
	local weakPoint = Build.part({
		name = "WeakPoint",
		size = Vector3.one * weakRadius * 2,
		cframe = CFrame.new(position + weakDirection * (radius - weakRadius * 0.35)),
		color = A.WEAK_POINT_COLOR,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Ball,
		collide = false,
		parent = model,
	})
	table.insert(parts, weakPoint)

	return { model = model, rock = rock, weakPoint = weakPoint, parts = parts }
end

return AsteroidBuilder
