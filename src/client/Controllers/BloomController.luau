--!strict
-- Softer bloom indoors. The world's one bloom effect (Lighting "SpaceBloom",
-- WorldSystem) suits open space, but inside a station hangar (any player's
-- "Station" model, Incubator Bay included) or the Zero G Dodgeball arena its
-- many lights glare. While the camera is inside one of those (their
-- bounding box plus a margin), this client eases the bloom down to
-- Config.World.BLOOM_INDOOR and back to BLOOM_INTENSITY outside. Local only.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local W = Config.World
local MARGIN = 20 -- studs around each box
local SCAN = 1 -- seconds between looking for new stations
local EASE = 4 -- per second

local BloomController = {}

type Box = { cframe: CFrame, half: Vector3, model: Model }

local boxes: { Box } = {}
local scanned = -math.huge

local function addBox(model: Model)
	local ok, cframe, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok then
		table.insert(
			boxes,
			{ cframe = cframe, half = size / 2 + Vector3.one * MARGIN, model = model }
		)
	end
end

local function rescan()
	table.clear(boxes)
	local regions = Workspace:FindFirstChild("Regions")
	if regions then
		for _, region in regions:GetChildren() do
			local station = region:FindFirstChild("Station")
			if station and station:IsA("Model") then
				addBox(station)
			end
		end
	end
	local arena = Workspace:FindFirstChild("DodgeballArena")
	if arena and arena:IsA("Model") then
		addBox(arena)
	end
end

local function indoors(position: Vector3): boolean
	for _, box in boxes do
		if box.model.Parent ~= nil then
			local p = box.cframe:PointToObjectSpace(position)
			if
				math.abs(p.X) <= box.half.X
				and math.abs(p.Y) <= box.half.Y
				and math.abs(p.Z) <= box.half.Z
			then
				return true
			end
		end
	end
	return false
end

function BloomController.start()
	RunService.Heartbeat:Connect(function(dt: number)
		local bloom = Lighting:FindFirstChild("SpaceBloom")
		local camera = Workspace.CurrentCamera
		if bloom == nil or not bloom:IsA("BloomEffect") or camera == nil then
			return
		end
		local now = os.clock()
		if now - scanned > SCAN then
			scanned = now
			rescan()
		end
		local goal = if indoors(camera.CFrame.Position) then W.BLOOM_INDOOR else W.BLOOM_INTENSITY
		local step = math.clamp(dt * EASE, 0, 1)
		bloom.Intensity += (goal - bloom.Intensity) * step
	end)
end

return BloomController
