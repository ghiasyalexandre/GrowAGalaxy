--!strict
-- A placed star. The server builds only the star itself; each client adds
-- its planets and their orbits from the Level attribute (StarController).
--
--   Star_<id>     Model, PrimaryPart = Core, streams persistently
--                 attributes: StarId, OwnerUserId, TypeId, Level, Income
--     Core        Neon ball, sized by level, with a PointLight
--       Manage    ProximityPrompt tagged "TycoonPrompt", TycoonAction = "Manage"

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local StarMath = require(ReplicatedStorage.Shared.Logic.StarMath)
local Types = require(ReplicatedStorage.Shared.Types)

local S = Config.Stars

local StarBuilder = {}

-- Updates size, colour and attributes after a level change.
function StarBuilder.apply(model: Model, star: Types.StarRecord)
	local def = S.BY_ID[star.typeId] or S.BY_ID[S.DEFAULT_TYPE]
	local levelDef = StarMath.levelDef(def.id, star.level)
	local radius = if levelDef then levelDef.starRadius else 18
	local core = model.PrimaryPart
	if core then
		core.Size = Vector3.one * radius * 2
		core.Color = Color3.fromHex(def.color)
		local light = core:FindFirstChildOfClass("PointLight")
		if light then
			light.Range = math.min(radius * 3, 60)
		end
	end
	model:SetAttribute("TypeId", def.id)
	model:SetAttribute("Level", star.level)
	model:SetAttribute("Income", StarMath.income(def.id, star.level))
end

function StarBuilder.build(
	id: string,
	star: Types.StarRecord,
	cframe: CFrame,
	ownerUserId: number
): Model
	local model = Build.model(`Star_{id}`)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("StarId", id)
	model:SetAttribute("OwnerUserId", ownerUserId)

	local core = Build.part({
		name = "Core",
		size = Vector3.one * 36,
		cframe = cframe,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Ball,
		collide = false,
		parent = model,
	})
	model.PrimaryPart = core

	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 230, 170)
	light.Parent = core

	local prompt =
		Build.prompt(core, { action = "Manage star", object = "Your star", tycoon = "Manage" })
	prompt.Name = "Manage"
	prompt.MaxActivationDistance = S.MANAGE_DISTANCE
	prompt:SetAttribute("StarId", id)

	StarBuilder.apply(model, star)
	return model
end

return StarBuilder
