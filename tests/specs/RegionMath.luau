return function(T, Loader)
	local Config = Loader.require("src/shared/Config")
	local RegionMath = Loader.require("src/shared/Logic/RegionMath")

	T.describe("RegionMath", function()
		T.test("slot 1 sits on +Z at the ring radius, facing the ISS", function()
			local origin, yaw = RegionMath.slotOrigin(1)
			T.near(origin.x, 0)
			T.near(origin.z, Config.World.REGION_RING_RADIUS)
			-- Region +Z must point away from the ISS.
			local ahead = RegionMath.toWorld(1, { x = 0, y = 0, z = 100 })
			T.near(ahead.z, Config.World.REGION_RING_RADIUS + 100)
			T.near(yaw, 0)
		end)

		T.test("every slot's +Z points away from the ISS", function()
			for slot = 1, Config.World.MAX_PLAYERS do
				local origin = RegionMath.slotOrigin(slot)
				local ahead = RegionMath.toWorld(slot, { x = 0, y = 0, z = 100 })
				local r0 = math.sqrt(origin.x ^ 2 + origin.z ^ 2)
				local r1 = math.sqrt(ahead.x ^ 2 + ahead.z ^ 2)
				T.near(r1 - r0, 100, 1e-6, `slot {slot}`)
			end
		end)

		T.test("fully expanded neighbouring regions never overlap", function()
			-- Region footprints are convex, so checking that every corner of one
			-- region lies outside its neighbour (in the neighbour's region space) is enough
			-- for adjacent slots, which are the closest pair.
			local expansions = Config.Galaxy.EXPANSIONS
			local size = expansions[#expansions].size
			local corners = {}
			for _, x in { -size.x / 2, size.x / 2 } do
				for _, z in { 0, size.z } do
					table.insert(corners, { x = x, y = 0, z = z })
				end
			end
			for slot = 1, Config.World.MAX_PLAYERS do
				local neighbour = slot % Config.World.MAX_PLAYERS + 1
				local nOrigin, nYaw = RegionMath.slotOrigin(neighbour)
				local c, s = math.cos(nYaw), math.sin(nYaw)
				for _, corner in corners do
					local world = RegionMath.toWorld(slot, corner)
					-- world -> neighbour region space (inverse rotation)
					local dx, dz = world.x - nOrigin.x, world.z - nOrigin.z
					local localPos = { x = c * dx - s * dz, y = 0, z = s * dx + c * dz }
					T.falsy(
						RegionMath.isInside(localPos, size, 0),
						`slot {slot} corner inside slot {neighbour}`
					)
				end
			end
		end)

		T.test("regions stay clear of the ISS, the Earth backdrop and the Outer Belt", function()
			local field = Config.World.FIELDS.OuterBelt
			for slot = 1, Config.World.MAX_PLAYERS do
				local station =
					RegionMath.toWorld(slot, { x = 0, y = 0, z = -Config.World.STATION_DISTANCE })
				local stationRadius = math.sqrt(station.x ^ 2 + station.z ^ 2)
				T.truthy(
					stationRadius > field.distance + field.radius + 300,
					`slot {slot} station clear of belt`
				)
			end
			local size = Config.Galaxy.EXPANSIONS[#Config.Galaxy.EXPANSIONS].size
			local earthTop = Config.World.EARTH_CENTER.y + Config.World.EARTH_DIAMETER / 2
			T.truthy(Config.World.REGION_RING_HEIGHT - size.y / 2 > earthTop, "regions above Earth")
		end)

		T.test("isInside respects the margin on every wall", function()
			local size = { x = 1000, y = 600, z = 1000 }
			T.truthy(RegionMath.isInside({ x = 0, y = 0, z = 500 }, size, 200))
			T.truthy(RegionMath.isInside({ x = 300, y = 100, z = 200 }, size, 200))
			T.falsy(RegionMath.isInside({ x = 301, y = 0, z = 500 }, size, 200))
			T.falsy(RegionMath.isInside({ x = 0, y = 101, z = 500 }, size, 200))
			T.falsy(RegionMath.isInside({ x = 0, y = 0, z = 199 }, size, 200))
			T.falsy(RegionMath.isInside({ x = 0, y = 0, z = 801 }, size, 200))
		end)

		T.test("firstFreeSlot fills gaps and reports a full server", function()
			T.equal(RegionMath.firstFreeSlot({}), 1)
			T.equal(RegionMath.firstFreeSlot({ [1] = true, [2] = true, [4] = true }), 3)
			local full = {}
			for slot = 1, Config.World.MAX_PLAYERS do
				full[slot] = true
			end
			T.equal(RegionMath.firstFreeSlot(full), nil)
		end)
	end)
end
