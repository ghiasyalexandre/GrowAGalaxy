--!strict
-- Helpers for building greybox geometry from code: anchored parts, invisible
-- markers, text signs, consoles and proximity prompts.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local COLORS = Config.World.COLORS

-- Tags the server and client listen for (CollectionService tags replicate).
local WARP_TAG = "WarpPrompt" -- airlocks; NavigationSystem
local LAUNCH_TAG = "LaunchPrompt" -- hangar consoles; ShipSystem
local ROUTE_TAG = "RoutePrompt" -- navigation consoles; handled on the client
local DOCK_ZONE_TAG = "DockZone" -- assisted docking volumes
local TYCOON_TAG = "TycoonPrompt" -- star shop, collect and manage; StarSystem and the client

export type PartProps = {
	name: string?,
	size: Vector3,
	cframe: CFrame,
	color: string?, -- hex
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	collide: boolean?,
	parent: Instance,
}

export type SignProps = {
	name: string?,
	text: string,
	size: Vector3,
	cframe: CFrame,
	faces: { Enum.NormalId },
	parent: Instance,
	color: string?,
	textColor: string?,
}

export type PromptProps = {
	action: string,
	object: string,
	warp: string?, -- WarpTarget handled by NavigationSystem
	launch: string?, -- Hangar ("ISS" or "Station") handled by ShipSystem
	route: string?, -- RouteTarget ("ISS" or "Station") handled by the client
	tycoon: string?, -- TycoonAction ("Shop", "Collect", "Manage" or "Shipyard")
}

local Build = {}

Build.WARP_TAG = WARP_TAG
Build.LAUNCH_TAG = LAUNCH_TAG
Build.ROUTE_TAG = ROUTE_TAG
Build.DOCK_ZONE_TAG = DOCK_ZONE_TAG
Build.TYCOON_TAG = TYCOON_TAG

function Build.part(props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.name or "Part"
	part.Anchored = true
	part.Shape = props.shape or Enum.PartType.Block
	part.Size = props.size
	part.CFrame = props.cframe
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Color = Color3.fromHex(props.color or COLORS.hull)
	part.Transparency = props.transparency or 0
	part.CanCollide = props.collide ~= false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = props.parent
	return part
end

-- Invisible, non-colliding reference point (spawn targets, berths).
function Build.marker(name: string, cframe: CFrame, parent: Instance): Part
	local part = Build.part({
		name = name,
		size = Vector3.one,
		cframe = cframe,
		transparency = 1,
		collide = false,
		parent = parent,
	})
	part.CanQuery = false
	return part
end

function Build.model(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- Puts the same text on one or more faces of a part.
function Build.label(part: BasePart, text: string, faces: { Enum.NormalId }, textColor: string?)
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Name = `Label{face.Name}`
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.TextWrapped = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.fromHex(textColor or "#FFFFFF")

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.06, 0)
		padding.PaddingRight = UDim.new(0.06, 0)
		padding.PaddingTop = UDim.new(0.1, 0)
		padding.PaddingBottom = UDim.new(0.1, 0)
		padding.Parent = label

		label.Parent = gui
		gui.Parent = part
	end
end

function Build.sign(props: SignProps): Part
	local part = Build.part({
		name = props.name or "Sign",
		size = props.size,
		cframe = props.cframe,
		color = props.color or COLORS.console,
		parent = props.parent,
	})
	Build.label(part, props.text, props.faces, props.textColor)
	return part
end

-- A console pedestal standing on the floor point `floor`, screen facing the
-- CFrame's look direction. Returns the pedestal, which carries any prompt.
function Build.console(name: string, title: string, floor: CFrame, parent: Instance): Part
	local pedestal = Build.part({
		name = name,
		size = Vector3.new(3.2, 3.6, 1.6),
		cframe = floor * CFrame.new(0, 1.8, 0),
		color = COLORS.console,
		material = Enum.Material.Metal,
		parent = parent,
	})
	Build.label(pedestal, title, { Enum.NormalId.Front })
	Build.part({
		name = "Trim",
		size = Vector3.new(3.4, 0.3, 1.8),
		cframe = floor * CFrame.new(0, 3.75, 0),
		color = COLORS.accent,
		material = Enum.Material.Neon,
		collide = false,
		parent = pedestal,
	})
	return pedestal
end

-- Dims everything that glows under `root` by `share` (0..1): Neon parts get
-- a darker colour, lights and beams less brightness. Call once, after
-- building.
function Build.dimEmissive(root: Instance, share: number)
	local keep = 1 - math.clamp(share, 0, 1)
	local items = root:GetDescendants()
	table.insert(items, root)
	for _, item in items do
		if item:IsA("BasePart") and item.Material == Enum.Material.Neon then
			item.Color = Color3.new(item.Color.R * keep, item.Color.G * keep, item.Color.B * keep)
		elseif item:IsA("Light") or item:IsA("Beam") then
			(item :: any).Brightness *= keep
		end
	end
end

function Build.prompt(parent: BasePart, props: PromptProps): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = props.action
	prompt.ObjectText = props.object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	if props.warp then
		prompt:SetAttribute("WarpTarget", props.warp)
		CollectionService:AddTag(prompt, WARP_TAG)
	end
	if props.launch then
		prompt:SetAttribute("Hangar", props.launch)
		CollectionService:AddTag(prompt, LAUNCH_TAG)
	end
	if props.route then
		prompt:SetAttribute("RouteTarget", props.route)
		CollectionService:AddTag(prompt, ROUTE_TAG)
	end
	if props.tycoon then
		prompt:SetAttribute("TycoonAction", props.tycoon)
		CollectionService:AddTag(prompt, TYCOON_TAG)
	end
	prompt.Parent = parent
	return prompt
end

-- A marked docking volume. Ships inside it below Movement.DOCK_MAX_SPEED can
-- dock. ownerUserId 0 means anyone may dock (the ISS).
function Build.dockZone(cframe: CFrame, size: Vector3, ownerUserId: number, parent: Instance): Part
	local zone = Build.part({
		name = "DockZone",
		size = size,
		cframe = cframe,
		color = COLORS.accent,
		transparency = 0.92,
		collide = false,
		parent = parent,
	})
	zone.CanQuery = false
	zone:SetAttribute("OwnerUserId", ownerUserId)
	CollectionService:AddTag(zone, DOCK_ZONE_TAG)
	return zone
end

-- Glowing square outline on a floor, marking a ship dock.
function Build.dockOutline(floor: CFrame, size: number, parent: Instance)
	local half = size / 2
	for _, edge in
		{
			{ size = Vector3.new(size, 0.2, 0.6), offset = Vector3.new(0, 0, -half) },
			{ size = Vector3.new(size, 0.2, 0.6), offset = Vector3.new(0, 0, half) },
			{ size = Vector3.new(0.6, 0.2, size), offset = Vector3.new(-half, 0, 0) },
			{ size = Vector3.new(0.6, 0.2, size), offset = Vector3.new(half, 0, 0) },
		}
	do
		Build.part({
			name = "DockOutline",
			size = edge.size,
			cframe = floor * CFrame.new(edge.offset),
			color = COLORS.accent,
			material = Enum.Material.Neon,
			collide = false,
			parent = parent,
		})
	end
end

return Build
