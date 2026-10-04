--!strict
-- Visible boundary of a player's galaxy region: its twelve box edges, drawn in
-- the slot's colour. See Logic/RegionMath for the region coordinate system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)

local RegionBuilder = {}

-- Rebuilds the "Bounds" model inside `region` for the given size.
function RegionBuilder.buildBounds(region: Model, origin: CFrame, size: Vector3, color: string)
	local existing = region:FindFirstChild("Bounds")
	if existing then
		existing:Destroy()
	end
	local bounds = Build.model("Bounds", region)
	local t = Config.World.REGION_EDGE_THICKNESS
	local hw, hh, d = size.X / 2, size.Y / 2, size.Z

	local function edge(edgeSize: Vector3, offset: Vector3)
		local part = Build.part({
			name = "Edge",
			size = edgeSize,
			cframe = origin * CFrame.new(offset),
			color = color,
			material = Enum.Material.Neon,
			transparency = 0.4,
			collide = false,
			parent = bounds,
		})
		part.CanQuery = false
	end

	for _, y in { -hh, hh } do
		for _, z in { 0, d } do
			edge(Vector3.new(size.X, t, t), Vector3.new(0, y, z))
		end
	end
	for _, x in { -hw, hw } do
		for _, z in { 0, d } do
			edge(Vector3.new(t, size.Y, t), Vector3.new(x, 0, z))
		end
	end
	for _, x in { -hw, hw } do
		for _, y in { -hh, hh } do
			edge(Vector3.new(t, t, d), Vector3.new(x, y, d / 2))
		end
	end
end

return RegionBuilder
