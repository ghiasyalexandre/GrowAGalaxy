--!strict
-- The UI art: one atlas (assets/ui/GaG_UI_Atlas.png) packed from the UI kit
-- in assets/grow_a_galaxy_ui_assets by tools/pack_ui_atlas.py, which also
-- writes the sprite rects and 9-slice centres (Config/SpriteAtlas).
--
-- Roblox can't load images from the project folder: upload GaG_UI_Atlas.png
-- (Studio > Asset Manager > Images > Bulk Import, or the Creator Hub) and put
-- its id in IMAGE as "rbxassetid://<id>". Until then IMAGE is nil and the UI
-- draws its plain look (Theme's gradients). Re-running the packer changes the
-- atlas, so it then needs uploading again.
--
-- Sprites: icons (Stardust, Ship, Mining, StarPlus, PlanetUp, Galaxy, Medal,
-- Gear, Play, Close, Info, LevelUp, Shop, Chest, OpenChest, CoinPile, Gift,
-- Energy, Rocket, Station, Telescope, Shield, Portal, RainbowStar, Moon,
-- Earth, RingedPlanet, PlanetPurple, GalaxyOrb, CrystalPurple, CrystalBlue),
-- buttons (ButtonBlue, ButtonGold, ButtonPurple, ButtonDark), panels
-- (PanelHud with the Stardust art, PanelSpace, PanelTall, PanelSmall) and
-- bars (TrackCyan/FillCyan, TrackHeat/FillHeat).

local SpriteAtlas = require(script.Parent.SpriteAtlas)

export type Rect = SpriteAtlas.Rect
export type SpriteDef = SpriteAtlas.SpriteDef

return {
	IMAGE = "rbxassetid://88113805122624" :: string?,
	SHEET_WIDTH = SpriteAtlas.WIDTH,
	SHEET_HEIGHT = SpriteAtlas.HEIGHT,
	SPRITES = SpriteAtlas.SPRITES,
	-- How big a panel's frame art is drawn (1 = atlas pixels).
	PANEL_SLICE_SCALE = 0.55,
}
