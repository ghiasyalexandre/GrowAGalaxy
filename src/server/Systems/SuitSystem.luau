--!strict
-- The HUD's travel buttons (SuitRecover): "hangar" moves the player to their
-- own station (the ISS arrival module if they have none yet), "station" to
-- the ISS arrival module, where everyone spawns, and ("visit", userId) to
-- another player's hangar in this server (the Visit panel); its owner is
-- told. A player flying their ship has it stowed first; they can launch it
-- again from their hangar. All share RECOVER_COOLDOWN.
--
-- Spacesuit movement itself runs on the client (SuitController); FlightGuard
-- checks it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FlightGuard = require(script.Parent.FlightGuard)
local Net = require(ReplicatedStorage.Shared.Net)
local Notify = require(script.Parent.Parent.Util.Notify)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local ShipSystem = require(script.Parent.ShipSystem)
local StationSystem = require(script.Parent.StationSystem)
local Teleport = require(script.Parent.Parent.Util.Teleport)
local WorldSystem = require(script.Parent.WorldSystem)

local SuitSystem = {}

local lastRecover: { [Player]: number } = {}
local recoverLimit = RateLimiter.new(2, 0.5)

local function destination(player: Player, where: string, host: Player?): (CFrame?, string)
	if where == "visit" then
		local spawn = if host then StationSystem.getSpawn(host) else nil
		if spawn and host then
			return spawn, `Welcome to {host.DisplayName}'s hangar!`
		end
		return nil, ""
	end
	local spawn = if where == "hangar" then StationSystem.getSpawn(player) else nil
	if spawn then
		return spawn, "Welcome back to your hangar."
	end
	local arrival = WorldSystem.getMarker("ArrivalSpawn")
	if arrival then
		return arrival.CFrame + Vector3.new(0, arrival.Size.Y / 2 + 3, 0), "Back at the ISS."
	end
	return nil, ""
end

local function recover(player: Player, where: unknown, hostId: unknown)
	if where ~= "hangar" and where ~= "station" and where ~= "visit" then
		return
	end
	if not recoverLimit.allow(player) or Teleport.rootOf(player) == nil then
		return
	end
	local host: Player? = nil
	if where == "visit" then
		host = if type(hostId) == "number" then Players:GetPlayerByUserId(hostId) else nil
		if host == nil or host == player then
			Notify.send(player, "That player isn't in this server.")
			return
		end
		if StationSystem.getSpawn(host :: Player) == nil then
			Notify.send(player, "Their hangar isn't ready yet.")
			return
		end
	end
	local now = os.clock()
	local ready = (lastRecover[player] or -math.huge) + Config.Movement.RECOVER_COOLDOWN
	if now < ready then
		Notify.send(player, `Travel is recharging. Try again in {math.ceil(ready - now)}s.`)
		return
	end
	local goal, message = destination(player, where :: string, host)
	if goal == nil then
		return
	end
	lastRecover[player] = now

	ShipSystem.stow(player)
	if Teleport.character(player, goal) then
		FlightGuard.reset(player)
		Notify.send(player, message)
		if host then
			Notify.send(host, `{player.DisplayName} is visiting your hangar!`)
		end
	end
end

function SuitSystem.start()
	Net.SuitRecover.OnServerEvent:Connect(recover)
	Players.PlayerRemoving:Connect(function(player)
		lastRecover[player] = nil
	end)
end

return SuitSystem
