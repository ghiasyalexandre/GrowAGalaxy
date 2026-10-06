--!strict
-- Placing or moving a star with a ghost preview (Logic/PlacementRules, the
-- same rules the server re-runs on confirm).
--
-- The ghost sits on a horizontal plane at its elevation, under your aim: the
-- mouse on a computer, the middle of the screen on a gamepad or phone (turn
-- the camera to steer it). It's always kept inside your galaxy's build box,
-- which is drawn as a glowing frame, and it starts at the valid spot nearest
-- your aim. Each other star shows its reserved footprint as a faint disc; the
-- ghost's own disc turns green (valid) or red, and the panel says why not.
--
-- Controls (on-screen buttons on every device, plus):
--   Confirm   Enter / ButtonA          Cancel   Backspace / ButtonB
--   Higher    E / DPadUp / wheel up    Lower    Q / DPadDown / wheel down
--   Snap to grid on/off: T / ButtonY

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local Theme = require(script.Parent.Parent.UI.Theme)

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
local FRAME = Color3.fromRGB(95, 227, 255)
local SNAP_GRID = G.GRID_SNAP * 4

local REASONS: { [string]: string } = {
	Invalid = "Not a valid spot",
	OutOfBounds = "Too near your galaxy's edge",
	TooHigh = "Too high or too low: press Lower / Higher",
	TooClose = "Too close to another star's planets",
	AtCapacity = "Your galaxy is full: expand it in the Shipyard",
}

export type Options = { mode: "place", typeId: string } | { mode: "move", starId: string }

local PlacementController = {}

local active: Options? = nil
local spot: Types.Vec3 = { x = 0, y = 0, z = 0 } -- region space
local valid = false
local snapping = false
local busy = false
local ghost: Part
local footprint: Part
local frameParts: { Part } = {}
local discs: { Part } = {}
local gui: ScreenGui
local statusLabel: TextLabel
local detailLabel: TextLabel
local confirmButton: TextButton
local starSource: () -> { [string]: Model } = function()
	return {}
end
local renderConnection: RBXScriptConnection? = nil

local ACTIONS = { "Confirm", "Cancel", "Higher", "Lower", "Snap", "Wheel" }

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

local function localPart(shape: Enum.PartType, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- A glowing frame around the build box, and a faint disc for every other
-- star's footprint.
local function drawGuides(region: CFrame, expansion: number, except: string?)
	for _, part in frameParts do
		part:Destroy()
	end
	for _, part in discs do
		part:Destroy()
	end
	table.clear(frameParts)
	table.clear(discs)
	local box = PlacementRules.buildBox(expansion)
	local lo = Vector3.new(box.min.x, box.min.y, box.min.z)
	local hi = Vector3.new(box.max.x, box.max.y, box.max.z)
	local size = hi - lo
	local function edge(a: Vector3, b: Vector3)
		local part = localPart(Enum.PartType.Block, FRAME, Enum.Material.Neon)
		local mid = (a + b) / 2
		part.Size = Vector3.new(1.5, 1.5, (b - a).Magnitude)
		part.CFrame = region * CFrame.lookAt(mid, b)
		part.Transparency = 0.35
		part.Parent = Workspace.CurrentCamera
		table.insert(frameParts, part)
	end
	for _, y in { lo.Y, hi.Y } do
		edge(Vector3.new(lo.X, y, lo.Z), Vector3.new(hi.X, y, lo.Z))
		edge(Vector3.new(lo.X, y, hi.Z), Vector3.new(hi.X, y, hi.Z))
		edge(Vector3.new(lo.X, y, lo.Z), Vector3.new(lo.X, y, hi.Z))
		edge(Vector3.new(hi.X, y, lo.Z), Vector3.new(hi.X, y, hi.Z))
	end
	if size.Y > 1 then
		for _, x in { lo.X, hi.X } do
			for _, z in { lo.Z, hi.Z } do
				edge(Vector3.new(x, lo.Y, z), Vector3.new(x, hi.Y, z))
			end
		end
	end
	for _, other in others(region, except) do
		local disc = localPart(Enum.PartType.Cylinder, FRAME, Enum.Material.ForceField)
		disc.Size = Vector3.new(G.SYSTEM_HALF_HEIGHT * 2, G.SYSTEM_RADIUS * 2, G.SYSTEM_RADIUS * 2)
		disc.CFrame = region
			* CFrame.new(other.x, other.y, other.z)
			* CFrame.Angles(0, 0, math.pi / 2)
		disc.Transparency = 0.7
		disc.Parent = Workspace.CurrentCamera
		table.insert(discs, disc)
	end
end

local function stop()
	active = nil
	valid = false
	for _, name in ACTIONS do
		ContextActionService:UnbindAction("GaG_Place" .. name)
	end
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	ghost.Parent = nil
	footprint.Parent = nil
	for _, part in frameParts do
		part:Destroy()
	end
	for _, part in discs do
		part:Destroy()
	end
	table.clear(frameParts)
	table.clear(discs)
	gui.Enabled = false
end

local function confirm()
	local options = active
	if options == nil or busy then
		return
	end
	if not valid then
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

-- The point under the aim on the horizontal plane at the ghost's height, in
-- region space, or nil when the aim runs parallel to the plane.
local function aimPoint(region: CFrame): Types.Vec3?
	local camera = Workspace.CurrentCamera
	local ray: Ray
	if Input.device() == "keyboard" then
		local mouse = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	else
		local size = camera.ViewportSize
		ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	end
	local origin = region:PointToObjectSpace(ray.Origin)
	local direction = region:VectorToObjectSpace(ray.Direction)
	if math.abs(direction.Y) < 1e-3 then
		return nil
	end
	local t = (spot.y - origin.Y) / direction.Y
	if t < 0 then
		-- The plane is behind the aim: use the point straight ahead instead.
		t = S.GHOST_DISTANCE
	end
	t = math.min(t, S.GHOST_MAX_DISTANCE * 3)
	local hit = origin + direction * t
	return { x = hit.X, y = spot.y, z = hit.Z }
end

local function update()
	local options = active
	local region = regionCFrame()
	local profile = ClientState.profile
	if options == nil or region == nil or profile == nil then
		return
	end
	local aimed = aimPoint(region)
	if aimed then
		local target = PlacementRules.clamp(aimed, profile.expansion)
		if snapping then
			target = PlacementRules.clamp(PlacementRules.snap(target, SNAP_GRID), profile.expansion)
		end
		spot = { x = target.x, y = spot.y, z = target.z }
	end

	local except = if options.mode == "move" then options.starId else nil
	local ok, rejection, short =
		PlacementRules.checkStar(spot, profile.expansion, others(region, except))
	local title: string
	local reason: string? = nil
	if options.mode == "place" then
		local owned = count(starSource())
		local def = S.BY_ID[options.typeId]
		local cost = StarMath.placeCost(options.typeId, owned) or 0
		title = `{if def then def.displayName else "Star"}  ·  {cost} {CURRENCY}`
		if not PlacementRules.hasCapacity(owned, profile.expansion) then
			ok, rejection = false, "AtCapacity"
		elseif profile.stardust < cost then
			ok = false
			reason = `You need {cost - profile.stardust} more {CURRENCY}`
		end
	else
		title = "Moving a star (its planets come along)"
	end
	if not ok and reason == nil then
		local text = REASONS[rejection or "Invalid"] or REASONS.Invalid
		if rejection == "TooClose" and short then
			text ..= `: {short} studs short`
		end
		reason = text
	end
	valid = ok
	local color = if ok then VALID else INVALID
	local world = region:PointToWorldSpace(Vector3.new(spot.x, spot.y, spot.z))
	ghost.CFrame = CFrame.new(world)
	ghost.Color = color
	footprint.CFrame = region
		* CFrame.new(spot.x, spot.y, spot.z)
		* CFrame.Angles(0, 0, math.pi / 2)
	footprint.Color = color
	statusLabel.Text = title
	detailLabel.Text = (if ok then "Valid spot" else reason or "")
		.. `  ·  height {math.floor(spot.y)}{if snapping then "  ·  snap on" else ""}`
	detailLabel.TextColor3 = color
	confirmButton.AutoButtonColor = ok
	confirmButton.BackgroundTransparency = if ok then 0 else 0.5
end

local function raise(step: number)
	local profile = ClientState.profile
	if profile then
		local box = PlacementRules.buildBox(profile.expansion)
		spot = { x = spot.x, y = math.clamp(spot.y + step, box.min.y, box.max.y), z = spot.z }
	end
end

local function handle(
	name: string,
	state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if name == "Wheel" then
		raise(if input.Position.Z > 0 then S.GHOST_STEP else -S.GHOST_STEP)
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
		raise(S.GHOST_STEP)
	elseif name == "Lower" then
		raise(-S.GHOST_STEP)
	elseif name == "Snap" then
		snapping = not snapping
	end
	return Enum.ContextActionResult.Sink
end

local BINDINGS: { [string]: { any } } = {
	Confirm = { Enum.KeyCode.Return, Enum.KeyCode.ButtonA },
	Cancel = { Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB },
	Higher = { Enum.KeyCode.E, Enum.KeyCode.DPadUp },
	Lower = { Enum.KeyCode.Q, Enum.KeyCode.DPadDown },
	Snap = { Enum.KeyCode.T, Enum.KeyCode.ButtonY },
	Wheel = { Enum.UserInputType.MouseWheel },
}

-- Starts placing (shop) or moving (manage panel) a star.
function PlacementController.begin(options: Options)
	if active then
		stop()
	end
	local profile = ClientState.profile
	local region = regionCFrame()
	if region == nil or profile == nil then
		ClientState.notify:Fire("Your galaxy isn't ready yet.")
		return
	end
	local except: string? = nil
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
	else
		except = options.starId
	end

	-- Start at the valid spot nearest to where the camera looks (a moved
	-- star starts where it is).
	local camera = Workspace.CurrentCamera
	local look = camera.CFrame.Position + camera.CFrame.LookVector * S.GHOST_DISTANCE
	local p = region:PointToObjectSpace(look)
	local wanted: Types.Vec3 = { x = p.X, y = p.Y, z = p.Z }
	if options.mode == "move" then
		local model = starSource()[options.starId]
		if model then
			local at = region:PointToObjectSpace(model:GetPivot().Position)
			wanted = { x = at.X, y = at.Y, z = at.Z }
		end
	end
	local start = PlacementRules.nearestValid(wanted, profile.expansion, others(region, except))
	if start == nil then
		ClientState.notify:Fire("There's no free room left in your galaxy. Move a star or expand.")
		return
	end
	spot = start

	active = options
	local ghostType = S.DEFAULT_TYPE
	if options.mode == "place" then
		ghostType = options.typeId
	else
		local model = starSource()[options.starId]
		local typeId = model and model:GetAttribute("TypeId")
		ghostType = if type(typeId) == "string" then typeId else ghostType
	end
	ghost.Size = Vector3.one * StarMath.radius(ghostType, 1) * 2
	ghost.Parent = Workspace.CurrentCamera
	footprint.Parent = Workspace.CurrentCamera
	drawGuides(region, profile.expansion, except)
	for name, keys in BINDINGS do
		ContextActionService:BindActionAtPriority("GaG_Place" .. name, function(_, state, input)
			return handle(name, state, input)
		end, false, PRIORITY, table.unpack(keys))
	end
	gui.Enabled = true
	renderConnection = RunService.RenderStepped:Connect(update)
	update()
end

function PlacementController.isActive(): boolean
	return active ~= nil
end

-- StarController supplies the player's own star models.
function PlacementController.setStarSource(source: () -> { [string]: Model })
	starSource = source
end

local function buildPanel()
	gui = Theme.screen("Placement", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	gui.DisplayOrder = 7
	local panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -110)
	panel.Size = UDim2.new(0.9, 0, 0, 112)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 112)
	limit.Parent = panel
	statusLabel = Theme.label(panel, {
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -28, 0, 22),
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	detailLabel = Theme.label(panel, {
		Position = UDim2.fromOffset(14, 28),
		Size = UDim2.new(1, -28, 0, 20),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(10, 56)
	row.Size = UDim2.new(1, -20, 0, 46)
	row.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local function button(
		order: number,
		text: string,
		style: Theme.ButtonStyle,
		onClick: () -> ()
	): TextButton
		local b = Theme.button(row, text, style, onClick)
		b.LayoutOrder = order
		b.Size = UDim2.new(0.2, -7, 1, 0)
		return b
	end
	button(1, "Lower", "primary", function()
		raise(-S.GHOST_STEP)
	end)
	button(2, "Higher", "primary", function()
		raise(S.GHOST_STEP)
	end)
	button(3, "Snap", "special", function()
		snapping = not snapping
	end)
	button(4, "Cancel", "primary", function()
		stop()
		ClientState.notify:Fire("Placement cancelled.")
	end)
	confirmButton = button(5, "Confirm", "buy", function()
		task.spawn(confirm)
	end)
end

function PlacementController.init()
	ghost = localPart(Enum.PartType.Ball, VALID, Enum.Material.Neon)
	ghost.Name = "GaG_StarGhost"
	ghost.Transparency = 0.35

	footprint = localPart(Enum.PartType.Cylinder, VALID, Enum.Material.ForceField)
	footprint.Name = "GaG_StarFootprint"
	footprint.Size = Vector3.new(G.SYSTEM_HALF_HEIGHT * 2, G.SYSTEM_RADIUS * 2, G.SYSTEM_RADIUS * 2)
	footprint.Transparency = 0.5

	buildPanel()
end

return PlacementController
