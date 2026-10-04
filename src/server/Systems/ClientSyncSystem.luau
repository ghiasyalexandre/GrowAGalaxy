--!strict
-- Gives each client its starting state and keeps everyone's list of region
-- owners up to date. Profile changes are pushed by DataSystem itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataSystem = require(script.Parent.DataSystem)
local Net = require(ReplicatedStorage.Shared.Net)
local ProfileSchema = require(ReplicatedStorage.Shared.Logic.ProfileSchema)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local RegionSystem = require(script.Parent.RegionSystem)
local Types = require(ReplicatedStorage.Shared.Types)

local INITIAL_STATE_TIMEOUT = 20

local ClientSyncSystem = {}

local initialStateLimit = RateLimiter.new(3, 0.5)

local function broadcastRegions()
	Net.RegionsChanged:FireAllClients(RegionSystem.list())
end

function ClientSyncSystem.start()
	Net.GetInitialState.OnServerInvoke = function(player: Player): Types.InitialState?
		if not initialStateLimit.allow(player) then
			return nil
		end
		local profile = DataSystem.waitForProfile(player, INITIAL_STATE_TIMEOUT)
		if profile == nil then
			return nil
		end
		return {
			profile = ProfileSchema.view(profile),
			regions = RegionSystem.list(),
		}
	end

	RegionSystem.regionAdded:Connect(broadcastRegions)
	RegionSystem.regionRemoved:Connect(broadcastRegions)
end

return ClientSyncSystem
