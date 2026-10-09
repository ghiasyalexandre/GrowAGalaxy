--!strict
-- Draws the egg on every Egg Lab's pedestal (models tagged "GaG_EggLab",
-- DeviceBuilder.eggLab), for owners and visitors alike, from the model's
-- attributes (EggSystem):
--
--   Rarity, Tier   the pedestal egg: coloured by its rarity, dressed with
--                  its tier's effects (PlanetLook.tierFx); none = a faint
--                  pink shell waiting for a roll
--   RolledAt       server time of the latest roll: the egg shakes and
--                  flickers through the rarity colours for ROLL_SECONDS,
--                  then pops into the new egg with a burst (a bigger one
--                  for Epic and rarer or tier 5 and up)
--
-- The egg bobs and turns while it waits. Only the owner's lab keeps its
-- prompt and its ROLL / KEEP buttons enabled. Reduced effects skips the shaking and the
-- particles (the colours and the reveal stay).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local PlanetLook = require(script.Parent.Parent.Fx.PlanetLook)
local StarFx = require(script.Parent.Parent.Fx.StarFx)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PlanetsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Planets"))

local P = Config.Planets
local E = Config.Eggs
local TAG = "GaG_EggLab"
local EGG_SIZE = 1.7 -- studs across (the mesh makes it taller)
local IDLE_COLOR = Color3.fromRGB(255, 110, 200)
local BOB = 0.15 -- studs
local TURN = 0.8 -- radians per second

local EggLabController = {}

type Lab = {
	model: Model,
	spot: BasePart,
	egg: Part?,
	rollingUntil: number, -- os.clock() the roll animation ends, 0 when idle
	shown: string, -- the rarity and tier the egg shows ("" = empty)
	connections: { RBXScriptConnection },
}

local labs: { [Model]: Lab } = {}

local function reduced(): boolean
	return ClientState.reducedEffects == true
end

local function makeEgg(lab: Lab, color: Color3, tier: number?, ghost: boolean): Part
	if lab.egg then
		lab.egg:Destroy()
	end
	local egg = Instance.new("Part")
	egg.Name = "GaG_LabEgg"
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.one * EGG_SIZE
	egg.CFrame = lab.spot.CFrame
	egg.Color = color
	egg.Material = if ghost then Enum.Material.Glass else Enum.Material.SmoothPlastic
	egg.Transparency = if ghost then 0.6 else 0
	egg.Reflectance = if ghost then 0 else 0.2
	egg.Anchored = true
	egg.CanCollide = false
	egg.CanQuery = false
	egg.CanTouch = false
	egg.CastShadow = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.35, 1)
	mesh.Parent = egg
	if tier then
		PlanetLook.tierFx(egg, tier, EGG_SIZE / 2, reduced())
	end
	egg.Parent = lab.model
	lab.egg = egg
	return egg
end

-- The label over a rolled egg: its tier (number and name, in the tier's
-- colour) above its rarity (in the rarity's colour). Seen within
-- LABEL_DISTANCE studs; it rides on the egg, so it goes when the egg does.
local LABEL_DISTANCE = 40

local function label(egg: Part, rarity: PlanetsConfig.RarityDef, tier: number)
	local tierDef = P.TIERS[tier]
	local gui = Instance.new("BillboardGui")
	gui.Name = "EggLabel"
	gui.Size = UDim2.fromOffset(180, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, EGG_SIZE + 0.9, 0)
	gui.MaxDistance = LABEL_DISTANCE
	gui.LightInfluence = 0
	gui.Parent = egg
	for index, line in
		{
			{
				text = `TIER {tier}  ·  {string.upper(tierDef.name)}`,
				color = tierDef.color,
				size = 15,
			},
			{ text = string.upper(rarity.displayName), color = rarity.color, size = 20 },
		}
	do
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Position = UDim2.fromScale(0, if index == 1 then 0 else 0.42)
		text.Size = UDim2.fromScale(1, if index == 1 then 0.42 else 0.58)
		text.Font = Enum.Font.GothamBlack
		text.TextSize = line.size
		text.Text = line.text
		text.TextColor3 = Color3.fromHex(line.color)
		text.TextStrokeTransparency = 0.25
		text.TextStrokeColor3 = Color3.new(0, 0, 0)
		text.Parent = gui
	end
end

-- Shows the egg the attributes describe (no animation).
local function settle(lab: Lab)
	local rarity = lab.model:GetAttribute("Rarity")
	local tier = lab.model:GetAttribute("Tier")
	local def = if type(rarity) == "string" then P.RARITIES[rarity] else nil
	local tierNumber = if type(tier) == "number" and P.TIERS[tier] then tier else 1
	local key = if def then `{def.id}#{tierNumber}` else ""
	if key == lab.shown and lab.egg then
		return
	end
	lab.shown = key
	if def then
		label(makeEgg(lab, Color3.fromHex(def.color), tierNumber, false), def, tierNumber)
	else
		makeEgg(lab, IDLE_COLOR, nil, true)
	end
end

-- The roll: shake and flicker, then reveal with a burst.
local function roll(lab: Lab)
	local rolledAt = lab.model:GetAttribute("RolledAt")
	if
		type(rolledAt) ~= "number"
		or Workspace:GetServerTimeNow() - rolledAt > E.ROLL_SECONDS + 1
	then
		settle(lab)
		return
	end
	local seconds = if reduced() then math.min(E.ROLL_SECONDS, 0.3) else E.ROLL_SECONDS
	lab.rollingUntil = os.clock() + seconds
	lab.shown = "rolling"
	makeEgg(lab, Color3.new(1, 1, 1), nil, false)
	task.delay(seconds, function()
		if labs[lab.model] ~= lab then
			return
		end
		lab.rollingUntil = 0
		settle(lab)
		local rarity = lab.model:GetAttribute("Rarity")
		local tier = lab.model:GetAttribute("Tier")
		local def = if type(rarity) == "string" then P.RARITIES[rarity] else nil
		local egg = lab.egg
		if def == nil or egg == nil then
			return
		end
		local color = Color3.fromHex(def.color)
		local big = def.index >= P.RARITIES[E.ANNOUNCE_RARITY].index
			or (type(tier) == "number" and tier >= E.ANNOUNCE_TIER)
		StarFx.birth(egg.Position, if big then 2.2 else 1.2, color)
		if big and type(tier) == "number" and P.TIERS[tier] then
			StarFx.levelUp(egg.Position, 1.6, Color3.fromHex(P.TIERS[tier].color))
		end
	end)
end

local function add(model: Instance)
	if not model:IsA("Model") or labs[model] then
		return
	end
	local spot = model:WaitForChild("EggSpot", 10)
	if spot == nil or not spot:IsA("BasePart") or model.Parent == nil then
		return
	end
	local lab: Lab = {
		model = model,
		spot = spot,
		egg = nil,
		rollingUntil = 0,
		shown = "",
		connections = {},
	}
	labs[model] = lab
	settle(lab)
	-- Only the owner opens their lab.
	local mine = model:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
	for _, item in model:GetDescendants() do
		if item:IsA("ProximityPrompt") then
			item.Enabled = mine
		elseif item:IsA("ClickDetector") and not mine then
			-- Visitors can't press another player's ROLL and KEEP buttons.
			item.MaxActivationDistance = 0
		end
	end
	table.insert(
		lab.connections,
		model:GetAttributeChangedSignal("RolledAt"):Connect(function()
			roll(lab)
		end)
	)
	for _, name in { "Rarity", "Tier" } do
		table.insert(
			lab.connections,
			model:GetAttributeChangedSignal(name):Connect(function()
				if lab.rollingUntil == 0 then
					settle(lab)
				end
			end)
		)
	end
end

local function remove(model: Instance)
	local lab = labs[model :: Model]
	if lab == nil then
		return
	end
	labs[model :: Model] = nil
	for _, connection in lab.connections do
		connection:Disconnect()
	end
	if lab.egg then
		lab.egg:Destroy()
	end
end

local function step()
	local clock = os.clock()
	local calm = reduced()
	for _, lab in labs do
		local egg = lab.egg
		if egg == nil or egg.Parent == nil then
			continue
		end
		local base = lab.spot.CFrame
		if lab.rollingUntil > clock then
			-- Rolling: a fast wobble and a flicker through the rarity colours.
			local left = lab.rollingUntil - clock
			local index = math.floor(clock * 14) % #P.RARITY_ORDER + 1
			egg.Color = Color3.fromHex(P.RARITIES[P.RARITY_ORDER[index]].color)
			local shake = if calm then 0 else math.sin(clock * 40) * 0.25 * math.min(left * 2, 1)
			egg.CFrame = base * CFrame.Angles(0, clock * 12, shake)
		elseif not calm then
			egg.CFrame = base
				* CFrame.new(0, math.sin(clock * 2) * BOB, 0)
				* CFrame.Angles(0, clock * TURN, 0)
		end
	end
end

function EggLabController.init() end

function EggLabController.start()
	for _, model in CollectionService:GetTagged(TAG) do
		task.spawn(add, model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(model)
		task.spawn(add, model)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
	RunService.RenderStepped:Connect(step)
end

return EggLabController
