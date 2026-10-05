--!strict
-- The Zero G Dodgeball arena (Config.Dodgeball, Logic/DodgeballMath), built
-- once by DodgeballSystem:
--
--   a glass box (solid walls, so balls and players stay in) with a glowing
--   frame along its edges; floating neon cover blocks tagged "DodgeBlock"
--   (players launch off them); spawn markers "Spawn1".."SpawnN"; an exit
--   portal back to the ISS (a WarpPrompt to "Arrival"); and a big sign.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local DodgeballMath = require(ReplicatedStorage.Shared.Logic.DodgeballMath)

local D = Config.Dodgeball
local BLOCK_TAG = "DodgeBlock"
local WALL = 2 -- studs thick
local FRAME_COLOR = "#FFB020"

local DodgeballBuilder = {}

DodgeballBuilder.BLOCK_TAG = BLOCK_TAG

local function vec(point: DodgeballMath.Point): Vector3
	return Vector3.new(point.x, point.y, point.z)
end

function DodgeballBuilder.build(parent: Instance): Model
	local model = Build.model("DodgeballArena", parent)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local center = vec(D.CENTER)
	local size = vec(D.SIZE)

	-- Walls: six glass panels, slightly tinted.
	for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
		for _, side in { -1, 1 } do
			local panel = Vector3.new(
				if axis.X == 1 then WALL else size.X + WALL * 2,
				if axis.Y == 1 then WALL else size.Y + WALL * 2,
				if axis.Z == 1 then WALL else size.Z + WALL * 2
			)
			local offset = axis * side * ((size * axis).Magnitude / 2 + WALL / 2)
			local wall = Build.part({
				name = "Wall",
				size = panel,
				cframe = CFrame.new(center + offset),
				color = "#7FC8FF",
				material = Enum.Material.Glass,
				transparency = 0.82,
				parent = model,
			})
			wall.CastShadow = false
		end
	end

	-- A glowing frame along the twelve edges.
	local half = size / 2
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			Build.part({
				name = "Frame",
				size = Vector3.new(1.5, 1.5, size.Z + 3),
				cframe = CFrame.new(center + Vector3.new(x * half.X, y * half.Y, 0)),
				color = FRAME_COLOR,
				material = Enum.Material.Neon,
				collide = false,
				parent = model,
			})
		end
		for _, z in { -1, 1 } do
			Build.part({
				name = "Frame",
				size = Vector3.new(1.5, size.Y + 3, 1.5),
				cframe = CFrame.new(center + Vector3.new(x * half.X, 0, z * half.Z)),
				color = FRAME_COLOR,
				material = Enum.Material.Neon,
				collide = false,
				parent = model,
			})
		end
	end
	for _, y in { -1, 1 } do
		for _, z in { -1, 1 } do
			Build.part({
				name = "Frame",
				size = Vector3.new(size.X + 3, 1.5, 1.5),
				cframe = CFrame.new(center + Vector3.new(0, y * half.Y, z * half.Z)),
				color = FRAME_COLOR,
				material = Enum.Material.Neon,
				collide = false,
				parent = model,
			})
		end
	end

	-- Cover: glowing blocks, every eighth one lighting its neighbourhood.
	local blocks = Build.model("Blocks", model)
	for index, def in DodgeballMath.blocks() do
		local block = Build.part({
			name = "Block",
			size = vec(def.size),
			cframe = CFrame.new(vec(def.position)),
			color = def.color,
			material = Enum.Material.Neon,
			transparency = 0.2,
			parent = blocks,
		})
		block.CastShadow = false
		CollectionService:AddTag(block, BLOCK_TAG)
		if index % 8 == 0 then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromHex(def.color)
			light.Range = 40
			light.Brightness = 1.5
			light.Shadows = false
			light.Parent = block
		end
	end

	-- Spawn points, and the exit portal beside the first.
	local spawns = DodgeballMath.spawnPoints()
	for index, point in spawns do
		local at = vec(point)
		-- Facing the middle of the arena.
		Build.marker(
			`Spawn{index}`,
			CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z)),
			model
		)
		local pad = Build.part({
			name = "SpawnGlow",
			shape = Enum.PartType.Ball,
			size = Vector3.one * 2,
			cframe = CFrame.new(at - Vector3.new(0, 4, 0)),
			color = FRAME_COLOR,
			material = Enum.Material.Neon,
			collide = false,
			parent = model,
		})
		pad.CastShadow = false
	end
	local first = vec(spawns[1])
	local exitAt = first + Vector3.new(0, 10, 0)
	local exit = Build.part({
		name = "ExitPortal",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.4, 9, 9),
		cframe = CFrame.lookAt(exitAt, center) * CFrame.Angles(0, math.pi / 2, 0),
		color = "#5FE3FF",
		material = Enum.Material.ForceField,
		transparency = 0.1,
		collide = false,
		parent = model,
	})
	exit.CastShadow = false
	Build.prompt(exit, { action = "Back to the ISS", object = "Exit portal", warp = "Arrival" })

	Build.sign({
		name = "ArenaSign",
		text = "ZERO G DODGEBALL\nClick: throw your sun  ·  Shift: launch off a block",
		size = Vector3.new(60, 10, 0.6),
		cframe = CFrame.new(center + Vector3.new(0, half.Y - 10, half.Z - 2))
			* CFrame.Angles(0, math.pi, 0),
		faces = { Enum.NormalId.Front, Enum.NormalId.Back },
		parent = model,
		textColor = FRAME_COLOR,
	}).CanCollide =
		false
	return model
end

return DodgeballBuilder
