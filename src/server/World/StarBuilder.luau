--!strict
-- A placed star. The server builds the star itself; each client draws its
-- planets and orbits from the Planets attribute (StarController).
--
--   Star_<id>     Model, PrimaryPart = Core, streams persistently
--                 attributes: StarId, OwnerUserId, TypeId, Level, Income
--                 (star plus planets in orbit), Orbits (open slots),
--                 Planets ("Basalt,,Aurora," planet type by orbit slot),
--                 PlanetLevels ("3,,1,")
--     Core        Neon ball in the type's colour, with a PointLight
--       Manage    ProximityPrompt tagged "TycoonPrompt", TycoonAction = "Manage"
--     Disk        Black holes only: a glowing accretion disk
--     Corona      Giants and supergiants: a faint outer glow

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local StarMath = require(ReplicatedStorage.Shared.Logic.StarMath)
local Types = require(ReplicatedStorage.Shared.Types)

local S = Config.Stars
local BLACK_HOLE = "BlackHole"
local DISK_COLOR = "#FF9A3D"
-- Types that get a corona (tier 5 and up, except the black hole).
local CORONA_TIER = 5

local StarBuilder = {}

local function extra(model: Model, name: string): BasePart?
	local part = model:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

local function makeExtra(
	model: Model,
	name: string,
	shape: Enum.PartType,
	color: string,
	transparency: number
): Part
	local core = model.PrimaryPart :: BasePart
	local part = Build.part({
		name = name,
		size = Vector3.one,
		cframe = core.CFrame,
		color = color,
		material = Enum.Material.Neon,
		shape = shape,
		transparency = transparency,
		collide = false,
		parent = model,
	})
	part.CanQuery = false
	return part
end

-- Updates looks and attributes after any change (type, level, planets).
-- `equipped` is the star's planets by orbit slot.
function StarBuilder.apply(
	model: Model,
	star: Types.StarRecord,
	equipped: { [number]: Types.PlanetRecord }
)
	local def = S.BY_ID[star.typeId] or S.BY_ID[S.DEFAULT_TYPE]
	local radius = StarMath.radius(def.id, star.level)
	local core = model.PrimaryPart
	if core then
		core.Size = Vector3.one * radius * 2
		core.Color = Color3.fromHex(def.color)
		local light = core:FindFirstChildOfClass("PointLight")
		if light then
			light.Color = Color3.fromHex(def.light)
			light.Range = math.min(radius * 3, 60)
			light.Brightness = if def.id == BLACK_HOLE then 4 else 2
		end

		-- Black hole: a tilted accretion disk around the dark core.
		local disk = extra(model, "Disk")
		if def.id == BLACK_HOLE then
			disk = disk or makeExtra(model, "Disk", Enum.PartType.Cylinder, DISK_COLOR, 0.25)
			local d = disk :: BasePart
			d.Size = Vector3.new(0.6, radius * 4.2, radius * 4.2)
			d.CFrame = CFrame.new(core.Position) * CFrame.Angles(0, 0, math.rad(90 - 12))
		elseif disk then
			disk:Destroy()
		end

		-- Giants: a faint glow around the star.
		local corona = extra(model, "Corona")
		if def.tier >= CORONA_TIER and def.id ~= BLACK_HOLE then
			corona = corona or makeExtra(model, "Corona", Enum.PartType.Ball, def.light, 0.8)
			local c = corona :: BasePart
			c.Size = Vector3.one * radius * 2.5
			c.Color = Color3.fromHex(def.light)
			c.CFrame = CFrame.new(core.Position)
		elseif corona then
			corona:Destroy()
		end
	end
	model:SetAttribute("TypeId", def.id)
	model:SetAttribute("Level", star.level)
	model:SetAttribute("Income", StarMath.income(star, equipped))
	model:SetAttribute("Orbits", StarMath.slots(def.id))
	model:SetAttribute("Planets", StarMath.encodePlanets(equipped))
	model:SetAttribute("PlanetLevels", StarMath.encodePlanetLevels(equipped))
end

function StarBuilder.build(
	id: string,
	star: Types.StarRecord,
	cframe: CFrame,
	ownerUserId: number,
	equipped: { [number]: Types.PlanetRecord }
): Model
	local model = Build.model(`Star_{id}`)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("StarId", id)
	model:SetAttribute("OwnerUserId", ownerUserId)

	local core = Build.part({
		name = "Core",
		size = Vector3.one * 24,
		cframe = cframe,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Ball,
		collide = false,
		parent = model,
	})
	model.PrimaryPart = core

	local light = Instance.new("PointLight")
	light.Parent = core

	local prompt =
		Build.prompt(core, { action = "Manage star", object = "Your star", tycoon = "Manage" })
	prompt.Name = "Manage"
	prompt.MaxActivationDistance = S.MANAGE_DISTANCE
	prompt:SetAttribute("StarId", id)

	StarBuilder.apply(model, star, equipped)
	return model
end

return StarBuilder
