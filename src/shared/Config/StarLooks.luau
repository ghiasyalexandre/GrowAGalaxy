--!strict
-- How each star type looks on the client (Fx/StarLook), on top of the
-- server's plain Core ball, which stays the source of truth for size and
-- colour. All looks are cosmetic and local; nothing here changes gameplay.
-- Pure data (no Roblox types), so tests and ConfigCheck can load it.
--
-- Layers, from the inside out (each optional per type):
--   core       the server's core ball, recoloured locally to a deeper tone
--   plasma     a ForceField shell just outside the core: the engine animates
--              its pattern, so the surface churns
--   granules   particles stuck to the surface (turbulent colour variation)
--   bands      latitude stripes (brown dwarfs' cloud belts)
--   corona     soft additive glows round the star: a ragged outer corona
--              and a brighter limb glow (kept small enough that the first
--              orbit stays clear)
--   spikes     a starburst glint (the hottest stars)
--   flares     looping prominences that rise off the surface and fade
--   wind       particles streaming away (mass loss, stellar wind)
--   disk/jets  the black hole's accretion disk and polar jets
--   binary     two stars circling their shared centre (the core itself is
--              hidden), with a glowing stream of gas pulled between them
--
-- Detail drops with distance from the camera (studs from the star's surface):
-- within NEAR everything; within MID no granules or wind; beyond MID only
-- the corona, spikes and jets. Reduced effects caps a star at MID.

export type Flare = {
	every: { number }, -- seconds between flares: { min, max }
	life: number, -- seconds a flare lasts (rise, hold, fade)
	color: string,
	width: number, -- share of the star's radius
	height: number, -- arc height, share of the radius
	burst: boolean?, -- a bright flash and sparks as it erupts (flare stars)
}

export type Look = {
	core: string?, -- the core ball's colour on this client (deeper than the neon default)
	plasma: { color: string, transparency: number, scale: number }?,
	granules: {
		colors: { string }, -- picked through (hot to cool)
		size: number, -- share of the radius
		rate: number, -- per second at radius 10 (scales with surface area)
		life: { number }, -- seconds: { min, max }
		texture: string,
	}?,
	bands: { colors: { string }, count: number }?,
	spin: number, -- radians per second (the black hole's disk clumps)
	corona: { color: string, scale: number, transparency: number, pulse: number? }?,
	spikes: { color: string, scale: number, transparency: number }?,
	flares: Flare?,
	wind: {
		color: string,
		rate: number,
		speed: number, -- share of the radius per second
		size: number,
		life: number,
		texture: string,
	}?,
	disk: { inner: string, outer: string, scale: number, tilt: number, spin: number }?,
	jets: { color: string, length: number }?,
	binary: {
		a: { color: string, glow: string, size: number }, -- size: share of the star's radius
		b: { color: string, glow: string, size: number },
		distance: number, -- each star's distance from the centre, share of the radius
		period: number, -- seconds per turn
		tilt: number, -- degrees
		stream: string, -- colour of the gas pulled from b onto a
	}?,
}

-- Built-in textures (no uploads). Despite its name, fire_main is an
-- eight-point starburst; explosion01_core_main is a fiery puff.
local CELL = "rbxasset://textures/particles/explosion01_core_main.dds"
local WISP = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local GLINT = "rbxasset://textures/particles/fire_main.dds"

-- Tuned from the Yellow Dwarf: a deep core under bright surface cells, a
-- ragged corona (transparency ~0.6), and prominences 0.3r wide, 0.8r high.
-- Each type then leans on what its name promises.
local LOOKS: { [string]: Look } = {
	-- A failed star: dim, banded like a gas giant, a faint smouldering glow.
	BrownDwarf = {
		core = "#4A2216",
		plasma = { color = "#7A3E2A", transparency = 0.35, scale = 1.015 },
		granules = {
			colors = { "#C97A4A", "#8A4A2E", "#4A2216" },
			size = 0.45,
			rate = 6,
			life = { 3, 5 },
			texture = SMOKE,
		},
		bands = { colors = { "#A8683F", "#5E3020", "#C98A5E", "#71402A" }, count = 5 },
		spin = 0,
		corona = { color = "#B0603A", scale = 1.4, transparency = 0.78, pulse = 0.04 },
		flares = {
			every = { 12, 20 },
			life = 5,
			color = "#E0602A",
			width = 0.2,
			height = 0.5,
		},
	},
	-- A flare star: small, deep red, frequent violent flares with bursts.
	RedDwarf = {
		core = "#B02A14",
		plasma = { color = "#FF5A30", transparency = 0.15, scale = 1.015 },
		granules = {
			colors = { "#FFC08A", "#FF5A30", "#8A1A0C" },
			size = 0.38,
			rate = 14,
			life = { 1.2, 2.2 },
			texture = CELL,
		},
		spin = 0,
		corona = { color = "#FF4A20", scale = 1.6, transparency = 0.64, pulse = 0.08 },
		flares = {
			every = { 2, 4 },
			life = 3.5,
			color = "#FF6A2E",
			width = 0.3,
			height = 0.9,
			burst = true,
		},
	},
	-- A sun like ours: golden granulation, a soft corona, prominences.
	YellowDwarf = {
		core = "#E07812",
		plasma = { color = "#FFB238", transparency = 0.1, scale = 1.012 },
		granules = {
			colors = { "#FFF4C2", "#FFB238", "#D2560E" },
			size = 0.34,
			rate = 16,
			life = { 1.2, 2.2 },
			texture = CELL,
		},
		spin = 0,
		corona = { color = "#FFB020", scale = 1.75, transparency = 0.62, pulse = 0.06 },
		flares = {
			every = { 3, 6 },
			life = 5,
			color = "#FF8A1F",
			width = 0.3,
			height = 0.8,
		},
	},
	-- Two suns circling each other: a golden star and a hot blue-white
	-- one, a shared glow round both and a stream of gas pulled between them.
	BinaryStar = {
		spin = 0,
		corona = { color = "#FFD08A", scale = 1.5, transparency = 0.7, pulse = 0.05 },
		binary = {
			a = { color = "#FFC04A", glow = "#FFB020", size = 0.62 },
			b = { color = "#CFE0FF", glow = "#8FB8FF", size = 0.5 },
			distance = 1.05,
			period = 12,
			tilt = 15,
			stream = "#9FC8FF",
		},
	},
	-- A dense white-hot ember: tiny, intense, a hard halo and a starburst.
	WhiteDwarf = {
		core = "#B8CCF0",
		plasma = { color = "#DDE8FF", transparency = 0.05, scale = 1.02 },
		granules = {
			colors = { "#FFFFFF", "#CFE0FF", "#8FB0F0" },
			size = 0.26,
			rate = 18,
			life = { 0.5, 0.9 },
			texture = WISP,
		},
		spin = 0,
		corona = { color = "#CFE0FF", scale = 1.75, transparency = 0.5, pulse = 0.14 },
		spikes = { color = "#EAF2FF", scale = 4.5, transparency = 0.25 },
	},
	-- Swollen and blazing red: big slow cells, long flares, gas drifting off.
	RedGiant = {
		core = "#B8361A",
		plasma = { color = "#FF6B3D", transparency = 0.2, scale = 1.01 },
		granules = {
			colors = { "#FFC08A", "#FF6B3D", "#8A2410" },
			size = 0.5,
			rate = 10,
			life = { 2.5, 4 },
			texture = CELL,
		},
		spin = 0,
		corona = { color = "#FF7A40", scale = 1.6, transparency = 0.62, pulse = 0.05 },
		flares = {
			every = { 4, 8 },
			life = 7,
			color = "#FF7A3D",
			width = 0.3,
			height = 0.7,
		},
		wind = {
			color = "#FF6A3A",
			rate = 2,
			speed = 0.25,
			size = 0.35,
			life = 4,
			texture = SMOKE,
		},
	},
	-- Hot, bright and fierce: blue-white churn, a starburst, a fast wind.
	BlueGiant = {
		core = "#3F6FE0",
		plasma = { color = "#8FC0FF", transparency = 0.05, scale = 1.012 },
		granules = {
			colors = { "#FFFFFF", "#A9CCFF", "#3F6FE0" },
			size = 0.32,
			rate = 20,
			life = { 0.8, 1.4 },
			texture = CELL,
		},
		spin = 0,
		corona = { color = "#6FA8FF", scale = 1.75, transparency = 0.55, pulse = 0.1 },
		spikes = { color = "#CFE3FF", scale = 3.2, transparency = 0.35 },
		flares = {
			every = { 3, 6 },
			life = 4,
			color = "#9FCBFF",
			width = 0.26,
			height = 0.8,
		},
		wind = {
			color = "#BFE0FF",
			rate = 12,
			speed = 1.6,
			size = 0.12,
			life = 1.2,
			texture = WISP,
		},
	},
	-- One of the largest stars there is: huge boiling cells, the biggest
	-- flares with bursts, and thick red gas pouring off it.
	RedSupergiant = {
		core = "#9E1E10",
		plasma = { color = "#FF4A2E", transparency = 0.2, scale = 1.008 },
		granules = {
			colors = { "#FFD0A0", "#FF4A2E", "#6A0E06" },
			size = 0.55,
			rate = 9,
			life = { 3, 5 },
			texture = CELL,
		},
		spin = 0,
		corona = { color = "#FF5A30", scale = 1.5, transparency = 0.58, pulse = 0.05 },
		flares = {
			every = { 2.5, 5 },
			life = 8,
			color = "#FF6A3D",
			width = 0.32,
			height = 0.8,
			burst = true,
		},
		wind = {
			color = "#E0401E",
			rate = 3,
			speed = 0.2,
			size = 0.45,
			life = 5,
			texture = SMOKE,
		},
	},
	-- Blowing itself apart: a violet-blue furnace, a starburst and a thick,
	-- fast wind of glowing gas streaming off it.
	WolfRayet = {
		core = "#3A2FC8",
		plasma = { color = "#A9A0FF", transparency = 0.06, scale = 1.015 },
		granules = {
			colors = { "#FFFFFF", "#B8B0FF", "#4A3FE0" },
			size = 0.3,
			rate = 22,
			life = { 0.6, 1.1 },
			texture = CELL,
		},
		spin = 0,
		corona = { color = "#8F86FF", scale = 1.85, transparency = 0.52, pulse = 0.1 },
		spikes = { color = "#DCD8FF", scale = 3, transparency = 0.4 },
		flares = {
			every = { 2, 4 },
			life = 4,
			color = "#B0A0FF",
			width = 0.26,
			height = 0.9,
		},
		wind = {
			color = "#9F90FF",
			rate = 18,
			speed = 1.4,
			size = 0.3,
			life = 2,
			texture = SMOKE,
		},
	},
	-- A tiny, blinding cinder: white-blue, a hard halo and a big starburst.
	NeutronStar = {
		core = "#AFC8F0",
		plasma = { color = "#F0F6FF", transparency = 0.04, scale = 1.03 },
		granules = {
			colors = { "#FFFFFF", "#DDEBFF", "#9FC8FF" },
			size = 0.22,
			rate = 24,
			life = { 0.3, 0.6 },
			texture = WISP,
		},
		spin = 0,
		corona = { color = "#BFDCFF", scale = 1.7, transparency = 0.45, pulse = 0.2 },
		spikes = { color = "#FFFFFF", scale = 5.5, transparency = 0.2 },
	},
	-- A cosmic lighthouse: a neutron star throbbing fast, with two long
	-- cyan beams out of its poles.
	Pulsar = {
		core = "#7FD8F0",
		plasma = { color = "#D8FAFF", transparency = 0.05, scale = 1.03 },
		granules = {
			colors = { "#FFFFFF", "#9FF0FF", "#3FD8FF" },
			size = 0.22,
			rate = 24,
			life = { 0.3, 0.6 },
			texture = WISP,
		},
		spin = 0,
		corona = { color = "#5FE8FF", scale = 1.75, transparency = 0.45, pulse = 0.35 },
		spikes = { color = "#CFFAFF", scale = 4, transparency = 0.3 },
		jets = { color = "#5FE8FF", length = 9 },
	},
	-- The strongest magnet there is: magenta fire, violent bursting flares
	-- (starquakes), a throbbing glow and short magnetic jets.
	Magnetar = {
		core = "#9A1ACF",
		plasma = { color = "#FF7AF0", transparency = 0.08, scale = 1.025 },
		granules = {
			colors = { "#FFFFFF", "#FF7AF0", "#9A1ACF" },
			size = 0.26,
			rate = 22,
			life = { 0.4, 0.8 },
			texture = CELL,
		},
		spin = 0,
		corona = { color = "#E060FF", scale = 1.8, transparency = 0.5, pulse = 0.25 },
		spikes = { color = "#FFD0FF", scale = 3.5, transparency = 0.35 },
		flares = {
			every = { 1.2, 2.5 },
			life = 2.5,
			color = "#FF5AE0",
			width = 0.3,
			height = 1.2,
			burst = true,
		},
		jets = { color = "#FF7AF0", length = 4 },
	},
	-- Light can't escape: a dark core inside a purple glow, a turning
	-- accretion disk of hot clumps, and jets out of both poles.
	BlackHole = {
		core = "#020104",
		spin = 0,
		corona = { color = "#9A5CFF", scale = 1.8, transparency = 0.6, pulse = 0.12 },
		disk = { inner = "#FFF0C0", outer = "#FF6A2E", scale = 2.1, tilt = 12, spin = 0.6 },
		jets = { color = "#B67CFF", length = 5 },
	},
	-- Fictional stars, built from the same layers.
	-- A newborn star in its birth nebula: magenta and teal gas churning,
	-- soft pink flares, and teal wisps blowing off it.
	NebulaHeart = {
		core = "#6A1A8A",
		plasma = { color = "#E060FF", transparency = 0.12, scale = 1.015 },
		granules = {
			colors = { "#FFFFFF", "#FF7AE0", "#5FE3FF" },
			size = 0.4,
			rate = 16,
			life = { 1.5, 2.6 },
			texture = WISP,
		},
		spin = 0,
		corona = { color = "#C060FF", scale = 1.8, transparency = 0.6, pulse = 0.08 },
		flares = {
			every = { 3, 6 },
			life = 6,
			color = "#FF7AE0",
			width = 0.3,
			height = 0.9,
		},
		wind = {
			color = "#5FE3FF",
			rate = 5,
			speed = 0.4,
			size = 0.4,
			life = 4,
			texture = SMOKE,
		},
	},
	-- Crystal-bright: an icy white core, rainbow glints, a huge starburst.
	PrismStar = {
		core = "#7FD8F0",
		plasma = { color = "#E8FFFF", transparency = 0.05, scale = 1.02 },
		granules = {
			colors = { "#FFFFFF", "#7FFFE8", "#FF9AE8", "#FFE07A" },
			size = 0.28,
			rate = 22,
			life = { 0.6, 1.1 },
			texture = WISP,
		},
		spin = 0,
		corona = { color = "#BFF8FF", scale = 1.7, transparency = 0.52, pulse = 0.14 },
		spikes = { color = "#FFFFFF", scale = 5, transparency = 0.2 },
		flares = {
			every = { 2.5, 5 },
			life = 3.5,
			color = "#9AF0FF",
			width = 0.2,
			height = 0.9,
		},
	},
	-- Dark matter on fire: a near-black core, green flames and a green-gold
	-- disk swirling round it.
	VoidFlame = {
		core = "#0A0414",
		plasma = { color = "#3A0F5A", transparency = 0.3, scale = 1.012 },
		granules = {
			colors = { "#B8FF8A", "#3ACF6A", "#1A0A2E" },
			size = 0.42,
			rate = 14,
			life = { 1.2, 2.2 },
			texture = CELL,
		},
		spin = 0,
		corona = { color = "#5CFF8A", scale = 1.75, transparency = 0.58, pulse = 0.1 },
		flares = {
			every = { 2, 4 },
			life = 4,
			color = "#7CFF6A",
			width = 0.3,
			height = 1,
			burst = true,
		},
		disk = { inner = "#D8FFB0", outer = "#4A1A8A", scale = 2.2, tilt = 22, spin = 0.8 },
	},
	-- Reborn in fire: blazing gold, the biggest bursting flares, fire
	-- pouring off it and two jets like wings.
	CosmicPhoenix = {
		core = "#C8380A",
		plasma = { color = "#FFC040", transparency = 0.06, scale = 1.012 },
		granules = {
			colors = { "#FFF8D0", "#FFB020", "#FF4A10" },
			size = 0.36,
			rate = 22,
			life = { 0.9, 1.6 },
			texture = CELL,
		},
		spin = 0,
		corona = { color = "#FF9A20", scale = 1.85, transparency = 0.55, pulse = 0.12 },
		spikes = { color = "#FFE0A0", scale = 3.5, transparency = 0.35 },
		flares = {
			every = { 1.5, 3 },
			life = 5,
			color = "#FFB030",
			width = 0.34,
			height = 1.1,
			burst = true,
		},
		wind = {
			color = "#FF7A20",
			rate = 6,
			speed = 0.5,
			size = 0.4,
			life = 3,
			texture = SMOKE,
		},
		jets = { color = "#FFD070", length = 6 },
	},
}

return {
	LOOKS = LOOKS,
	NEAR = 450, -- studs from the surface: full detail inside this (a region seen from its station)
	MID = 1100, -- studs: corona, plasma and flares inside this; beyond, glow only
	LOD_INTERVAL = 0.25, -- seconds between distance checks per star
	-- The corona's outer edge stays this far inside the first orbit
	-- (Config.Stars ORBIT_FIRST), so planets there are never swallowed.
	CORONA_ORBIT_MARGIN = 6,
	FLARE_TEXTURE = CELL,
	-- Coronas are a few big additive smoke puffs (soft, ragged edges).
	GLOW_TEXTURE = SMOKE,
	GLINT_TEXTURE = GLINT,
	SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds",
}
