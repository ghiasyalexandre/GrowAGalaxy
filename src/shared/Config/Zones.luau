--!strict
-- Mining zones. Only enabled zones are built in the world; the rest are defined
-- now so later stages only flip the flag and tune numbers.
--
-- Rule (checked by Logic/ConfigCheck): a zone's unlock cost may only use
-- materials that earlier zones produce, so no zone ever gates itself.

export type MaterialWeight = { material: string, weight: number }

export type Cost = { credits: number, materials: { [string]: number } }

export type ZoneDef = {
	id: string,
	displayName: string,
	purpose: string,
	enabled: boolean,
	materials: { MaterialWeight },
	asteroidCount: number,
	respawnSeconds: number,
	weakPoints: "Static" | "Moving",
	extractionStages: number,
	unlock: Cost?, -- nil = available from the start
}

local ORDER: { string } = { "OuterBelt", "FrozenBelt", "CrystalBelt", "NebulaBelt" }

local BY_ID: { [string]: ZoneDef } = {
	OuterBelt = {
		id = "OuterBelt",
		displayName = "Outer Belt",
		purpose = "Beginner construction",
		enabled = true,
		materials = {
			{ material = "Iron", weight = 55 },
			{ material = "Silicate", weight = 45 },
		},
		asteroidCount = 40,
		respawnSeconds = 20,
		weakPoints = "Static",
		extractionStages = 1,
		unlock = nil,
	},
	FrozenBelt = {
		id = "FrozenBelt",
		displayName = "Frozen Belt",
		purpose = "Ice bodies and intermediate upgrades",
		enabled = false,
		materials = {
			{ material = "Ice", weight = 50 },
			{ material = "Iron", weight = 25 },
			{ material = "Silicate", weight = 25 },
		},
		asteroidCount = 35,
		respawnSeconds = 25,
		weakPoints = "Static",
		extractionStages = 1,
		unlock = { credits = 3000, materials = { Iron = 100, Silicate = 100 } },
	},
	CrystalBelt = {
		id = "CrystalBelt",
		displayName = "Crystal Belt",
		purpose = "Advanced equipment and planets",
		enabled = false,
		materials = {
			{ material = "Crystal", weight = 40 },
			{ material = "Iron", weight = 60 },
		},
		asteroidCount = 30,
		respawnSeconds = 30,
		weakPoints = "Moving",
		extractionStages = 2,
		unlock = { credits = 20000, materials = { Iron = 200, Ice = 200 } },
	},
	NebulaBelt = {
		id = "NebulaBelt",
		displayName = "Nebula Belt",
		purpose = "Advanced stars and solar systems",
		enabled = false,
		materials = {
			{ material = "StellarGas", weight = 55 },
			{ material = "Crystal", weight = 45 },
		},
		asteroidCount = 30,
		respawnSeconds = 35,
		weakPoints = "Moving",
		extractionStages = 3,
		unlock = { credits = 75000, materials = { Crystal = 300, Ice = 300 } },
	},
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
	STARTER_ZONE = "OuterBelt",
}
