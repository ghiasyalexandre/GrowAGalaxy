--!strict
-- Helpers for building greybox geometry from code: anchored parts, invisible
-- markers, text signs, consoles and proximity prompts.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local COLORS = Config.World.COLORS

-- Tag on every navigation prompt; NavigationSystem listens for it.
local WARP_TAG = "WarpPrompt"

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
}

local Build = {}

Build.WARP_TAG = WARP_TAG

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
	prompt.Parent = parent
	return prompt
end

return Build
