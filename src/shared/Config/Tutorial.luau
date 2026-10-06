--!strict
-- The new-player tutorial: one step at a time on a card at the top of the
-- screen (TutorialController), written so young players can follow it:
-- a short title and one short line (at most MAX_TEXT letters) per step.
--
-- A step is done once its stat (profile.stats) is at least 1; the card shows
-- the first step not done yet, so steps the player already did are skipped.
-- `ack` steps have no gameplay stat of their own: the player presses Next
-- (or, with `auto`, the client notices them moving or flying) and the server
-- counts the stat (TutorialSystem). Finishing the `final` step pays
-- FINISH_REWARD once; skipping the tutorial pays nothing.
--
-- `text` is for keyboard and mouse; `gamepad` and `touch` replace it on
-- those devices. `hud` names a HUD button the card points at; `world` names
-- something in the world it marks ("collect", "eggLab", "incubator",
-- "star"). `icon` is a sprite from the UI kit (Config.SpriteAtlas).
-- Logic/Progression works out the current step.

export type StepDef = {
	id: string,
	stat: string,
	title: string,
	text: string,
	gamepad: string?,
	touch: string?,
	ack: boolean?,
	auto: string?, -- "move" | "fly": the client acknowledges on its own
	final: boolean?,
	hud: string?,
	world: string?,
	icon: string?,
}

local STEPS: { StepDef } = {
	{
		id = "welcome",
		stat = "tutorialWelcome",
		ack = true,
		icon = "Galaxy",
		title = "Hi, Space Explorer!",
		text = "Let's build your own galaxy! Press Next.",
		touch = "Let's build your own galaxy! Tap Next.",
	},
	{
		id = "move",
		stat = "tutorialMoved",
		ack = true,
		auto = "move",
		icon = "Moon",
		title = "Float around",
		text = "W A S D to move. Space goes up.",
		gamepad = "Left stick to move. RB goes up.",
		touch = "Use the joystick to move.",
	},
	{
		id = "launch",
		stat = "shipsLaunched",
		hud = "LaunchShip",
		icon = "Rocket",
		title = "Get in your ship",
		text = "Press Launch Ship!",
		touch = "Tap Launch Ship!",
	},
	{
		id = "fly",
		stat = "tutorialFlew",
		ack = true,
		auto = "fly",
		icon = "Ship",
		title = "Fly!",
		text = "W to go. Mouse to steer. Shift to go fast!",
		gamepad = "Left stick to go. Right stick to steer.",
		touch = "Joystick to go. Drag to steer.",
	},
	{
		id = "mine",
		stat = "asteroidsMined",
		icon = "Mining",
		title = "Zap a space rock",
		text = "Follow the yellow arrows. Click the glowing spot!",
		gamepad = "Follow the yellow arrows. Hold RT on the glowing spot!",
		touch = "Follow the yellow arrows. Hold Laser on the glowing spot!",
	},
	{
		id = "star",
		stat = "starsPlaced",
		hud = "StarShop",
		icon = "StarPlus",
		title = "Buy a star",
		text = "Press Star Shop. Pick a star and place it!",
		touch = "Tap Star Shop. Pick a star and place it!",
	},
	{
		id = "collect",
		stat = "collections",
		hud = "Hangar",
		world = "collect",
		icon = "CoinPile",
		title = "Collect Stardust",
		text = "Press Hangar. Go to the glowing console. Press E.",
		gamepad = "Press Hangar. Go to the glowing console. Press X.",
		touch = "Tap Hangar. Go to the glowing console. Tap the button.",
	},
	{
		id = "egg",
		stat = "eggsBought",
		hud = "Station",
		world = "eggLab",
		icon = "GalaxyOrb",
		title = "Get a planet egg",
		text = "Press Station. Find the giant egg. Buy an egg!",
		touch = "Tap Station. Find the giant egg. Buy an egg!",
	},
	{
		id = "incubate",
		stat = "eggsIncubated",
		hud = "Hangar",
		world = "incubator",
		icon = "OpenChest",
		title = "Hatch your egg",
		text = "Press Hangar. Go through the left door. Press E at a glass dome.",
		gamepad = "Press Hangar. Go through the left door. Press X at a glass dome.",
		touch = "Tap Hangar. Go through the left door. Tap the button at a glass dome.",
	},
	{
		id = "hatch",
		stat = "planetsHatched",
		world = "incubator",
		icon = "PlanetPurple",
		title = "Wait for it...",
		text = "Watch the timer. Your planet pops out at zero!",
	},
	{
		id = "equip",
		stat = "planetsEquipped",
		hud = "Planets",
		icon = "RingedPlanet",
		title = "Add your planet",
		text = "Press Planets, then Equip!",
		touch = "Tap Planets, then Equip!",
	},
	{
		id = "levelup",
		stat = "starUpgrades",
		world = "star",
		icon = "LevelUp",
		title = "Power up your star",
		text = "Fly to your star. Press E, then Level up!",
		gamepad = "Fly to your star. Press X, then Level up!",
		touch = "Fly to your star. Tap the button, then Level up!",
	},
	{
		id = "finish",
		stat = "tutorialFinished",
		ack = true,
		final = true,
		icon = "Medal",
		title = "You did it!",
		text = "Press Finish for your prize!",
		touch = "Tap Finish for your prize!",
	},
}

return {
	STEPS = STEPS,
	FINISH_REWARD = 1000, -- Stardust, once, for finishing (not for skipping)
	MAX_TEXT = 80, -- letters per step text (ConfigCheck)
	-- Client auto-acknowledgement: studs moved in the suit / flown in a ship.
	MOVE_DISTANCE = 12,
	FLY_DISTANCE = 120,
}
