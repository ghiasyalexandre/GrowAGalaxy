--!strict
-- Builds each player's personal station inside their region when the region
-- is assigned. The station is destroyed with the region when they leave.
-- stationAdded fires once it's built (HangarSystem adds its upgrades).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionSystem = require(script.Parent.RegionSystem)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local StationBuilder = require(script.Parent.Parent.World.StationBuilder)

local StationSystem = {}

StationSystem.stationAdded = Signal.new() :: Signal.Signal<Player>

local stations: { [Player]: StationBuilder.Station } = {}

-- The player's own station: spawn point, ship berth and docking zone.
function StationSystem.getStation(player: Player): StationBuilder.Station?
	return stations[player]
end

-- Where the player floats when they return to their own station.
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
			region.owner.UserId,
			region.color
		)
		StationSystem.stationAdded:Fire(region.owner)
	end)
	RegionSystem.regionRemoved:Connect(function(region)
		stations[region.owner] = nil
	end)
end

return StationSystem
