--!strict
-- The UI sprite sheet (assets/ui/GaG_SpriteSheet_1024.png): icons, button
-- skins, panel frames and progress bars, cut out with ImageRectOffset/Size.
--
-- Roblox can't load images from the project folder: upload
-- GaG_SpriteSheet_1024.png (Studio > Asset Manager > Images > Bulk Import, or
-- the Creator Hub) and put its id in IMAGE as "rbxassetid://<id>". Until then
-- IMAGE is nil and the UI draws its plain look (Theme's gradients).
--
-- Rects are in pixels of the 1024 x 768 sheet (upload it at that size; Roblox
-- downscales anything above 1024). `slice` is the stretchable centre of a
-- 9-slice sprite, relative to the sprite's own rect.

export type Rect = { x0: number, y0: number, x1: number, y1: number }
export type SpriteDef = { x: number, y: number, w: number, h: number, slice: Rect? }

local function sprite(x: number, y: number, w: number, h: number, slice: Rect?): SpriteDef
	return { x = x, y = y, w = w, h = h, slice = slice }
end

local function slice(x0: number, y0: number, x1: number, y1: number): Rect
	return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

local SPRITES: { [string]: SpriteDef } = {
	-- Icons
	Stardust = sprite(55, 30, 180, 175),
	Ship = sprite(270, 31, 256, 163),
	Laser = sprite(536, 21, 226, 187),
	StarPlus = sprite(783, 24, 199, 180),
	PlanetUp = sprite(42, 216, 201, 184),
	Galaxy = sprite(301, 218, 200, 181),
	Medal = sprite(542, 219, 189, 177),
	Gear = sprite(793, 218, 186, 184),
	-- Buttons (the glowing side tabs sit in the corners, so they never stretch)
	ButtonBlue = sprite(18, 407, 239, 91, slice(70, 44, 167, 47)),
	ButtonPurple = sprite(271, 407, 235, 91, slice(70, 44, 163, 47)),
	ButtonGold = sprite(520, 407, 240, 90, slice(70, 44, 168, 46)),
	ButtonDark = sprite(774, 409, 232, 86, slice(70, 42, 160, 44)),
	-- Panels: wide (banners, toasts, wallet) and large (shop windows)
	PanelWide = sprite(21, 539, 512, 117, slice(145, 80, 367, 84)),
	PanelLarge = sprite(556, 503, 431, 167, slice(142, 109, 289, 111)),
	-- Progress bars: dark tracks and glowing fills
	TrackGrey = sprite(35, 687, 242, 54, slice(30, 26, 212, 28)),
	FillCyan = sprite(283, 687, 229, 57, slice(24, 27, 205, 30)),
	TrackOrange = sprite(522, 686, 239, 57, slice(34, 27, 205, 30)),
	FillOrange = sprite(768, 686, 226, 55, slice(24, 26, 202, 29)),
}

return {
	IMAGE = nil :: string?, -- "rbxassetid://<id>" once uploaded
	SHEET_WIDTH = 1024,
	SHEET_HEIGHT = 768,
	SPRITES = SPRITES,
	-- How big a panel's frame art is drawn (1 = sheet pixels).
	PANEL_SLICE_SCALE = 0.5,
}
