--!strict
-- Builds the tycoon plots, assigns one to each player, and runs the
-- dropper -> conveyor -> furnace loop. All buying is server-authoritative:
-- pads are physical, and the server checks owner, reach, order, and cost.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local DataSystem = require(script.Parent.DataSystem)

-- Local layout of a plot. -Z faces the hub, the belt runs along +X.
local BELT_Z = 6
local BELT_START_X = -28
local BELT_END_X = 24
local PAD_Z = 20
local FIRST_SLOT_X = -24
local SLOT_SPACING = 10
local DROPPER_Y = 10
local ORE_SPAWN_Y = 7

type Plot = {
	index: number,
	origin: CFrame,
	model: Model,
	droppers: Folder,
	ores: Folder,
	pads: { BasePart },
	signLabel: TextLabel,
	owner: Player?,
	oreCount: number,
	generation: number,
}

local TycoonSystem = {}

local plots: { Plot } = {}
local plotByPlayer: { [Player]: Plot } = {}
local padCooldown: { [Player]: boolean } = {}

local function makePart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeBillboard(adornee: BasePart, text: string, offsetY: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Adornee = adornee
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	return label
end

local function slotX(slot: number): number
	return FIRST_SLOT_X + (slot - 1) * SLOT_SPACING
end

local function spawnOre(plot: Plot, slot: number)
	if plot.oreCount >= Config.MAX_ORE_PER_PLOT then
		return
	end
	local def = Config.DROPPERS[slot]
	local ore = Instance.new("Part")
	ore.Name = "Ore"
	ore.Size = Vector3.one * 1.5
	ore.Material = Enum.Material.Neon
	ore.Color = def.color
	ore.CFrame = plot.origin * CFrame.new(slotX(slot), ORE_SPAWN_Y, BELT_Z)
	ore:SetAttribute("Value", def.oreValue)
	ore.Parent = plot.ores
	ore:SetNetworkOwner(nil)

	plot.oreCount += 1
	ore.Destroying:Connect(function()
		plot.oreCount -= 1
	end)
	Debris:AddItem(ore, Config.ORE_LIFETIME)
end

local function startDropper(plot: Plot, slot: number)
	local generation = plot.generation
	local def = Config.DROPPERS[slot]
	task.spawn(function()
		while plot.generation == generation do
			spawnOre(plot, slot)
			task.wait(def.dropInterval)
		end
	end)
end

local function buildDropper(plot: Plot, slot: number)
	local def = Config.DROPPERS[slot]
	local x = slotX(slot)
	local model = Instance.new("Model")
	model.Name = def.id

	makePart(
		"Housing",
		Vector3.new(5, 3, 5),
		plot.origin * CFrame.new(x, DROPPER_Y, BELT_Z),
		Color3.fromRGB(50, 50, 70),
		Enum.Material.DiamondPlate,
		model
	)
	makePart(
		"Core",
		Vector3.new(2.5, 1, 2.5),
		plot.origin * CFrame.new(x, DROPPER_Y - 2, BELT_Z),
		def.color,
		Enum.Material.Neon,
		model
	)
	for _, side in { -1, 1 } do
		makePart(
			"Leg",
			Vector3.new(1, DROPPER_Y, 1),
			plot.origin * CFrame.new(x, DROPPER_Y / 2, BELT_Z + side * 4),
			Color3.fromRGB(50, 50, 70),
			Enum.Material.Metal,
			model
		)
	end
	model.Parent = plot.droppers
end

local function refreshPads(plot: Plot)
	local owner = plot.owner
	for slot, pad in plot.pads do
		local visible = false
		if owner then
			local def = Config.DROPPERS[slot]
			local previousOwned = slot == 1 or DataSystem.owns(owner, Config.DROPPERS[slot - 1].id)
			visible = previousOwned and not DataSystem.owns(owner, def.id)
		end
		pad.Parent = if visible then plot.model else nil
	end
end

local function flashPad(pad: BasePart, color: Color3)
	local original = pad.Color
	pad.Color = color
	task.delay(0.3, function()
		pad.Color = original
	end)
end

local function tryBuy(plot: Plot, slot: number, player: Player)
	if plot.owner ~= player then
		return
	end
	local def = Config.DROPPERS[slot]
	if DataSystem.owns(player, def.id) then
		return
	end
	if slot > 1 and not DataSystem.owns(player, Config.DROPPERS[slot - 1].id) then
		return
	end
	if not DataSystem.trySpend(player, def.cost) then
		flashPad(plot.pads[slot], Color3.fromRGB(255, 70, 70))
		return
	end
	DataSystem.markOwned(player, def.id)
	buildDropper(plot, slot)
	startDropper(plot, slot)
	refreshPads(plot)
end

local function onPadTouched(plot: Plot, slot: number, hit: BasePart)
	local character = hit.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player or player ~= plot.owner or padCooldown[player] then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	-- Touches can be faked by exploiters; require the character to really be here.
	if (root.Position - plot.pads[slot].Position).Magnitude > Config.PAD_REACH then
		return
	end

	padCooldown[player] = true
	task.delay(0.5, function()
		padCooldown[player] = nil
	end)
	tryBuy(plot, slot, player)
end

local function buildPlot(index: number): Plot
	local angle = (index - 1) / Config.PLOT_COUNT * math.pi * 2
	local center = Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.PLOT_RING_RADIUS
	local origin = CFrame.lookAt(center, Vector3.zero)
	local half = Config.PLOT_SIZE / 2

	local model = Instance.new("Model")
	model.Name = `Plot{index}`

	makePart(
		"Base",
		Vector3.new(Config.PLOT_SIZE, 1, Config.PLOT_SIZE),
		origin * CFrame.new(0, -0.5, 0),
		Color3.fromRGB(30, 30, 50),
		Enum.Material.Slate,
		model
	)

	-- Walkway back to the hub.
	local gap = Config.PLOT_RING_RADIUS - half - Config.HUB_SIZE / 2
	makePart(
		"Bridge",
		Vector3.new(10, 1, gap),
		origin * CFrame.new(0, -0.5, -(half + gap / 2)),
		Color3.fromRGB(60, 60, 90),
		Enum.Material.Glass,
		model
	)

	local beltLength = BELT_END_X - BELT_START_X
	local beltMidX = (BELT_START_X + BELT_END_X) / 2
	local belt = makePart(
		"Conveyor",
		Vector3.new(beltLength, 1, 6),
		origin * CFrame.new(beltMidX, 0.5, BELT_Z),
		Color3.fromRGB(25, 25, 30),
		Enum.Material.Metal,
		model
	)
	belt.AssemblyLinearVelocity = origin.RightVector * Config.CONVEYOR_SPEED

	for _, side in { -1, 1 } do
		makePart(
			"Rail",
			Vector3.new(beltLength, 2, 0.5),
			origin * CFrame.new(beltMidX, 2, BELT_Z + side * 3.25),
			Color3.fromRGB(80, 80, 110),
			Enum.Material.Metal,
			model
		)
	end
	makePart(
		"BackStop",
		Vector3.new(0.5, 2, 6),
		origin * CFrame.new(BELT_START_X - 0.25, 2, BELT_Z),
		Color3.fromRGB(80, 80, 110),
		Enum.Material.Metal,
		model
	)

	local furnace = makePart(
		"StarFurnace",
		Vector3.new(6, 6, 8),
		origin * CFrame.new(BELT_END_X + 3, 3, BELT_Z),
		Color3.fromRGB(255, 140, 40),
		Enum.Material.Neon,
		model
	)
	makeBillboard(furnace, "Star Furnace", 5)

	local signPost = makePart(
		"Sign",
		Vector3.new(1, 8, 1),
		origin * CFrame.new(0, 4, -half + 4),
		Color3.fromRGB(80, 80, 110),
		Enum.Material.Metal,
		model
	)
	local signLabel = makeBillboard(signPost, "Unclaimed Galaxy", 6)

	local droppers = Instance.new("Folder")
	droppers.Name = "Droppers"
	droppers.Parent = model

	local ores = Instance.new("Folder")
	ores.Name = "Ores"
	ores.Parent = model

	local plot: Plot = {
		index = index,
		origin = origin,
		model = model,
		droppers = droppers,
		ores = ores,
		pads = {},
		signLabel = signLabel,
		owner = nil,
		oreCount = 0,
		generation = 0,
	}

	furnace.Touched:Connect(function(hit)
		if hit.Parent ~= ores then
			return
		end
		local value = hit:GetAttribute("Value")
		hit:Destroy()
		local owner = plot.owner
		if owner and typeof(value) == "number" then
			DataSystem.addStardust(owner, value)
		end
	end)

	for slot, def in Config.DROPPERS do
		local pad = makePart(
			`BuyPad_{def.id}`,
			Vector3.new(6, 0.4, 6),
			origin * CFrame.new(slotX(slot), 0.2, PAD_Z),
			Color3.fromRGB(80, 220, 120),
			Enum.Material.Neon,
			model
		)
		makeBillboard(pad, `{def.displayName}\n✦ {Format.abbreviate(def.cost)}`, 4)
		pad.Touched:Connect(function(hit)
			onPadTouched(plot, slot, hit)
		end)
		plot.pads[slot] = pad
	end

	refreshPads(plot)
	model.Parent = workspace
	return plot
end

local function teleportToPlot(player: Player, plot: Plot)
	local character = player.Character
	if character then
		character:PivotTo(plot.origin * CFrame.new(0, 4, -Config.PLOT_SIZE / 2 + 10))
	end
end

local function claimPlot(player: Player)
	if not DataSystem.waitForProfile(player) then
		return
	end
	local plot: Plot? = nil
	for _, candidate in plots do
		if not candidate.owner then
			plot = candidate
			break
		end
	end
	if not plot then
		warn(`[TycoonSystem] no free plot for {player.Name}; raise PLOT_COUNT or lower max players`)
		return
	end

	plot.owner = player
	plotByPlayer[player] = plot
	plot.signLabel.Text = `{player.DisplayName}'s Galaxy`

	for slot, def in Config.DROPPERS do
		if DataSystem.owns(player, def.id) then
			buildDropper(plot, slot)
			startDropper(plot, slot)
		end
	end
	refreshPads(plot)

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart")
		if plotByPlayer[player] == plot then
			teleportToPlot(player, plot)
		end
	end)
	teleportToPlot(player, plot)
end

local function releasePlot(player: Player)
	padCooldown[player] = nil
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	plotByPlayer[player] = nil
	plot.owner = nil
	plot.generation += 1
	plot.droppers:ClearAllChildren()
	plot.ores:ClearAllChildren()
	plot.signLabel.Text = "Unclaimed Galaxy"
	refreshPads(plot)
end

function TycoonSystem.init()
	for index = 1, Config.PLOT_COUNT do
		table.insert(plots, buildPlot(index))
	end
end

function TycoonSystem.start()
	Players.PlayerAdded:Connect(claimPlot)
	for _, player in Players:GetPlayers() do
		task.spawn(claimPlot, player)
	end
	Players.PlayerRemoving:Connect(releasePlot)
end

return TycoonSystem
