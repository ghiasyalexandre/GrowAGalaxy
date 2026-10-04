--!strict
-- Placing or moving a star with a ghost preview. The ghost floats ahead of
-- the camera; the player changes its distance and height, can snap it to a
-- grid, and sees at once whether the spot is valid (green) or not (red, with
-- the reason). A faint sphere shows the room the star's planets will need.
-- Confirming asks the server (StarRequest), which re-checks everything.
--
-- Controls (bound above everything else while placing):
--   Confirm   Enter / ButtonA / touch     Cancel   Backspace / ButtonB / touch
--   Higher    E / DPadUp / touch          Lower    Q / DPadDown / touch
--   Nearer / farther: mouse wheel / DPadLeft, DPadRight
--   Snap to grid on/off: T / ButtonY

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Logic = Shared:WaitForChild("Logic")
local PlacementRules = require(Logic:WaitForChild("PlacementRules"))
local RegionMath = require(Logic:WaitForChild("RegionMath"))
local StarMath = require(Logic:WaitForChild("StarMath"))
local Types = require(Shared:WaitForChild("Types"))

local S = Config.Stars
local G = Config.Galaxy
local CURRENCY = Config.Economy.CURRENCY_NAME
local PRIORITY = Enum.ContextActionPriority.High.Value + 10
local VALID = Color3.fromRGB(90, 230, 130)
local INVALID = Color3.fromRGB(255, 80, 70)

local REASONS: { [string]: string } = {
	Invalid = "Not a valid spot",
	OutOfBounds = "Outside your galaxy (or too near its edge)",
	TooClose = "Too close to another star",
	AtCapacity = "Your galaxy is full",
}

export type Options = { mode: "place", typeId: string } | { mode: "move", starId: string }

local PlacementController = {}

local active: Options? = nil
local distance = S.GHOST_DISTANCE
local height = 0
local snapping = false
local busy = false
local ghost: Part
local footprint: Part
local info: BillboardGui
local infoText: TextLabel
local current: Types.Vec3? = nil -- region-space spot, when valid
local starSource: () -> { [string]: Model } = function()
	return {}
end
local renderConnection: RBXScriptConnection? = nil

local ACTIONS = {
	"Confirm",
	"Cancel",
	"Higher",
	"Lower",
	"Nearer",
	"Farther",
	"Snap",
	"Wheel",
}

local function regionCFrame(): CFrame?
	local slot = ClientState.mySlot()
	if slot == nil then
		return nil
	end
	local origin, yaw = RegionMath.slotOrigin(slot)
	return CFrame.new(origin.x, origin.y, origin.z) * CFrame.Angles(0, yaw, 0)
end

-- Region-space positions of my other stars (the moving one left out).
local function others(region: CFrame, except: string?): { Types.Vec3 }
	local list: { Types.Vec3 } = {}
	for id, model in starSource() do
		if id ~= except then
			local p = region:PointToObjectSpace(model:GetPivot().Position)
			table.insert(list, { x = p.X, y = p.Y, z = p.Z })
		end
	end
	return list
end

local function count(t: { [string]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function stop()
	active = nil
	current = nil
	for _, name in ACTIONS do
		ContextActionService:UnbindAction("GaG_Place" .. name)
	end
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	ghost.Parent = nil
	footprint.Parent = nil
end

local function confirm()
	local options = active
	local spot = current
	if options == nil or busy then
		return
	end
	if spot == nil then
		ClientState.notify:Fire("Find a valid (green) spot first.")
		return
	end
	busy = true
	local pos = Vector3.new(spot.x, spot.y, spot.z)
	local ok, message
	if options.mode == "place" then
		ok, message = Net.StarRequest:InvokeServer("place", options.typeId, pos)
	else
		ok, message = Net.StarRequest:InvokeServer("move", options.starId, pos)
	end
	busy = false
	if type(message) == "string" then
		ClientState.notify:Fire(message)
	end
	if ok then
		stop()
	end
end

local function update()
	local options = active
	local region = regionCFrame()
	local camera = Workspace.CurrentCamera
	local profile = ClientState.profile
	if options == nil or region == nil or camera == nil or profile == nil then
		return
	end
	local world = camera.CFrame.Position
		+ camera.CFrame.LookVector * distance
		+ Vector3.new(0, height, 0)
	local p = region:PointToObjectSpace(world)
	local spot: Types.Vec3 = { x = p.X, y = p.Y, z = p.Z }
	if snapping then
		spot = PlacementRules.snap(spot, G.GRID_SNAP * 4)
	end
	world = region:PointToWorldSpace(Vector3.new(spot.x, spot.y, spot.z))

	local except = if options.mode == "move" then options.starId else nil
	local ok, rejection = PlacementRules.checkStar(spot, profile.expansion, others(region, except))
	local lines: { string } = {}
	if options.mode == "place" then
		local owned = count(starSource())
		if not PlacementRules.hasCapacity(owned, profile.expansion) then
			ok, rejection = false, "AtCapacity"
		end
		local def = S.BY_ID[options.typeId]
		local cost = StarMath.placeCost(options.typeId, owned) or 0
		table.insert(lines, `{if def then def.displayName else "Star"}: {cost} {CURRENCY}`)
		if profile.stardust < cost then
			table.insert(lines, `You need {cost - profile.stardust} more {CURRENCY}`)
		end
	else
		table.insert(lines, "Moving star")
	end
	table.insert(
		lines,
		`Height {math.floor(spot.y)}  ·  {math.floor(distance)} studs away{if snapping
			then "  ·  snap"
			else ""}`
	)
	table.insert(
		lines,
		if ok
			then "Enter to confirm · Backspace to cancel"
			else REASONS[rejection or "Invalid"] or REASONS.Invalid
	)

	current = if ok then spot else nil
	local color = if ok then VALID else INVALID
	ghost.CFrame = CFrame.new(world)
	footprint.CFrame = ghost.CFrame
	ghost.Color = color
	footprint.Color = color
	infoText.Text = table.concat(lines, "\n")
	infoText.TextColor3 = color
end

local function handle(
	name: string,
	state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if name == "Wheel" then
		local step = if input.Position.Z > 0 then S.GHOST_STEP else -S.GHOST_STEP
		distance = math.clamp(distance + step, S.GHOST_MIN_DISTANCE, S.GHOST_MAX_DISTANCE)
		return Enum.ContextActionResult.Sink
	end
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if name == "Confirm" then
		task.spawn(confirm)
	elseif name == "Cancel" then
		stop()
		ClientState.notify:Fire("Placement cancelled.")
	elseif name == "Higher" then
		height += S.GHOST_STEP
	elseif name == "Lower" then
		height -= S.GHOST_STEP
	elseif name == "Nearer" then
		distance = math.max(S.GHOST_MIN_DISTANCE, distance - S.GHOST_STEP)
	elseif name == "Farther" then
		distance = math.min(S.GHOST_MAX_DISTANCE, distance + S.GHOST_STEP)
	elseif name == "Snap" then
		snapping = not snapping
	end
	return Enum.ContextActionResult.Sink
end

local BINDINGS: { [string]: { keys: { any }, touch: boolean } } = {
	Confirm = { keys = { Enum.KeyCode.Return, Enum.KeyCode.ButtonA }, touch = true },
	Cancel = { keys = { Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB }, touch = true },
	Higher = { keys = { Enum.KeyCode.E, Enum.KeyCode.DPadUp }, touch = true },
	Lower = { keys = { Enum.KeyCode.Q, Enum.KeyCode.DPadDown }, touch = true },
	Nearer = { keys = { Enum.KeyCode.DPadLeft }, touch = true },
	Farther = { keys = { Enum.KeyCode.DPadRight }, touch = true },
	Snap = { keys = { Enum.KeyCode.T, Enum.KeyCode.ButtonY }, touch = false },
	Wheel = { keys = { Enum.UserInputType.MouseWheel }, touch = false },
}

-- Starts placing (shop) or moving (manage panel) a star.
function PlacementController.begin(options: Options)
	if active then
		stop()
	end
	local profile = ClientState.profile
	if regionCFrame() == nil or profile == nil then
		ClientState.notify:Fire("Your galaxy isn't ready yet.")
		return
	end
	if options.mode == "place" then
		local owned = count(starSource())
		if not PlacementRules.hasCapacity(owned, profile.expansion) then
			ClientState.notify:Fire(REASONS.AtCapacity)
			return
		end
		local cost = StarMath.placeCost(options.typeId, owned) or 0
		if profile.stardust < cost then
			ClientState.notify:Fire(
				`A new star costs {cost} {CURRENCY}. Mine asteroids to earn more.`
			)
			return
		end
	end
	active = options
	distance = S.GHOST_DISTANCE
	height = 0
	local def = S.BY_ID[if options.mode == "place" then options.typeId else S.DEFAULT_TYPE]
	ghost.Size = Vector3.one * def.levels[1].starRadius * 2
	ghost.Parent = Workspace.CurrentCamera
	footprint.Parent = Workspace.CurrentCamera
	for name, binding in BINDINGS do
		ContextActionService:BindActionAtPriority("GaG_Place" .. name, function(_, state, input)
			return handle(name, state, input)
		end, binding.touch, PRIORITY, table.unpack(binding.keys))
		if binding.touch then
			ContextActionService:SetTitle("GaG_Place" .. name, name)
		end
	end
	renderConnection = RunService.RenderStepped:Connect(update)
	ClientState.notify:Fire(
		"Aim where the star should go. E / Q: higher / lower. Wheel: distance. T: snap."
	)
end

function PlacementController.isActive(): boolean
	return active ~= nil
end

-- StarController supplies the player's own star models.
function PlacementController.setStarSource(source: () -> { [string]: Model })
	starSource = source
end

function PlacementController.init()
	ghost = Instance.new("Part")
	ghost.Name = "GaG_StarGhost"
	ghost.Shape = Enum.PartType.Ball
	ghost.Material = Enum.Material.Neon
	ghost.Transparency = 0.35
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false

	footprint = Instance.new("Part")
	footprint.Name = "GaG_StarFootprint"
	footprint.Shape = Enum.PartType.Ball
	footprint.Material = Enum.Material.ForceField
	footprint.Size = Vector3.one * G.SYSTEM_RADIUS * 2
	footprint.Transparency = 0.6
	footprint.Anchored = true
	footprint.CanCollide = false
	footprint.CanQuery = false
	footprint.CanTouch = false

	info = Instance.new("BillboardGui")
	info.Name = "Info"
	info.Size = UDim2.fromOffset(300, 70)
	info.StudsOffsetWorldSpace = Vector3.new(0, 30, 0)
	info.AlwaysOnTop = true
	info.LightInfluence = 0
	info.Adornee = ghost
	info.Parent = ghost
	infoText = Instance.new("TextLabel")
	infoText.Size = UDim2.fromScale(1, 1)
	infoText.BackgroundTransparency = 1
	infoText.Font = Enum.Font.GothamBold
	infoText.TextScaled = true
	infoText.TextStrokeTransparency = 0.3
	infoText.Parent = info
end

return PlacementController
