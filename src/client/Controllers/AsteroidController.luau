--!strict
-- Asteroid effects, purely local and visual:
--   * rock glows and cracks as its extraction progress (server attribute
--     "Progress") rises,
--   * the weak point of the asteroid your beam is extracting is outlined,
--   * a broken asteroid (attribute "Broken") vanishes in a burst of debris,
--     with a sound,
--   * while flying, scanner markers show the nearest asteroids and their
--     distance (grey when someone else is mining one).
-- The server owns every value; this only reads the attributes it sets on
-- Workspace/Asteroids/Asteroid_<id> and on your ship (MiningTarget).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local A = Config.Asteroids
local CRACK_COLOR = Color3.fromHex(A.CRACK_COLOR)
local WEAK_COLOR = Color3.fromHex(A.WEAK_POINT_COLOR)
-- How far towards CRACK_COLOR the rock goes at full progress.
local CRACK_TINT = 0.65
-- Progress at which the rock's surface turns into glowing cracks.
local CRACK_MATERIAL_AT = 0.5
local BURST_PARTICLES = 36
local BURST_LIFETIME = 3 -- long enough for the break sound
local MARKER_FREE = Color3.fromHex(A.WEAK_POINT_COLOR)
local MARKER_TAKEN = Color3.fromRGB(150, 150, 160)

type Rock = { part: BasePart, color: Color3, material: Enum.Material }

type Visual = {
	model: Model,
	rocks: { Rock },
	weakPoint: BasePart?,
	connections: { RBXScriptConnection },
}

local AsteroidController = {}

local visuals: { [Model]: Visual } = {}
local byId: { [number]: Visual } = {}
local highlight: Highlight
local shipConnection: RBXScriptConnection? = nil
local markers: { BillboardGui } = {}

local function applyProgress(v: Visual)
	local progress = v.model:GetAttribute("Progress")
	local share = if type(progress) == "number" then math.clamp(progress, 0, 1) else 0
	for _, rock in v.rocks do
		rock.part.Color = rock.color:Lerp(CRACK_COLOR, share * CRACK_TINT)
		rock.part.Material = if share >= CRACK_MATERIAL_AT
			then Enum.Material.CrackedLava
			else rock.material
	end
end

local function burst(position: Vector3, size: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "GaG_AsteroidBurst"
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(size * 1.5, size * 3.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new(CRACK_COLOR, WEAK_COLOR)
	emitter.LightEmission = 0.8
	emitter.Drag = 1.5
	emitter.Parent = attachment
	emitter:Emit(BURST_PARTICLES)

	if A.BREAK_SOUND ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = A.BREAK_SOUND
		sound.Volume = A.BREAK_SOUND_VOLUME
		sound.RollOffMinDistance = 20
		sound.RollOffMaxDistance = 600
		sound.Parent = attachment
		sound:Play()
	end

	Debris:AddItem(attachment, BURST_LIFETIME)
end

local function breakApart(v: Visual)
	local rock = v.model.PrimaryPart
	if rock then
		burst(rock.Position, rock.Size.X / 2)
	end
	for _, descendant in v.model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
		end
	end
end

local function refreshHighlight()
	local ship = ClientState.ship
	local target = if ship then ship:GetAttribute("MiningTarget") else nil
	local v = if type(target) == "number" then byId[target] else nil
	highlight.Adornee = if v then v.weakPoint else nil
	highlight.Enabled = v ~= nil and v.weakPoint ~= nil
end

local function add(model: Instance)
	if not model:IsA("Model") or visuals[model] then
		return
	end
	local v: Visual = { model = model, rocks = {}, weakPoint = nil, connections = {} }
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			if part.Name == "WeakPoint" then
				v.weakPoint = part
			else
				table.insert(v.rocks, { part = part, color = part.Color, material = part.Material })
			end
		end
	end
	visuals[model] = v
	local id = model:GetAttribute("AsteroidId")
	if type(id) == "number" then
		byId[id] = v
	end

	table.insert(
		v.connections,
		model:GetAttributeChangedSignal("Progress"):Connect(function()
			applyProgress(v)
		end)
	)
	table.insert(
		v.connections,
		model:GetAttributeChangedSignal("Broken"):Connect(function()
			if model:GetAttribute("Broken") == true then
				breakApart(v)
			end
		end)
	)
	applyProgress(v)
	if model:GetAttribute("Broken") == true then
		breakApart(v)
	end
	refreshHighlight()
end

local function remove(child: Instance)
	local v = if child:IsA("Model") then visuals[child] else nil
	if v == nil then
		return
	end
	local model = v.model
	visuals[model] = nil
	local id = model:GetAttribute("AsteroidId")
	if type(id) == "number" and byId[id] == v then
		byId[id] = nil
	end
	for _, connection in v.connections do
		connection:Disconnect()
	end
	refreshHighlight()
end

local function makeMarker(parent: Instance): BillboardGui
	local marker = Instance.new("BillboardGui")
	marker.Name = "GaG_AsteroidMarker"
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.Size = UDim2.fromOffset(80, 34)
	marker.Enabled = false
	marker.Parent = parent

	local diamond = Instance.new("Frame")
	diamond.Name = "Diamond"
	diamond.AnchorPoint = Vector2.new(0.5, 0)
	diamond.Position = UDim2.fromScale(0.5, 0)
	diamond.Size = UDim2.fromOffset(10, 10)
	diamond.Rotation = 45
	diamond.BackgroundTransparency = 1
	diamond.Parent = marker
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = MARKER_FREE
	stroke.Parent = diamond

	local label = Instance.new("TextLabel")
	label.Name = "Distance"
	label.Position = UDim2.fromOffset(0, 14)
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = MARKER_FREE
	label.TextStrokeTransparency = 0.4
	label.Parent = marker
	return marker
end

-- Points markers at the nearest unbroken asteroids within SCAN_RANGE.
local function scan()
	local ship = ClientState.ship
	local hull = if ship and ClientState.mode == "ship" then ship.PrimaryPart else nil
	local found: { { v: Visual, rock: BasePart, distance: number } } = {}
	if hull then
		local origin = hull.Position
		for _, v in visuals do
			local rock = v.model.PrimaryPart
			if rock and v.model:GetAttribute("Broken") ~= true then
				local distance = (rock.Position - origin).Magnitude
				if distance <= A.SCAN_RANGE then
					table.insert(found, { v = v, rock = rock, distance = distance })
				end
			end
		end
		table.sort(found, function(a, b)
			return a.distance < b.distance
		end)
	end
	local myId = Players.LocalPlayer.UserId
	for index, marker in markers do
		local entry = found[index]
		if entry == nil then
			marker.Enabled = false
			continue
		end
		local reservedBy = entry.v.model:GetAttribute("ReservedBy")
		local taken = type(reservedBy) == "number" and reservedBy ~= 0 and reservedBy ~= myId
		local color = if taken then MARKER_TAKEN else MARKER_FREE
		local label = marker:FindFirstChild("Distance") :: TextLabel
		local stroke = (marker:FindFirstChild("Diamond") :: Frame):FindFirstChildOfClass("UIStroke")
		label.Text = `{math.floor(entry.distance)}`
		label.TextColor3 = color
		if stroke then
			stroke.Color = color
		end
		marker.Adornee = entry.rock
		marker.Enabled = true
	end
end

local function watchShip()
	if shipConnection then
		shipConnection:Disconnect()
		shipConnection = nil
	end
	local ship = ClientState.ship
	if ship then
		shipConnection = ship:GetAttributeChangedSignal("MiningTarget"):Connect(refreshHighlight)
	end
	refreshHighlight()
end

function AsteroidController.init()
	highlight = Instance.new("Highlight")
	highlight.Name = "GaG_WeakPointHighlight"
	highlight.FillColor = WEAK_COLOR
	highlight.FillTransparency = 0.4
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = Workspace.CurrentCamera

	-- Local-only, like the highlight; survives respawns.
	local folder = Instance.new("Folder")
	folder.Name = "GaG_AsteroidScanner"
	folder.Parent = Workspace.CurrentCamera
	for index = 1, A.SCAN_MARKERS do
		markers[index] = makeMarker(folder)
	end
end

function AsteroidController.start()
	ClientState.shipChanged:Connect(watchShip)
	watchShip()
	task.spawn(function()
		local folder = Workspace:WaitForChild("Asteroids")
		folder.ChildAdded:Connect(add)
		folder.ChildRemoved:Connect(remove)
		for _, child in folder:GetChildren() do
			add(child)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(A.SCAN_INTERVAL)
			scan()
		end
	end)
end

return AsteroidController
