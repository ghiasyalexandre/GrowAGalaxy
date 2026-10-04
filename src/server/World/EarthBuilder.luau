--!strict
-- Earth backdrop below the ISS: an ocean sphere, a few land masses that just
-- break its surface, and a thin translucent atmosphere. Visual only; nothing
-- here collides or can be clicked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)

local COLORS = Config.World.COLORS
local MAX_PART_SIZE = 2048

-- Directions (from Earth's centre) of the land masses, mostly on the side that
-- faces the ISS.
local LAND_DIRECTIONS = {
	Vector3.new(0.5, 0.8, 0.2),
	Vector3.new(-0.6, 0.7, -0.3),
	Vector3.new(0.1, 0.9, -0.6),
	Vector3.new(-0.3, 0.75, 0.6),
	Vector3.new(0.85, 0.5, -0.4),
	Vector3.new(-0.9, 0.4, 0.1),
}

local function backdropPart(props: Build.PartProps): Part
	local part = Build.part(props)
	part.CanCollide = false
	part.CanQuery = false
	return part
end

local EarthBuilder = {}

function EarthBuilder.build(): Model
	local model = Build.model("Earth")
	local c = Config.World.EARTH_CENTER
	local center = Vector3.new(c.x, c.y, c.z)
	local diameter = math.min(Config.World.EARTH_DIAMETER, MAX_PART_SIZE)
	local radius = diameter / 2

	backdropPart({
		name = "Ocean",
		shape = Enum.PartType.Ball,
		size = Vector3.one * diameter,
		cframe = CFrame.new(center),
		color = COLORS.earthOcean,
		parent = model,
	})

	-- Each land mass is a large sphere sitting mostly inside the ocean sphere,
	-- poking out by `rise` studs, which leaves a wide, gently domed patch.
	local landRadius = radius * 0.8
	local rise = radius * 0.02
	for index, direction in LAND_DIRECTIONS do
		backdropPart({
			name = `Land{index}`,
			shape = Enum.PartType.Ball,
			size = Vector3.one * landRadius * 2,
			cframe = CFrame.new(center + direction.Unit * (radius - landRadius + rise)),
			color = COLORS.earthLand,
			material = Enum.Material.Grass,
			parent = model,
		})
	end

	backdropPart({
		name = "Atmosphere",
		shape = Enum.PartType.Ball,
		size = Vector3.one * math.min(diameter * 1.024, MAX_PART_SIZE),
		cframe = CFrame.new(center),
		color = COLORS.atmosphere,
		transparency = 0.82,
		parent = model,
	})

	model.WorldPivot = CFrame.new(center)
	return model
end

return EarthBuilder
