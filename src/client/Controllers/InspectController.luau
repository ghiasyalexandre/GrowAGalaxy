--!strict
-- Inspecting a solar system (any player's): the camera orbits the star, its
-- planets get labels with the length of their year, and a panel shows the
-- system with a time slider. The slider sets how fast the system's time runs,
-- from an hour to three decades per second (Logic/OrbitTime, on a log scale),
-- by driving the orbit clock every client draws planets with
-- (StarController.clock). Pause stops time; "Normal" returns to the shared
-- speed. Purely local: nothing is sent to the server.
--
-- Opened from the star's Inspect prompt (R) or the Manage panel
-- (ClientState.inspectStar). Controls: drag to orbit, mouse wheel or D-pad
-- up/down to zoom, right stick to orbit on a gamepad, D-pad left/right moves
-- the slider, Backspace / B leaves. While inspecting, ClientState.inspecting
-- tells the ship to coast to a stop and leave the camera alone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local PlacementController = require(script.Parent.PlacementController)
local StarController = require(script.Parent.StarController)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local OrbitTime = require(Shared:WaitForChild("Logic"):WaitForChild("OrbitTime"))
local StarMath = require(Shared:WaitForChild("Logic"):WaitForChild("StarMath"))

local S = Config.Stars
local P = Config.Planets
local C = Theme.COLORS

local RENDER_STEP = "GaG_Inspect"
local DRIFT = 0.06 -- radians per second the camera drifts round on its own
local DRAG_SPEED = 0.006 -- radians per pixel
local STICK_SPEED = 1.8 -- radians per second at full stick
local MAX_PITCH = math.rad(80)
local ZOOM_STEP = 0.88
local SLIDER_STEP = 0.04
local LABEL_REFRESH = 0.5

local InspectController = {}

local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local ownerLabel: TextLabel
local rateLabel: TextLabel
local elapsedLabel: TextLabel
local sliderTrack: TextButton
local sliderFill: Frame
local sliderKnob: GuiObject
local pauseButton: TextButton
local labelFolder: Folder

local current: Model? = nil
local yaw = 0
local pitch = math.rad(25)
local distance = 300
local minDistance = 60
local maxDistance = 900
local dragging = false
local sliding = false
local position = OrbitTime.positionOf(S.ORBIT_DEFAULT_RATE) -- slider, kept between visits
local startTime = 0 -- clock time when the view opened
local labels: { [Part]: BillboardGui } = {}
local sinceLabels = 0

local function setButtonText(button: TextButton, text: string)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	else
		button.Text = text
	end
end

local function applyRate()
	local clock = StarController.clock
	clock.rate = OrbitTime.rateAt(position)
	sliderFill.Size = UDim2.fromScale(position, 1)
	sliderKnob.Position = UDim2.fromScale(position, 0.5)
	rateLabel.Text = OrbitTime.describeRate(clock.rate :: number)
		.. (if clock.paused then "  (paused)" else "")
	setButtonText(pauseButton, if clock.paused then "Play" else "Pause")
end

local function setPosition(value: number)
	position = math.clamp(value, 0, 1)
	applyRate()
end

local function slideTo(x: number)
	local left = sliderTrack.AbsolutePosition.X
	local width = math.max(sliderTrack.AbsoluteSize.X, 1)
	setPosition((x - left) / width)
end

-- Labels over each planet: its name and how long its year is.
local function refreshLabels(model: Model)
	local seen: { [Part]: boolean } = {}
	for _, planet in StarController.planetsOf(model) do
		seen[planet.part] = true
		if not labels[planet.part] then
			local def = P.BY_ID[planet.id]
			local slot = S.SLOTS[planet.slot]
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromOffset(170, 34)
			billboard.StudsOffsetWorldSpace = Vector3.new(0, (planet.part.Size.Y / 2) + 4, 0)
			billboard.AlwaysOnTop = true
			billboard.LightInfluence = 0
			billboard.Adornee = planet.part
			billboard.Parent = labelFolder
			Theme.label(billboard, {
				Size = UDim2.new(1, 0, 0.55, 0),
				Text = if def then def.displayName else planet.id,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextStrokeTransparency = 0.3,
				TextColor3 = if def
					then Color3.fromHex(def.color):Lerp(Color3.new(1, 1, 1), 0.4)
					else C.text,
			})
			Theme.label(billboard, {
				Position = UDim2.fromScale(0, 0.55),
				Size = UDim2.new(1, 0, 0.45, 0),
				Text = `Orbit {planet.slot}  ·  year: {OrbitTime.describe(
					slot.periodDays * OrbitTime.DAY
				)}`,
				TextScaled = true,
				Font = Enum.Font.Gotham,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextStrokeTransparency = 0.3,
				TextColor3 = C.subtle,
			})
			labels[planet.part] = billboard
		end
	end
	for part, billboard in labels do
		if not seen[part] then
			billboard:Destroy()
			labels[part] = nil
		end
	end
end

local function refreshPanel(model: Model)
	local typeId = model:GetAttribute("TypeId")
	local level = model:GetAttribute("Level")
	local def = if type(typeId) == "string" then S.BY_ID[typeId] else nil
	if def and type(level) == "number" then
		titleLabel.Text =
			`{def.displayName}  ·  level {level}/{StarMath.maxLevel(def.id)}  ·  {#StarController.planetsOf(
				model
			)}/{StarMath.slots(def.id)} planets`
		titleLabel.TextColor3 = Color3.fromHex(def.light)
	end
	local ownerId = model:GetAttribute("OwnerUserId")
	local owner = if type(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	ownerLabel.Text = if owner == Players.LocalPlayer
		then "Your solar system"
		elseif owner then `{owner.DisplayName}'s solar system`
		else "A solar system"
end

function InspectController.close()
	if current == nil then
		return
	end
	current = nil
	dragging = false
	sliding = false
	RunService:UnbindFromRenderStep(RENDER_STEP)
	local clock = StarController.clock
	clock.rate = nil
	clock.paused = false
	for _, billboard in labels do
		billboard:Destroy()
	end
	table.clear(labels)
	gui.Enabled = false
	ClientState.inspecting = false
	StarController.setPromptsShown(true)
	-- Flying, the ship's chase camera takes over again by itself.
	local camera = Workspace.CurrentCamera
	if ClientState.mode ~= "ship" then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = Config.Movement.CAMERA_FOV
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local function update(dt: number)
	local model = current
	local core = if model then (model.PrimaryPart or model:FindFirstChild("Core")) else nil
	if model == nil or model.Parent == nil or core == nil or not core:IsA("BasePart") then
		InspectController.close()
		return
	end
	-- Gamepad: right stick orbits, D-pad zooms and slides.
	for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if state.KeyCode == Enum.KeyCode.Thumbstick2 and state.Position.Magnitude > 0.15 then
			yaw -= state.Position.X * STICK_SPEED * dt
			pitch = math.clamp(pitch + state.Position.Y * STICK_SPEED * dt, -MAX_PITCH, MAX_PITCH)
		end
	end
	if not dragging then
		yaw += DRIFT * dt
	end
	local center = core.Position
	local eye = center
		+ (CFrame.Angles(0, yaw, 0) * CFrame.Angles(-pitch, 0, 0)):VectorToWorldSpace(
			Vector3.new(0, 0, distance)
		)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(eye, center)
	camera.FieldOfView = 60

	local clock = StarController.clock
	elapsedLabel.Text = `Time passed: {OrbitTime.describe(math.max(clock.time - startTime, 0))}`
	sinceLabels += dt
	if sinceLabels >= LABEL_REFRESH then
		sinceLabels = 0
		refreshLabels(model)
		refreshPanel(model)
	end
end

function InspectController.open(model: Model)
	if PlacementController.isActive() then
		ClientState.notify:Fire("Finish placing first.")
		return
	end
	InspectController.close()
	local typeId = model:GetAttribute("TypeId")
	if type(typeId) ~= "string" or S.BY_ID[typeId] == nil then
		return
	end
	current = model
	ClientState.inspecting = true
	-- The Manage and Inspect prompts would cover the system being viewed.
	StarController.setPromptsShown(false)
	-- Frame the whole system: back far enough to see its outermost orbit.
	local outer = S.SLOTS[StarMath.slots(typeId)].orbit
	distance = outer * 2.4
	minDistance = outer * 0.6
	maxDistance = outer * 5
	local camera = Workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.rad(25)
	-- Carry on from the shared clock, at the slider's speed.
	local clock = StarController.clock
	clock.time = Workspace:GetServerTimeNow() * S.ORBIT_DEFAULT_RATE
	clock.paused = false
	startTime = clock.time
	applyRate()
	refreshLabels(model)
	refreshPanel(model)
	gui.Enabled = true
	Theme.popIn(panel)
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 20, update)
end

local function build()
	gui = Theme.screen("Inspect", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	gui.DisplayOrder = 5

	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -20)
	panel.Size = UDim2.new(0.9, 0, 0, 176)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(620, 176)
	size.Parent = panel

	local titleX = 18
	local icon = Theme.icon(panel, "GalaxyOrb", 44)
	if icon then
		icon.Position = UDim2.fromOffset(14, 8)
		icon.ZIndex = 2
		titleX = 64
	end
	titleLabel = Theme.label(panel, {
		Position = UDim2.fromOffset(titleX, 12),
		Size = UDim2.new(1, -titleX - 70, 0, 22),
		TextSize = 19,
		Font = Enum.Font.GothamBlack,
	})
	ownerLabel = Theme.label(panel, {
		Position = UDim2.fromOffset(titleX, 34),
		Size = UDim2.new(1, -titleX - 70, 0, 16),
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.subtle,
	})
	Theme.closeButton(panel, InspectController.close)

	-- Time slider: an hour per second on the left, three decades on the right.
	Theme.label(panel, {
		Position = UDim2.fromOffset(18, 62),
		Size = UDim2.fromOffset(110, 18),
		Text = "SYSTEM TIME",
		TextSize = 13,
		Font = Enum.Font.GothamBlack,
		TextColor3 = C.gold,
	})
	rateLabel = Theme.label(panel, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 62),
		Size = UDim2.fromOffset(220, 18),
		TextSize = 15,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	sliderTrack = Instance.new("TextButton")
	sliderTrack.Name = "Slider"
	sliderTrack.Text = ""
	sliderTrack.AutoButtonColor = false
	sliderTrack.BackgroundTransparency = 1
	sliderTrack.Position = UDim2.fromOffset(28, 86)
	sliderTrack.Size = UDim2.new(1, -56, 0, 22)
	sliderTrack.Parent = panel
	sliderFill = Theme.progress(sliderTrack, position, C.gold, 12)
	local track = sliderFill.Parent :: Frame
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(0, 0.5)
	track.Size = UDim2.new(1, 0, 0, Theme.barHeight(12))
	local knobIcon = Theme.icon(sliderTrack, "Stardust", 34)
	if knobIcon then
		sliderKnob = knobIcon
	else
		local knob = Instance.new("Frame")
		knob.Size = UDim2.fromOffset(22, 22)
		knob.BackgroundColor3 = Color3.new(1, 1, 1)
		knob.Parent = sliderTrack
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = knob
		local edge = Instance.new("UIStroke")
		edge.Color = C.gold
		edge.Thickness = 3
		edge.Parent = knob
		sliderKnob = knob
	end
	sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	sliderKnob.ZIndex = 3
	local rates = { 3600, OrbitTime.DAY, OrbitTime.YEAR, S.INSPECT_RATE_MAX }
	for index, text in { "1 hour / s", "1 day / s", "1 year / s", "3 decades / s" } do
		-- Under the matching point of the track (28 px in from each side).
		local at = OrbitTime.positionOf(rates[index])
		Theme.label(panel, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(at, 28 - 56 * at, 0, 110),
			Size = UDim2.fromOffset(90, 14),
			Text = text,
			TextSize = 11,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.subtle,
		})
	end
	sliderTrack.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			sliding = true
			slideTo(input.Position.X)
		end
	end)

	pauseButton = Theme.button(panel, "Pause", "primary", function()
		local clock = StarController.clock
		clock.paused = not clock.paused
		applyRate()
	end)
	pauseButton.Position = UDim2.new(0, 18, 1, -44)
	pauseButton.Size = UDim2.fromOffset(110, 32)
	Theme.buttonIcon(pauseButton, "Play")
	local normal = Theme.button(panel, "Normal", "special", function()
		setPosition(OrbitTime.positionOf(S.ORBIT_DEFAULT_RATE))
	end)
	normal.Position = UDim2.new(0, 136, 1, -44)
	normal.Size = UDim2.fromOffset(110, 32)
	elapsedLabel = Theme.label(panel, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -28),
		Size = UDim2.new(1, -280, 0, 16),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	Theme.label(panel, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -10),
		Size = UDim2.new(1, -280, 0, 14),
		Text = "Drag to orbit  ·  wheel to zoom  ·  Backspace to leave",
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.subtle,
	})

	labelFolder = Instance.new("Folder")
	labelFolder.Name = "GaG_InspectLabels"
end

function InspectController.init()
	build()
end

function InspectController.start()
	labelFolder.Parent = Workspace.CurrentCamera
	ClientState.inspectStar:Connect(InspectController.open)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if current == nil then
			return
		end
		local kind = input.UserInputType
		if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.ButtonB then
			InspectController.close()
		elseif input.KeyCode == Enum.KeyCode.DPadLeft then
			setPosition(position - SLIDER_STEP)
		elseif input.KeyCode == Enum.KeyCode.DPadRight then
			setPosition(position + SLIDER_STEP)
		elseif input.KeyCode == Enum.KeyCode.DPadUp then
			distance = math.max(minDistance, distance * ZOOM_STEP)
		elseif input.KeyCode == Enum.KeyCode.DPadDown then
			distance = math.min(maxDistance, distance / ZOOM_STEP)
		elseif
			not processed
			and (
				kind == Enum.UserInputType.MouseButton1
				or kind == Enum.UserInputType.MouseButton2
				or kind == Enum.UserInputType.Touch
			)
		then
			dragging = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if current == nil then
			return
		end
		local kind = input.UserInputType
		if
			sliding
			and (kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch)
		then
			slideTo(input.Position.X)
		elseif
			dragging
			and (kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch)
		then
			yaw -= input.Delta.X * DRAG_SPEED
			pitch = math.clamp(pitch + input.Delta.Y * DRAG_SPEED, -MAX_PITCH, MAX_PITCH)
		elseif kind == Enum.UserInputType.MouseWheel and not processed then
			local step = if input.Position.Z > 0 then ZOOM_STEP else 1 / ZOOM_STEP
			distance = math.clamp(distance * step, minDistance, maxDistance)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if
			kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.MouseButton2
			or kind == Enum.UserInputType.Touch
		then
			dragging = false
			sliding = false
		end
	end)
end

return InspectController
