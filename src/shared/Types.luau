--!strict
-- Shared type definitions. Types that cross the client/server boundary
-- (profile schema, item definitions) live here so both sides agree.

export type Profile = {
	version: number,
	stardust: number,
	owned: { string },
}

export type DropperDef = {
	id: string,
	displayName: string,
	cost: number,
	oreValue: number,
	dropInterval: number,
	color: Color3,
}

return nil
