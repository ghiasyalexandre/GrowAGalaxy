--!strict
-- The new-player tutorial: one step at a time on a card at the top of the
-- screen (TutorialController), written so young players can follow it.
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
		title = "Welcome, Space Explorer!",
		text = "This is your space adventure! You'll fly a spaceship, catch Stardust from space rocks, and grow your very own galaxy of stars and planets. Press Next to begin!",
	},
	{
		id = "move",
		stat = "tutorialMoved",
		ack = true,
		auto = "move",
		icon = "Moon",
		title = "Float around",
		text = "You're floating in space! Press W, A, S and D to move. Space goes up and Ctrl goes down. Hold the right mouse button and drag to look around.",
		gamepad = "You're floating in space! Use the left stick to move. RB goes up and LB goes down. Use the right stick to look around.",
		touch = "You're floating in space! Use the joystick on the left to move. Tap Up or Down to go higher or lower. Swipe the screen to look around.",
	},
	{
		id = "launch",
		stat = "shipsLaunched",
		hud = "LaunchShip",
		icon = "Rocket",
		title = "Get in your spaceship",
		text = "Press the blue Launch Ship button at the bottom of the screen. Your spaceship is waiting for you!",
	},
	{
		id = "fly",
		stat = "tutorialFlew",
		ack = true,
		auto = "fly",
		icon = "Ship",
		title = "Fly your ship",
		text = "Press W to fly forward and S to slow down. Move the mouse to steer. Hold Shift to go super fast!",
		gamepad = "Push the left stick up to fly forward. Steer with the right stick. Click the left stick to go super fast!",
		touch = "Push the joystick up to fly forward. Drag on the screen to steer. Tap Boost to go super fast!",
	},
	{
		id = "mine",
		stat = "asteroidsMined",
		icon = "Mining",
		title = "Catch some Stardust",
		text = "Follow the yellow markers to a space rock. Fly close, point at its glowing spot and click to zap it with your laser. Stardust is the money you build your galaxy with!",
		gamepad = "Follow the yellow markers to a space rock. Fly close, point at its glowing spot and hold RT to zap it with your laser. Stardust is the money you build your galaxy with!",
		touch = "Follow the yellow markers to a space rock. Fly close, point at its glowing spot and hold Laser to zap it. Stardust is the money you build your galaxy with!",
	},
	{
		id = "star",
		stat = "starsPlaced",
		hud = "StarShop",
		icon = "StarPlus",
		title = "Buy your first star",
		text = "Press the Star Shop button (or B). Pick a star, move it to a good spot in your galaxy and press Place.",
		gamepad = "Press the Star Shop button. Pick a star, move it to a good spot in your galaxy and press A to place it.",
		touch = "Tap the Star Shop button. Pick a star, move it to a good spot in your galaxy and tap Place.",
	},
	{
		id = "collect",
		stat = "collections",
		hud = "Hangar",
		world = "collect",
		icon = "CoinPile",
		title = "Collect your Stardust",
		text = "Your star is making Stardust! Press the Hangar button to go home. Go to the glowing Collect console and press E.",
		gamepad = "Your star is making Stardust! Press the Hangar button to go home. Go to the glowing Collect console and press X.",
		touch = "Your star is making Stardust! Tap the Hangar button to go home. Go to the glowing Collect console and tap the button that pops up.",
	},
	{
		id = "egg",
		stat = "eggsBought",
		hud = "Station",
		world = "eggLab",
		icon = "GalaxyOrb",
		title = "Get a planet egg",
		text = "Planets hatch from eggs! Press the Station button to zoom to the big space station. Find the Planet Egg Lab with the giant egg and buy an egg. Need more Stardust? Zap more space rocks!",
	},
	{
		id = "incubate",
		stat = "eggsIncubated",
		hud = "Hangar",
		world = "incubator",
		icon = "OpenChest",
		title = "Hatch your egg",
		text = "Press the Hangar button to go home. Walk through the door on the left side to the Incubator. Press E at a glass dome to put your egg inside.",
		gamepad = "Press the Hangar button to go home. Walk through the door on the left side to the Incubator. Press X at a glass dome to put your egg inside.",
		touch = "Tap the Hangar button to go home. Walk through the door on the left side to the Incubator. Tap the button at a glass dome to put your egg inside.",
	},
	{
		id = "hatch",
		stat = "planetsHatched",
		world = "incubator",
		icon = "PlanetPurple",
		title = "Wait for it...",
		text = "Your egg is warming up! Watch the timer above the dome. When it reaches zero, your new planet pops out!",
	},
	{
		id = "equip",
		stat = "planetsEquipped",
		hud = "Planets",
		icon = "RingedPlanet",
		title = "Give your star a planet",
		text = "Open Planets (or press P) and press Equip on your new planet. Pick your star, and the planet starts flying around it. Planets make lots of Stardust!",
		gamepad = "Open Planets and press Equip on your new planet. Pick your star, and the planet starts flying around it. Planets make lots of Stardust!",
		touch = "Tap Planets and tap Equip on your new planet. Pick your star, and the planet starts flying around it. Planets make lots of Stardust!",
	},
	{
		id = "levelup",
		stat = "starUpgrades",
		world = "star",
		icon = "LevelUp",
		title = "Make your star stronger",
		text = "Fly to your star and press E to manage it. Press Level up to make it bigger and earn even more Stardust!",
		gamepad = "Fly to your star and press X to manage it. Press Level up to make it bigger and earn even more Stardust!",
		touch = "Fly to your star and tap the button that pops up. Tap Level up to make it bigger and earn even more Stardust!",
	},
	{
		id = "finish",
		stat = "tutorialFinished",
		ack = true,
		final = true,
		icon = "Medal",
		title = "You're a Galaxy Builder!",
		text = "Amazing work! Keep zapping space rocks, buy more stars, hatch more eggs and grow the biggest galaxy. Press Finish to get your reward!",
	},
}

return {
	STEPS = STEPS,
	FINISH_REWARD = 1000, -- Stardust, once, for finishing (not for skipping)
	-- Client auto-acknowledgement: studs moved in the suit / flown in a ship.
	MOVE_DISTANCE = 12,
	FLY_DISTANCE = 120,
}
