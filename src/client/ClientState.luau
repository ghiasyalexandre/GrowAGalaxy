--!strict
-- The client's copy of what the server has told it (its profile view, who
-- owns which region, its ship) plus local state shared by controllers
-- (suit or ship mode, stabilizer, flight readout, route). Display only; the
-- server stays authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Signal =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local MAX_ATTEMPTS = 30

export type Mode = "suit" | "ship"
export type DockStatus = "none" | "ready" | "tooFast"
export type Route = "Station" | "ISS"

local ClientState = {}

ClientState.profile = nil :: Types.ProfileView?
ClientState.regions = {} :: { Types.RegionInfo }

-- The player's spawned ship, if any, and its effective stats.
ClientState.ship = nil :: Model?
ClientState.shipInfo = nil :: Types.ShipInfo?

ClientState.mode = "suit" :: Mode
ClientState.stabilization = true
-- Fewer particles (sparkles, space dust) for slower devices or taste.
ClientState.reducedEffects = false
ClientState.route = "Station" :: Route
-- Updated every frame while flying.
ClientState.flight = {
	speed = 0,
	maxSpeed = 0,
	throttle = 0, -- 0 to 1, forward thrust the pilot is asking for
	dock = "none" :: DockStatus,
}
-- The local pilot's last laser shot, drawn at once without waiting for the
-- server. `direction` is in ship space (-Z is the nose).
ClientState.beam = {
	lastShot = 0, -- os.clock() of the last shot
	direction = Vector3.new(0, 0, -1),
}

-- Fires with the changed field name, or "*" after the initial load.
ClientState.profileChanged = Signal.new() :: Signal.Signal<string>
ClientState.regionsChanged = Signal.new() :: Signal.Signal<()>
ClientState.shipChanged = Signal.new() :: Signal.Signal<()>
ClientState.modeChanged = Signal.new() :: Signal.Signal<()>
ClientState.stabilizationChanged = Signal.new() :: Signal.Signal<()>
ClientState.effectsChanged = Signal.new() :: Signal.Signal<()>
ClientState.routeChanged = Signal.new() :: Signal.Signal<()>
-- A short message to show the player (from the server or a controller).
ClientState.notify = Signal.new() :: Signal.Signal<string>

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

function ClientState.setMode(mode: Mode)
	if mode ~= ClientState.mode then
		ClientState.mode = mode
		ClientState.modeChanged:Fire()
	end
end

-- Changes a setting and saves it on the server.
function ClientState.setStabilization(on: boolean)
	ClientState.stabilization = on
	ClientState.stabilizationChanged:Fire()
	Net.SettingChanged:FireServer("stabilization", on)
end

function ClientState.setReducedEffects(on: boolean)
	ClientState.reducedEffects = on
	ClientState.effectsChanged:Fire()
	Net.SettingChanged:FireServer("reducedEffects", on)
end

function ClientState.setRoute(route: Route)
	ClientState.route = route
	ClientState.routeChanged:Fire()
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
	Net.ShipState.OnClientEvent:Connect(function(ship: Model?, info: Types.ShipInfo?)
		ClientState.ship = ship
		ClientState.shipInfo = info
		ClientState.shipChanged:Fire()
	end)
	Net.Notify.OnClientEvent:Connect(function(text: string)
		if type(text) == "string" then
			ClientState.notify:Fire(text)
		end
	end)

	for _ = 1, MAX_ATTEMPTS do
		local ok, state = pcall(function()
			return Net.GetInitialState:InvokeServer()
		end)
		if ok and type(state) == "table" then
			ClientState.profile = state.profile
			ClientState.regions = state.regions
			-- Saved settings, applied without sending them back.
			local settings = state.profile.settings
			if type(settings) == "table" then
				ClientState.stabilization = settings.stabilization ~= false
				ClientState.reducedEffects = settings.reducedEffects == true
				ClientState.stabilizationChanged:Fire()
				ClientState.effectsChanged:Fire()
			end
			ClientState.profileChanged:Fire("*")
			ClientState.regionsChanged:Fire()
			return
		end
		task.wait(2)
	end
	warn("[ClientState] Could not get the starting state from the server")
end

return ClientState
