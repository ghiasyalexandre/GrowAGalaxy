--!strict
-- The Egg Lab gallery at the ISS: around the giant egg (the "EggGallery"
-- marker, tagged "GaG_EggGallery") one planet of each rarity circles on its
-- own tilted ring, each with a small name label. Every CYCLE seconds each
-- shows the next type of its rarity, so in time the whole catalog passes
-- by. Drawn on this client only (Fx/PlanetLook) and only while the camera is
-- near; with Reduced effects the planets hold still.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local PlanetLook = require(script.Parent.Parent.Fx.PlanetLook)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local P = Config.Planets
local TAG = "GaG_EggGallery"
local CYCLE = 20 -- seconds each type is shown
local NEAR = 220 -- studs: drawn only this close to the camera
local RADIUS = 1.3 -- planet size
local SPEED = 0.35 -- radians per second

local IssGalleryController = {}

type Slot = { rarity: string, typeId: string?, body: Part?, label: BillboardGui? }

local marker: BasePart? = nil
local folder: Folder? = nil
local slots: { Slot } = {}

local function clear(slot: Slot)
	if slot.body then
		slot.body:Destroy()
	end
	slot.body, slot.label, slot.typeId = nil, nil, nil
end

local function show(slot: Slot, typeId: string)
	clear(slot)
	local def = P.BY_ID[typeId]
	if def == nil or folder == nil then
		return
	end
	local body = PlanetLook.build(def, RADIUS, ClientState.reducedEffects == true)
	body.Name = `Gallery_{typeId}`
	body.Parent = folder
	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(150, 30)
	label.StudsOffsetWorldSpace = Vector3.new(0, RADIUS + 1.2, 0)
	label.MaxDistance = 45
	label.LightInfluence = 0
	label.Adornee = body
	label.Parent = body
	local rarity = P.RARITIES[def.rarity]
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextStrokeTransparency = 0.3
	text.TextColor3 = Color3.fromHex(rarity.color)
	text.Text = `{def.displayName} · {rarity.displayName}`
	text.Parent = label
	slot.body, slot.label, slot.typeId = body, label, typeId
end

local function attach(part: Instance)
	if not part:IsA("BasePart") or marker then
		return
	end
	marker = part
	local made = Instance.new("Folder")
	made.Name = "GaG_EggGallery"
	made.Parent = Workspace
	folder = made
	slots = {}
	for _, rarity in P.RARITY_ORDER do
		table.insert(slots, { rarity = rarity })
	end
end

local function step()
	local center = marker
	if center == nil or center.Parent == nil or folder == nil then
		return
	end
	local camera = Workspace.CurrentCamera
	local near = camera ~= nil and (camera.CFrame.Position - center.Position).Magnitude < NEAR
	local t = Workspace:GetServerTimeNow()
	local reduced = ClientState.reducedEffects == true
	for index, slot in slots do
		if not near then
			clear(slot)
			continue
		end
		local types = P.BY_RARITY[slot.rarity]
		local typeId = types[(math.floor(t / CYCLE) + index) % #types + 1]
		if slot.typeId ~= typeId then
			show(slot, typeId)
		end
		local body = slot.body
		if body then
			local ring = 7.5 + index * 0.9
			local angle = index * math.pi / 3
				+ (if reduced then 0 else t * SPEED * (1 - index * 0.06))
			local tilt = CFrame.Angles(math.rad(12 - index * 5), 0, math.rad(index * 7))
			body.CFrame = CFrame.new(center.Position)
				* tilt
				* CFrame.new(math.cos(angle) * ring, 0, math.sin(angle) * ring)
				* CFrame.Angles(0, if reduced then 0 else t * 0.6, 0)
		end
	end
end

function IssGalleryController.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(attach)
	for _, part in CollectionService:GetTagged(TAG) do
		attach(part)
	end
	RunService.RenderStepped:Connect(function()
		local ok, problem = pcall(step :: any)
		if not ok then
			warn(`[IssGallery] {problem}`)
		end
	end)
end

return IssGalleryController
