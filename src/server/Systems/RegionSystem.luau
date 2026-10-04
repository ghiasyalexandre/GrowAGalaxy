--!strict
-- Assigns each player a galaxy region slot on this server, builds its visible
-- boundary, and answers ownership questions for every other system.
--
-- Slots are per server and not saved: a returning player may get a different
-- slot, and their galaxy (saved in region space) loads there unchanged.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local RegionBuilder = require(script.Parent.Parent.World.RegionBuilder)
local RegionMath = require(ReplicatedStorage.Shared.Logic.RegionMath)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

export type Region = {
	slot: number,
	owner: Player,
	origin: CFrame, -- region space -> world space
	size: Vector3,
	color: string,
	model: Model,
}

local RegionSystem = {}

RegionSystem.regionAdded = Signal.new() :: Signal.Signal<Region>
RegionSystem.regionRemoved = Signal.new() :: Signal.Signal<Region>

local bySlot: { [number]: Region } = {}
local byPlayer: { [Player]: Region } = {}
local folder: Folder

local function originFor(slot: number): CFrame
	local position, yaw = RegionMath.slotOrigin(slot)
	return CFrame.new(position.x, position.y, position.z) * CFrame.Angles(0, yaw, 0)
end

local function sizeFor(expansion: number): Vector3
	local size = RegionMath.regionSize(expansion)
	return Vector3.new(size.x, size.y, size.z)
end

local function assign(player: Player, profile: Types.Profile)
	if byPlayer[player] or player.Parent ~= Players then
		return
	end
	local slot = RegionMath.firstFreeSlot(bySlot)
	if slot == nil then
		player:Kick("This server is full. Please join another server.")
		return
	end

	local colors = Config.World.REGION_COLORS
	local color = colors[(slot - 1) % #colors + 1]
	local origin = originFor(slot)
	local size = sizeFor(profile.galaxy.expansion)

	local model = Instance.new("Model")
	model.Name = `Region_{slot}`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("Slot", slot)
	model:SetAttribute("OwnerUserId", player.UserId)
	RegionBuilder.buildBounds(model, origin, size, color)
	model.WorldPivot = origin
	model.Parent = folder

	local region: Region = {
		slot = slot,
		owner = player,
		origin = origin,
		size = size,
		color = color,
		model = model,
	}
	bySlot[slot] = region
	byPlayer[player] = region
	RegionSystem.regionAdded:Fire(region)
end

local function release(player: Player)
	local region = byPlayer[player]
	if region == nil then
		return
	end
	byPlayer[player] = nil
	bySlot[region.slot] = nil
	region.model:Destroy()
	RegionSystem.regionRemoved:Fire(region)
end

-- Grows the player's region to an expansion level and redraws its edges.
-- The origin (near face) stays put, so stars and the station don't move.
function RegionSystem.resize(player: Player, expansion: number)
	local region = byPlayer[player]
	if region == nil then
		return
	end
	region.size = sizeFor(expansion)
	RegionBuilder.buildBounds(region.model, region.origin, region.size, region.color)
end

function RegionSystem.getRegion(player: Player): Region?
	return byPlayer[player]
end

function RegionSystem.getOwner(slot: number): Player?
	local region = bySlot[slot]
	return if region then region.owner else nil
end

-- Is this world position inside the player's own region?
function RegionSystem.isInOwnRegion(player: Player, position: Vector3): boolean
	local region = byPlayer[player]
	if region == nil then
		return false
	end
	local p = region.origin:PointToObjectSpace(position)
	return RegionMath.isInside({ x = p.X, y = p.Y, z = p.Z }, {
		x = region.size.X,
		y = region.size.Y,
		z = region.size.Z,
	}, 0)
end

function RegionSystem.toWorld(region: Region, localPos: Types.Vec3): Vector3
	return region.origin:PointToWorldSpace(Vector3.new(localPos.x, localPos.y, localPos.z))
end

function RegionSystem.toLocal(region: Region, position: Vector3): Types.Vec3
	local p = region.origin:PointToObjectSpace(position)
	return { x = p.X, y = p.Y, z = p.Z }
end

-- Who owns which slot, for clients.
function RegionSystem.list(): { Types.RegionInfo }
	local list: { Types.RegionInfo } = {}
	for slot, region in bySlot do
		table.insert(
			list,
			{ slot = slot, userId = region.owner.UserId, name = region.owner.DisplayName }
		)
	end
	table.sort(list, function(a, b)
		return a.slot < b.slot
	end)
	return list
end

function RegionSystem.init()
	folder = Instance.new("Folder")
	folder.Name = "Regions"
	folder.Parent = Workspace
end

function RegionSystem.start()
	DataSystem.profileLoaded:Connect(assign)
	Players.PlayerRemoving:Connect(release)
end

return RegionSystem
