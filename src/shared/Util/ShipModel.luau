--!strict
-- Imported ship models: finds a ship's model under ReplicatedStorage/Assets/
-- Ships (see assets/roblox/Ships/README.md) and fits a copy of it to the
-- ship's Config (modelSize, modelYaw). Used by the server's ShipBuilder and
-- the client's Shipyard previews.
--
-- fit() returns a copy whose bounding box is centred on the origin with the
-- nose facing -Z, and the box's size in that frame. Move it with
-- model:PivotTo(target * model:GetPivot()).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ships = require(script.Parent.Parent.Config.Ships)

type ShipDef = Ships.ShipDef

local ShipModel = {}

-- The ship's imported model (a Model or a single MeshPart), or nil.
function ShipModel.find(def: ShipDef): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ships = assets and assets:FindFirstChild("Ships")
	local source = ships and ships:FindFirstChild(def.model)
	if source and (source:IsA("Model") or source:IsA("BasePart")) then
		return source
	end
	return nil
end

-- A fitted copy: the longest horizontal side is def.modelSize studs, shrunk
-- further if needed to fit inside `limit` (studs, nose along Z).
function ShipModel.fit(source: Instance, def: ShipDef, limit: Vector3?): (Model, Vector3)
	local model: Model
	if source:IsA("Model") then
		model = source:Clone()
	else
		model = Instance.new("Model")
		local part = source:Clone()
		part.Parent = model
		model.PrimaryPart = part :: BasePart
	end
	model.Name = "Skin"

	-- A quarter turn swaps the box's width and length.
	local yaw = math.rad(def.modelYaw)
	local quarter = math.abs(math.sin(yaw)) > 0.5
	local function turned(size: Vector3): Vector3
		return if quarter then Vector3.new(size.Z, size.Y, size.X) else size
	end

	local _, raw = model:GetBoundingBox()
	local size = turned(raw)
	local scale = def.modelSize / math.max(size.X, size.Z, 1e-3)
	if limit then
		scale =
			math.min(scale, limit.X / size.X, limit.Y / math.max(size.Y, 1e-3), limit.Z / size.Z)
	end
	model:ScaleTo(model:GetScale() * scale)

	local box, scaled = model:GetBoundingBox()
	local pivotInBox = box:ToObjectSpace(model:GetPivot())
	model:PivotTo(CFrame.Angles(0, yaw, 0) * pivotInBox)
	return model, turned(scaled)
end

-- True for a part that shows its own colours (a texture), so paint must not
-- be applied to it.
function ShipModel.textured(part: BasePart): boolean
	if part:FindFirstChildWhichIsA("SurfaceAppearance") then
		return true
	end
	return part:IsA("MeshPart") and part.TextureID ~= ""
end

return ShipModel
