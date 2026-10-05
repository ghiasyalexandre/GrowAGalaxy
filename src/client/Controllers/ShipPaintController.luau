--!strict
-- Tints the textured parts of every painted ship on this client: spawned
-- ships and Showcase Dock displays (models tagged by Util/ShipLook, with a
-- "Tint" colour attribute; none = factory texture). The server already
-- painted the plain parts and set the finish; textures can only be recoloured
-- per client (Fx/TextureTint).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TextureTint = require(script.Parent.Parent.Fx.TextureTint)

local ShipLook =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("ShipLook"))

local ShipPaintController = {}

-- Applies the model's current Tint to its textured parts.
function ShipPaintController.paint(model: Instance)
	local tint = model:GetAttribute("Tint")
	local color = if type(tint) == "string" then Color3.fromHex(tint) else nil
	for _, part in model:GetDescendants() do
		if part:IsA("MeshPart") and part:GetAttribute(ShipLook.TINTABLE) then
			task.spawn(TextureTint.tint, part, color)
		end
	end
end

local function watch(model: Instance)
	ShipPaintController.paint(model)
	model:GetAttributeChangedSignal("Tint"):Connect(function()
		ShipPaintController.paint(model)
	end)
end

function ShipPaintController.init() end

function ShipPaintController.start()
	for _, model in CollectionService:GetTagged(ShipLook.TAG) do
		watch(model)
	end
	CollectionService:GetInstanceAddedSignal(ShipLook.TAG):Connect(watch)
end

return ShipPaintController
