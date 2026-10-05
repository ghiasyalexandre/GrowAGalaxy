--!strict
-- Zero G Dodgeball rules (Config.Dodgeball) shared by the server
-- (DodgeballSystem, World/DodgeballBuilder), the client and tests: where the
-- arena is, where its cover blocks and spawn points go, and which way a
-- launch off a block face sends you. Pure: points are { x, y, z } tables.

local Config = require(script.Parent.Parent.Config)

local D = Config.Dodgeball

export type Point = { x: number, y: number, z: number }
export type Block = { position: Point, size: Point, color: string }

local DodgeballMath = {}

local function add(a: Point, b: Point): Point
	return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

local function scale(a: Point, k: number): Point
	return { x = a.x * k, y = a.y * k, z = a.z * k }
end

local function dot(a: Point, b: Point): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

local function unit(a: Point): Point
	local length = math.sqrt(dot(a, a))
	return if length > 1e-6 then scale(a, 1 / length) else { x = 0, y = 1, z = 0 }
end

-- Whether a point is inside the arena, `margin` studs in from its walls
-- (a negative margin reaches outside).
function DodgeballMath.inside(point: Point, margin: number?): boolean
	local m = margin or 0
	local c, s = D.CENTER, D.SIZE
	return math.abs(point.x - c.x) <= s.x / 2 - m
		and math.abs(point.y - c.y) <= s.y / 2 - m
		and math.abs(point.z - c.z) <= s.z / 2 - m
end

-- Spawn points: evenly round the middle of the four side walls, 12 studs in.
function DodgeballMath.spawnPoints(): { Point }
	local points: { Point } = {}
	local c, s = D.CENTER, D.SIZE
	for i = 1, D.SPAWN_COUNT do
		local angle = (i - 1) / D.SPAWN_COUNT * 2 * math.pi
		local dx, dz = math.cos(angle), math.sin(angle)
		-- Out to the wall along the square's edge, then 12 studs back in.
		local reach = 1 / math.max(math.abs(dx), math.abs(dz))
		table.insert(points, {
			x = c.x + dx * reach * (s.x / 2 - 12),
			y = c.y + ((i % 3) - 1) * s.y * 0.25,
			z = c.z + dz * reach * (s.z / 2 - 12),
		})
	end
	return points
end

local function overlaps(a: Block, b: Block, gap: number): boolean
	return math.abs(a.position.x - b.position.x) < (a.size.x + b.size.x) / 2 + gap
		and math.abs(a.position.y - b.position.y) < (a.size.y + b.size.y) / 2 + gap
		and math.abs(a.position.z - b.position.z) < (a.size.z + b.size.z) / 2 + gap
end

-- The cover blocks, the same on every server (seeded): BLOCK_COUNT boxes
-- inside the arena, never touching each other (a gap of at least 8 studs to
-- float through), the walls, or the space around a spawn point.
function DodgeballMath.blocks(): { Block }
	local seed = D.SEED
	local function rng(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local blocks: { Block } = {}
	local spawns = DodgeballMath.spawnPoints()
	local low, high = D.BLOCK_SIZE[1], D.BLOCK_SIZE[2]
	local c, s = D.CENTER, D.SIZE
	for _ = 1, D.BLOCK_COUNT * 40 do
		if #blocks >= D.BLOCK_COUNT then
			break
		end
		local size = {
			x = low + rng() * (high - low),
			y = low + rng() * (high - low),
			z = low + rng() * (high - low),
		}
		-- Some long slabs and pillars among the cubes.
		if rng() < 0.3 then
			size.y = math.max(size.y * 0.35, 3)
		elseif rng() < 0.2 then
			size.y = high * 1.6
		end
		local position = {
			x = c.x + (rng() - 0.5) * (s.x - size.x - 16),
			y = c.y + (rng() - 0.5) * (s.y - size.y - 16),
			z = c.z + (rng() - 0.5) * (s.z - size.z - 16),
		}
		local block = {
			position = position,
			size = size,
			color = D.BLOCK_COLORS[math.floor(rng() * #D.BLOCK_COLORS) + 1],
		}
		local clear = true
		for _, other in blocks do
			if overlaps(block, other, 8) then
				clear = false
				break
			end
		end
		for _, spawn in spawns do
			if
				overlaps(
					block,
					{ position = spawn, size = { x = 10, y = 10, z = 10 }, color = "" },
					4
				)
			then
				clear = false
				break
			end
		end
		if clear then
			table.insert(blocks, block)
		end
	end
	return blocks
end

-- Which way a launch off a face with outward `normal` sends you, looking
-- along `look`: away from the face, bent towards where you look (never back
-- into the face). A unit vector.
function DodgeballMath.launchDirection(normal: Point, look: Point): Point
	local n, l = unit(normal), unit(look)
	local along = dot(l, n)
	if along <= 0 then
		-- Looking into the face: slide along it, mostly away.
		local flat = add(l, scale(n, -along))
		return unit(add(n, scale(flat, 0.6)))
	end
	return unit(add(scale(n, 0.6), l))
end

-- Where a ball thrown from `origin` along unit `direction` is after `t`
-- seconds (zero-g: a straight line).
function DodgeballMath.ballAt(origin: Point, direction: Point, t: number): Point
	return add(origin, scale(unit(direction), D.BALL_SPEED * math.max(t, 0)))
end

return DodgeballMath
