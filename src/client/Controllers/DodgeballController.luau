--!strict
-- Zero G Dodgeball on this client (Config.Dodgeball). While you're in the
-- arena (player attribute Dodgeball):
--
--   Throw    click / R2 / touch button: throws your sun-ball where you aim
--            (the mouse, or straight ahead on a gamepad or touch screen).
--            The server decides every hit (DodgeballSystem).
--   Launch   Shift / B / touch button next to a block or wall: pushes you
--            off its face, towards where you look (Logic/DodgeballMath).
--   HUD      a banner with your hits and outs this session and whether your
--            sun is ready; a red flash and the thrower's name when you're out.
--
-- Every client draws every ball: a blazing little sun with a fiery corona
-- and a trail, flying straight from DodgeballEvent "throw" until "end",
-- where it bursts.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local SuitController = require(script.Parent.SuitController)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DodgeballMath = require(Shared:WaitForChild("Logic"):WaitForChild("DodgeballMath"))
local Net = require(Shared:WaitForChild("Net"))

local D = Config.Dodgeball
local player = Players.LocalPlayer
local SUN = Color3.fromRGB(255, 176, 32)
local SUN_HOT = Color3.fromRGB(255, 244, 200)
local OUT_RED = Color3.fromRGB(255, 70, 70)
local THROW_ACTION = "GaG_DodgeThrow"
local LAUNCH_ACTION = "GaG_DodgeLaunch"
local PRIORITY = Enum.ContextActionPriority.High.Value + 10
local BLOCK_TAG = "DodgeBlock"

type Ball = { part: Part, origin: Vector3, direction: Vector3, started: number }

local DodgeballController = {}

local balls: { [number]: Ball } = {}
local bound = false
local lastLaunch = 0
local folder: Folder? = nil
local gui: ScreenGui
local banner: Frame
local score: TextLabel
local status: TextLabel
local outLabel: TextLabel
local flash: Frame

local function fx(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "GaG_Dodgeballs"
	made.Parent = Workspace.CurrentCamera
	folder = made
	return made
end

-- A small sun: a white-hot core in a blazing shell, with flames and a trail.
local function makeSun(at: Vector3): Part
	local sun = Instance.new("Part")
	sun.Shape = Enum.PartType.Ball
	sun.Size = Vector3.one * D.BALL_RADIUS * 2
	sun.Material = Enum.Material.Neon
	sun.Color = SUN
	sun.Anchored = true
	sun.CanCollide = false
	sun.CanQuery = false
	sun.CanTouch = false
	sun.CastShadow = false
	sun.CFrame = CFrame.new(at)
	local core = Instance.new("Part")
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.one * D.BALL_RADIUS * 1.2
	core.Material = Enum.Material.Neon
	core.Color = SUN_HOT
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Name = "Core"
	core.Parent = sun
	local light = Instance.new("PointLight")
	light.Color = SUN
	light.Range = 18
	light.Brightness = 3 * (1 - Config.World.EMISSIVE_DIM)
	light.Parent = sun
	if not ClientState.reducedEffects then
		local flames = Instance.new("Fire")
		flames.Color = Color3.fromRGB(255, 120, 30)
		flames.SecondaryColor = Color3.fromRGB(255, 220, 90)
		flames.Size = D.BALL_RADIUS * 2.2
		flames.Heat = 0
		flames.Parent = sun
	end
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, D.BALL_RADIUS * 0.7, 0)
	top.Parent = sun
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -D.BALL_RADIUS * 0.7, 0)
	bottom.Parent = sun
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.35
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(SUN_HOT, Color3.fromRGB(255, 90, 30))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = sun
	sun.Parent = fx()
	return sun
end

local function burst(at: Vector3, big: boolean)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = SUN_HOT
	ball.Size = Vector3.one * D.BALL_RADIUS * 2
	ball.CFrame = CFrame.new(at)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Parent = fx()
	local size = D.BALL_RADIUS * (if big then 10 else 5)
	TweenService:Create(ball, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
		Size = Vector3.one * size,
		Transparency = 1,
		Color = SUN,
	}):Play()
	task.delay(0.45, function()
		ball:Destroy()
	end)
end

local function onEvent(kind: unknown, ...: unknown)
	local args = { ... }
	if kind == "throw" then
		local id, origin, direction = args[1], args[2], args[3]
		if
			type(id) ~= "number"
			or typeof(origin) ~= "Vector3"
			or typeof(direction) ~= "Vector3"
		then
			return
		end
		balls[id] = {
			part = makeSun(origin),
			origin = origin,
			direction = direction.Unit,
			started = os.clock(),
		}
	elseif kind == "end" then
		local id, at, victim = args[1], args[2], args[3]
		local ball = if type(id) == "number" then balls[id] else nil
		if ball then
			ball.part:Destroy()
			balls[id :: number] = nil
		end
		if typeof(at) == "Vector3" then
			burst(at, type(victim) == "number" and victim ~= 0)
		end
	elseif kind == "hit" then
		local direction, thrower = args[1], args[2]
		if typeof(direction) == "Vector3" and direction.Magnitude > 0 then
			SuitController.launch(direction.Unit * D.KNOCKBACK, 0.6)
		end
		ClientState.shake:Fire(1.5)
		flash.BackgroundTransparency = 0.45
		TweenService:Create(flash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
		outLabel.Text = `OUT! Hit by {if type(thrower) == "string" then thrower else "someone"}`
		outLabel.Visible = true
		task.delay(D.OUT_TIME, function()
			outLabel.Visible = false
		end)
	end
end

local function stepBalls()
	local now = os.clock()
	for id, ball in balls do
		local t = now - ball.started
		if t > D.BALL_LIFETIME + 0.5 then
			ball.part:Destroy()
			balls[id] = nil
			continue
		end
		local at = ball.origin + ball.direction * D.BALL_SPEED * t
		ball.part.CFrame = CFrame.new(at)
		local core = ball.part:FindFirstChild("Core")
		if core and core:IsA("BasePart") then
			core.CFrame = CFrame.new(at)
		end
	end
end

local function aim(): Vector3
	local camera = Workspace.CurrentCamera
	if Input.device() == "keyboard" then
		local mouse = UserInputService:GetMouseLocation()
		return camera:ViewportPointToRay(mouse.X, mouse.Y).Direction
	end
	return camera.CFrame.LookVector
end

local function throw()
	if player:GetAttribute("DodgeReady") ~= true or player:GetAttribute("DodgeOut") == true then
		return
	end
	Net.DodgeballThrow:FireServer(aim())
end

-- The nearest block or wall face within LAUNCH_REACH, if any.
local function nearestFace(root: BasePart): RaycastResult?
	local include: { Instance } = CollectionService:GetTagged(BLOCK_TAG)
	local arena = Workspace:FindFirstChild("DodgeballArena")
	if arena then
		for _, part in arena:GetChildren() do
			if part.Name == "Wall" then
				table.insert(include, part)
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local reach = D.LAUNCH_REACH + root.Size.Y
	local best: RaycastResult? = nil
	local directions = {
		Vector3.xAxis,
		-Vector3.xAxis,
		Vector3.yAxis,
		-Vector3.yAxis,
		Vector3.zAxis,
		-Vector3.zAxis,
		Workspace.CurrentCamera.CFrame.LookVector,
	}
	for _, direction in directions do
		local result = Workspace:Raycast(root.Position, direction * reach, params)
		if result and (best == nil or result.Distance < (best :: RaycastResult).Distance) then
			best = result
		end
	end
	return best
end

local function launch()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local now = os.clock()
	if
		root == nil
		or not root:IsA("BasePart")
		or not SuitController.floating()
		or now - lastLaunch < D.LAUNCH_COOLDOWN
	then
		return
	end
	local face = nearestFace(root)
	if face == nil then
		status.Text = "Get next to a block to launch"
		return
	end
	lastLaunch = now
	local look = Workspace.CurrentCamera.CFrame.LookVector
	local d = DodgeballMath.launchDirection(
		{ x = face.Normal.X, y = face.Normal.Y, z = face.Normal.Z },
		{ x = look.X, y = look.Y, z = look.Z }
	)
	SuitController.launch(Vector3.new(d.x, d.y, d.z) * D.LAUNCH_SPEED, D.LAUNCH_TIME)
	-- A ring of light where you pushed off.
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(95, 227, 255)
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.lookAt(face.Position, face.Position + face.Normal)
		* CFrame.Angles(0, math.pi / 2, 0)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Parent = fx()
	TweenService
		:Create(ring, TweenInfo.new(0.35), { Size = Vector3.new(0.2, 12, 12), Transparency = 1 })
		:Play()
	task.delay(0.4, function()
		ring:Destroy()
	end)
end

local function setBound(on: boolean)
	if on == bound then
		return
	end
	bound = on
	if on then
		ContextActionService:BindActionAtPriority(THROW_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then
				throw()
			end
			return Enum.ContextActionResult.Sink
		end, true, PRIORITY, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
		ContextActionService:SetTitle(THROW_ACTION, "Throw")
		ContextActionService:BindActionAtPriority(LAUNCH_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then
				launch()
			end
			return Enum.ContextActionResult.Sink
		end, true, PRIORITY, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB)
		ContextActionService:SetTitle(LAUNCH_ACTION, "Launch")
	else
		ContextActionService:UnbindAction(THROW_ACTION)
		ContextActionService:UnbindAction(LAUNCH_ACTION)
	end
end

local function refresh()
	local playing = player:GetAttribute("Dodgeball") == true
	setBound(playing)
	gui.Enabled = playing
	if not playing then
		return
	end
	score.Text =
		`ZERO G DODGEBALL  ·  Hits {player:GetAttribute("DodgeHits") or 0}  ·  Outs {player:GetAttribute(
			"DodgeOuts"
		) or 0}`
	status.Text = if player:GetAttribute("DodgeOut") == true
		then "You're out: back in a moment"
		elseif
			player:GetAttribute("DodgeReady") == true
		then "Sun ready: click to throw  ·  Shift: launch off a block"
		else "Recharging your sun..."
	status.TextColor3 = if player:GetAttribute("DodgeReady") == true
		then SUN
		else Theme.COLORS.subtle
end

local function build()
	gui = Theme.screen("Dodgeball", player:WaitForChild("PlayerGui"))
	gui.Enabled = false
	banner = Theme.panel(gui, "Banner")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 64)
	banner.Size = UDim2.fromOffset(460, 58)
	score = Theme.label(banner, {
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -28, 0, 24),
		Font = Enum.Font.GothamBlack,
		TextSize = 17,
		TextColor3 = SUN,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	status = Theme.label(banner, {
		Position = UDim2.fromOffset(14, 32),
		Size = UDim2.new(1, -28, 0, 18),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	outLabel = Theme.label(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.35),
		Size = UDim2.fromOffset(520, 44),
		Font = Enum.Font.GothamBlack,
		TextSize = 30,
		TextColor3 = OUT_RED,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})
	flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = OUT_RED
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 0
	flash.Parent = gui
end

function DodgeballController.init()
	build()
end

function DodgeballController.start()
	Net.DodgeballEvent.OnClientEvent:Connect(onEvent)
	for _, name in { "Dodgeball", "DodgeReady", "DodgeOut", "DodgeHits", "DodgeOuts" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()
	RunService.RenderStepped:Connect(stepBalls)
end

return DodgeballController
