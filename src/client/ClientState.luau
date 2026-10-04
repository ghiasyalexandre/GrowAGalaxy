--!strict
-- The client's copy of what the server has told it: its own profile view and
-- who owns which region. Display only; the server stays authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Signal =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local MAX_ATTEMPTS = 30

local ClientState = {}

ClientState.profile = nil :: Types.ProfileView?
ClientState.regions = {} :: { Types.RegionInfo }

-- Fires with the changed field name, or "*" after the initial load.
ClientState.profileChanged = Signal.new() :: Signal.Signal<string>
ClientState.regionsChanged = Signal.new() :: Signal.Signal<()>

-- The local player's region slot, if they have one yet.
function ClientState.mySlot(): number?
	local userId = Players.LocalPlayer.UserId
	for _, info in ClientState.regions do
		if info.userId == userId then
			return info.slot
		end
	end
	return nil
end

-- Connects to server updates and fetches the starting state. Yields.
function ClientState.load()
	Net.ProfileChanged.OnClientEvent:Connect(function(field: string, value: any)
		local profile = ClientState.profile
		if profile and type(field) == "string" then
			(profile :: any)[field] = value
			ClientState.profileChanged:Fire(field)
		end
	end)
	Net.RegionsChanged.OnClientEvent:Connect(function(regions: { Types.RegionInfo })
		ClientState.regions = regions
		ClientState.regionsChanged:Fire()
	end)

	for _ = 1, MAX_ATTEMPTS do
		local ok, state = pcall(function()
			return Net.GetInitialState:InvokeServer()
		end)
		if ok and type(state) == "table" then
			ClientState.profile = state.profile
			ClientState.regions = state.regions
			ClientState.profileChanged:Fire("*")
			ClientState.regionsChanged:Fire()
			return
		end
		task.wait(2)
	end
	warn("[ClientState] Could not get the starting state from the server")
end

return ClientState
