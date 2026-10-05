--!strict
-- A ship's paint job (Config.Paint) on a built ship model: the server's
-- spawned ships and showcase displays, and the client's Shipyard previews.
--
--   mark(model, factoryPaint)  once, right after building: remembers each
--                              part's factory colour, material and shine, and
--                              which parts take paint ("GaG_Paintable":
--                              plain hull panels) or a tinted texture
--                              ("GaG_Tintable": textured imported meshes).
--   apply(model, look)         paints and finishes it. Plain parts change
--                              colour here; textured ones are tinted by each
--                              client (Fx/TextureTint) from the model's
--                              "Tint" attribute, set here. A nil paint or
--                              finish puts the factory one back.

local Config = require(script.Parent.Parent.Config)
local ShipModel = require(script.Parent.ShipModel)

local PAINTABLE = "GaG_Paintable"
local TINTABLE = "GaG_Tintable"

export type Look = { paint: string?, finish: string? }

local ShipLook = {}

ShipLook.TINTABLE = TINTABLE
-- Models wearing a look carry this tag, so every client tints them.
ShipLook.TAG = "GaG_ShipLook"

-- `paintParts` are the parts that wear the ship's factory paint colour.
function ShipLook.mark(model: Model, paintParts: { BasePart })
	for _, part in paintParts do
		part:SetAttribute(PAINTABLE, true)
	end
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part.Transparency >= 1 then
			continue
		end
		local textured = ShipModel.textured(part)
		if textured then
			part:SetAttribute(TINTABLE, true)
		end
		if textured or part:GetAttribute(PAINTABLE) then
			part:SetAttribute("GaG_FactoryPaint", part.Color)
			part:SetAttribute("GaG_FactoryMaterial", part.Material.Name)
			part:SetAttribute("GaG_FactoryShine", part.Reflectance)
		end
	end
end

function ShipLook.apply(model: Model, look: Look)
	local paint = if look.paint then Color3.fromHex(look.paint) else nil
	local finish = if look.finish then Config.Paint.FINISHES[look.finish] else nil
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local factory = part:GetAttribute("GaG_FactoryPaint")
		if typeof(factory) ~= "Color3" then
			continue
		end
		if part:GetAttribute(PAINTABLE) then
			part.Color = paint or factory
		end
		local material = if finish
			then finish.material
			else part:GetAttribute("GaG_FactoryMaterial")
		local enum = if type(material) == "string" then (Enum.Material :: any)[material] else nil
		if enum then
			part.Material = enum
		end
		local shine = if finish then finish.reflectance else part:GetAttribute("GaG_FactoryShine")
		part.Reflectance = if type(shine) == "number" then shine else 0
	end
	model:SetAttribute("Tint", look.paint)
	model:SetAttribute("Finish", look.finish)
end

return ShipLook
