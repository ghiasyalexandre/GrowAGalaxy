--!strict
-- Images cut from the UI sprite sheet (Config.Sprites). Every function
-- returns nil, or does nothing, while Config.Sprites.IMAGE is unset, so
-- callers keep their plain look until the sheet is uploaded.
--
--   enabled()                       is the sheet available?
--   icon(parent, name, size)        a square icon, scaled to fit
--   skin(target, name, scale?)      a 9-slice background behind target's
--                                   children; target's own background,
--                                   gradient and stroke are switched off.
--                                   Without `scale`, the frame art is sized
--                                   to target's height.
--   panelSkin(target)               a panel frame, wide or large by shape
--   set(image, name)                switch an icon to another sprite
--   tint(target, color)             recolour a skin (multiplies its colours)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local SpritesConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sprites"))

local CFG = Config.Sprites
local WIDE_ASPECT = 3.2 -- panels at least this wide for their height use PanelWide

local Sprites = {}

function Sprites.enabled(): boolean
	return CFG.IMAGE ~= nil
end

-- Points `image` at a sprite (rect, and slicing for 9-slice sprites).
local function apply(image: ImageLabel, def: SpritesConfig.SpriteDef)
	image.Image = CFG.IMAGE :: string
	image.ImageRectOffset = Vector2.new(def.x, def.y)
	image.ImageRectSize = Vector2.new(def.w, def.h)
	local cut = def.slice
	if cut then
		image.ScaleType = Enum.ScaleType.Slice
		image.SliceCenter = Rect.new(cut.x0, cut.y0, cut.x1, cut.y1)
	else
		image.ScaleType = Enum.ScaleType.Fit
	end
end

local function newImage(name: string, def: SpritesConfig.SpriteDef): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	apply(image, def)
	return image
end

function Sprites.icon(parent: Instance, name: string, size: number): ImageLabel?
	local def = CFG.SPRITES[name]
	if CFG.IMAGE == nil or def == nil then
		return nil
	end
	local image = newImage(`Icon_{name}`, def)
	image.Size = UDim2.fromOffset(size, size)
	image.Parent = parent
	return image
end

-- Switches off what would draw over or instead of the skin.
local function hideOwnLook(target: GuiObject)
	target.BackgroundTransparency = 1
	for _, child in target:GetChildren() do
		if child:IsA("UIStroke") or child:IsA("UIGradient") then
			-- Both classes have Enabled; the type checker can't see it on the union.
			(child :: any).Enabled = false
		end
	end
end

function Sprites.skin(target: GuiObject, name: string, scale: number?): ImageLabel?
	local def = CFG.SPRITES[name]
	if CFG.IMAGE == nil or def == nil then
		return nil
	end
	hideOwnLook(target)
	local image = newImage("Skin", def)
	-- Cover the whole target even when a UIPadding shrinks its content box.
	local padding = target:FindFirstChildOfClass("UIPadding")
	local left = if padding then padding.PaddingLeft.Offset else 0
	local right = if padding then padding.PaddingRight.Offset else 0
	local top = if padding then padding.PaddingTop.Offset else 0
	local bottom = if padding then padding.PaddingBottom.Offset else 0
	image.Position = UDim2.fromOffset(-left, -top)
	image.Size = UDim2.new(1, left + right, 1, top + bottom)
	image.ZIndex = 0
	image.Parent = target
	local function fit()
		image.SliceScale = scale or math.clamp(target.AbsoluteSize.Y / math.max(def.h, 1), 0.05, 1)
	end
	fit()
	if scale == nil then
		target:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	end
	return image
end

function Sprites.panelSkin(target: GuiObject): ImageLabel?
	local image = Sprites.skin(target, "PanelLarge", CFG.PANEL_SLICE_SCALE)
	if image == nil then
		return nil
	end
	local skin = image
	local function fit()
		local size = target.AbsoluteSize
		local name = if size.X >= size.Y * WIDE_ASPECT then "PanelWide" else "PanelLarge"
		local def = CFG.SPRITES[name]
		apply(skin, def)
		-- Never let the corners take more than the panel's height.
		skin.SliceScale = math.min(CFG.PANEL_SLICE_SCALE, size.Y / math.max(def.h, 1))
	end
	fit()
	target:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	return skin
end

-- Points an existing sprite image at another sprite.
function Sprites.set(image: ImageLabel, name: string)
	local def = CFG.SPRITES[name]
	if CFG.IMAGE ~= nil and def ~= nil then
		apply(image, def)
	end
end

function Sprites.tint(target: Instance, color: Color3)
	local skin = target:FindFirstChild("Skin")
	if skin and skin:IsA("ImageLabel") then
		skin.ImageColor3 = color
	end
end

return Sprites
