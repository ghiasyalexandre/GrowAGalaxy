--!strict
-- Builds each player's personal station inside their region when the region
-- is assigned. The station is destroyed with the region when they leave.

local RegionSystem = require(script.Parent.RegionSystem)
local StationBuilder = require(script.Parent.Parent.World.StationBuilder)

local StationSystem = {}

local stations: { [Player]: StationBuilder.Station } = {}

-- Where the player stands when they warp to their own station.
function StationSystem.getSpawn(player: Player): CFrame?
	local station = stations[player]
	return if station then station.spawn else nil
end

function StationSystem.start()
	RegionSystem.regionAdded:Connect(function(region)
		stations[region.owner] = StationBuilder.build(
			region.model,
			region.origin,
			region.owner.DisplayName,
			region.color
		)
	end)
	RegionSystem.regionRemoved:Connect(function(region)
		stations[region.owner] = nil
	end)
end

return StationSystem
