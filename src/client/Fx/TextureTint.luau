--!strict
-- Recolours a textured ship mesh on this client: the texture is loaded into
-- an EditableImage, turned to greyscale (brightest pixel = white) and
-- multiplied by the paint colour, keeping a floor of Config.Paint.TINT_FLOOR
-- so dark coats still show their panel lines. Results are cached per texture
-- and colour, so ten ships of one kind share one image.
--
-- Where EditableImage isn't available (the experience hasn't enabled it, or
-- the texture can't be read), the part drops its texture and takes the
-- colour as a plain coat instead. tint(part, nil) restores the original.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local FLOOR = Config.Paint.TINT_FLOOR
local ORIGINAL = "GaG_FactoryTexture"
local ORIGINAL_COLOR = "GaG_FactoryColor"

local TextureTint = {}

local cache: { [string]: Content } = {}
local failed: { [string]: boolean } = {}

-- A tinted copy of the texture at `uri`, or nil when it can't be made.
local function tinted(uri: string, color: Color3): Content?
	local key = `{uri}|{color:ToHex()}`
	local cached = cache[key]
	if cached then
		return cached
	end
	if failed[uri] then
		return nil
	end
	local ok, image = pcall(function()
		-- selene: allow(undefined_variable)
		return AssetService:CreateEditableImageAsync(Content.fromUri(uri))
	end)
	if not ok or image == nil then
		failed[uri] = true
		return nil
	end
	local size = image.Size
	local pixels = image:ReadPixelsBuffer(Vector2.zero, size)
	local count = size.X * size.Y
	-- Greyscale, scaled so the brightest pixel becomes white.
	local brightest = 1e-3
	for i = 0, count - 1 do
		local r = buffer.readu8(pixels, i * 4)
		local g = buffer.readu8(pixels, i * 4 + 1)
		local b = buffer.readu8(pixels, i * 4 + 2)
		brightest = math.max(brightest, 0.299 * r + 0.587 * g + 0.114 * b)
	end
	local cr, cg, cb = color.R * 255, color.G * 255, color.B * 255
	for i = 0, count - 1 do
		local r = buffer.readu8(pixels, i * 4)
		local g = buffer.readu8(pixels, i * 4 + 1)
		local b = buffer.readu8(pixels, i * 4 + 2)
		local shade = FLOOR + (1 - FLOOR) * (0.299 * r + 0.587 * g + 0.114 * b) / brightest
		buffer.writeu8(pixels, i * 4, math.clamp(math.floor(cr * shade + 0.5), 0, 255))
		buffer.writeu8(pixels, i * 4 + 1, math.clamp(math.floor(cg * shade + 0.5), 0, 255))
		buffer.writeu8(pixels, i * 4 + 2, math.clamp(math.floor(cb * shade + 0.5), 0, 255))
	end
	image:WritePixelsBuffer(Vector2.zero, size, pixels)
	-- selene: allow(undefined_variable)
	local content = Content.fromObject(image)
	cache[key] = content
	return content
end

-- Paints `part` (a textured MeshPart) `color`, or restores its factory
-- texture when `color` is nil. Yields while a texture loads.
function TextureTint.tint(part: MeshPart, color: Color3?)
	local original = part:GetAttribute(ORIGINAL)
	if type(original) ~= "string" then
		original = part.TextureID
		part:SetAttribute(ORIGINAL, original)
		part:SetAttribute(ORIGINAL_COLOR, part.Color)
	end
	local uri = original :: string
	if color == nil then
		part.TextureID = uri
		local factory = part:GetAttribute(ORIGINAL_COLOR)
		if typeof(factory) == "Color3" then
			part.Color = factory
		end
		return
	end
	local content = if uri ~= "" then tinted(uri, color) else nil
	if content then
		part.TextureContent = content
	else
		-- No EditableImage: a plain coat of the colour.
		part.TextureID = ""
		part.Color = color
	end
end

return TextureTint
