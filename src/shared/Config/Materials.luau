--!strict
-- Crafting materials. Deferred: the revised MVP uses Stardust only, so no
-- system grants or spends materials yet. Kept for a possible later crafting layer.

export type MaterialDef = {
	id: string,
	displayName: string,
	color: string,
	description: string,
}

local ORDER: { string } = { "Iron", "Silicate", "Ice", "Crystal", "StellarGas" }

local BY_ID: { [string]: MaterialDef } = {
	Iron = {
		id = "Iron",
		displayName = "Iron",
		color = "#A7A9AC",
		description = "Structural construction, equipment and rocky bodies.",
	},
	Silicate = {
		id = "Silicate",
		displayName = "Silicate",
		color = "#C9A27E",
		description = "Rocky planets and moons.",
	},
	Ice = {
		id = "Ice",
		displayName = "Ice",
		color = "#BFEFFF",
		description = "Ice planets and moons.",
	},
	Crystal = {
		id = "Crystal",
		displayName = "Crystal",
		color = "#C77DFF",
		description = "Advanced equipment and celestial upgrades.",
	},
	StellarGas = {
		id = "StellarGas",
		displayName = "Stellar Gas",
		color = "#FF9E5E",
		description = "Advanced stars and later progression.",
	},
}

return {
	ORDER = ORDER,
	BY_ID = BY_ID,
}
