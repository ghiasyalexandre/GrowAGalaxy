return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local DodgeballMath = Loader.require("src/shared/Logic/DodgeballMath")

	local D = Config.Dodgeball
	local c = D.CENTER

	T.describe("DodgeballMath", function()
		T.test("the arena has an inside and an outside", function()
			T.truthy(DodgeballMath.inside(c))
			T.equal(DodgeballMath.inside({ x = c.x + D.SIZE.x, y = c.y, z = c.z }), false)
			T.equal(
				DodgeballMath.inside({ x = c.x + D.SIZE.x / 2 - 2, y = c.y, z = c.z }, 5),
				false
			)
		end)

		T.test("spawn points are inside, apart from each other", function()
			local spawns = DodgeballMath.spawnPoints()
			T.equal(#spawns, D.SPAWN_COUNT)
			for i, a in spawns do
				T.truthy(DodgeballMath.inside(a, 5), `spawn {i} inside`)
				for j, b in spawns do
					if i ~= j then
						local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
						T.truthy(d > 30, `spawns {i} and {j} apart`)
					end
				end
			end
		end)

		T.test("cover blocks fit inside, never touch, and are the same every time", function()
			local blocks = DodgeballMath.blocks()
			T.truthy(#blocks >= D.BLOCK_COUNT * 0.8, `{#blocks} blocks placed`)
			for i, a in blocks do
				local corner = {
					x = a.position.x + a.size.x / 2,
					y = a.position.y + a.size.y / 2,
					z = a.position.z + a.size.z / 2,
				}
				T.truthy(DodgeballMath.inside(corner, 4), `block {i} inside`)
				for j, b in blocks do
					if i < j then
						local apart = math.abs(a.position.x - b.position.x)
								>= (a.size.x + b.size.x) / 2 + 8
							or math.abs(a.position.y - b.position.y) >= (a.size.y + b.size.y) / 2 + 8
							or math.abs(a.position.z - b.position.z)
								>= (a.size.z + b.size.z) / 2 + 8
						T.truthy(apart, `blocks {i} and {j} apart`)
					end
				end
			end
			local again = DodgeballMath.blocks()
			T.near(again[1].position.x, blocks[1].position.x)
		end)

		T.test("a launch goes away from the face, towards where you look", function()
			local up = { x = 0, y = 1, z = 0 }
			local d = DodgeballMath.launchDirection(up, { x = 1, y = 1, z = 0 })
			T.truthy(d.y > 0 and d.x > 0)
			T.near(math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1, 1e-6)
			local into = DodgeballMath.launchDirection(up, { x = 0.2, y = -1, z = 0 })
			T.truthy(into.y > 0, "looking into the face still pushes away")
		end)

		T.test("balls fly straight at BALL_SPEED", function()
			local p = DodgeballMath.ballAt({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 2 }, 2)
			T.near(p.z, D.BALL_SPEED * 2)
			T.near(p.x, 0)
		end)
	end)
end
