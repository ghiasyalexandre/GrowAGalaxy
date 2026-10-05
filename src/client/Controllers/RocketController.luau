--!strict
-- Ship rockets on this client (Config.Rockets). The Rocket action (Q /
-- gamepad B / touch button) fires at the reticle; the server checks the
-- cooldown and decides the blast (RocketSystem).
--
-- Every client draws every rocket from RocketEvent: a dark missile with a
-- glowing nose in its laser colour, trailing fire and smoke ("launch"); then
-- the blast ("boom"): a blinding core, a fireball and shockwave ring in the
-- laser colour, sparks flung out, a flash of light and a camera shake for
-- anyone close.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local K = Config.Rockets
local WHITE = Color3.new(1, 1, 1)
local SHAKE_RADIUS = 600

type Flight = { model: Model, origin: Vector3, direction: Vector3, started: number }

local RocketController = {}

local flights: { [number]: Flight } = {}
local folder: Folder? = nil

local function fx(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "GaG_Rockets"
	made.Parent = Workspace.CurrentCamera
	folder = made
	return made
end

local function part(
	shape: Enum.PartType,
	color: Color3,
	material: Enum.Material,
	size: Vector3
): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Color = color
	p.Material = material
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function missile(origin: Vector3, direction: Vector3, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Rocket"
	local body = part(
		Enum.PartType.Cylinder,
		Color3.fromRGB(46, 50, 62),
		Enum.Material.Metal,
		Vector3.new(5, 1.4, 1.4)
	)
	body.Name = "Body"
	body.Parent = model
	local nose = part(Enum.PartType.Ball, color, Enum.Material.Neon, Vector3.one * 1.5)
	nose.Name = "Nose"
	nose.Parent = model
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 20
	light.Brightness = 3
	light.Parent = nose
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(-2.5, 0.5, 0)
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(-2.5, -0.5, 0)
	a1.Parent = body
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.6
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(WHITE, color)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(1.5, 0.2)
	trail.Parent = body
	if not ClientState.reducedEffects then
		local flame = Instance.new("Fire")
		flame.Color = color
		flame.SecondaryColor = WHITE
		flame.Size = 2
		flame.Heat = 0
		flame.Parent = body
	end
	model.PrimaryPart = body
	model.Parent = fx()
	local at = CFrame.lookAt(origin, origin + direction)
	body.CFrame = at * CFrame.Angles(0, math.pi / 2, 0)
	nose.CFrame = at * CFrame.new(0, 0, -2.6)
	return model
end

local function boom(at: Vector3, color: Color3)
	local radius = K.BLAST_RADIUS
	local reduced = ClientState.reducedEffects
	local core = part(Enum.PartType.Ball, WHITE, Enum.Material.Neon, Vector3.one * 4)
	core.CFrame = CFrame.new(at)
	core.Parent = fx()
	local ball = part(Enum.PartType.Ball, color, Enum.Material.Neon, Vector3.one * 6)
	ball.CFrame = CFrame.new(at)
	ball.Transparency = 0.1
	ball.Parent = fx()
	local shell = part(Enum.PartType.Ball, color, Enum.Material.ForceField, Vector3.one * 8)
	shell.CFrame = CFrame.new(at)
	shell.Parent = fx()
	local ring = part(Enum.PartType.Cylinder, color, Enum.Material.Neon, Vector3.new(0.6, 6, 6))
	ring.CFrame = CFrame.new(at)
		* CFrame.Angles(math.random() * math.pi, 0, math.random() * math.pi)
	ring.Transparency = 0.2
	ring.Parent = fx()
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = radius * 2.5
	light.Brightness = 12
	light.Parent = core
	TweenService:Create(core, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		Size = Vector3.one * radius * 0.6,
		Transparency = 1,
	}):Play()
	TweenService:Create(ball, TweenInfo.new(0.7, Enum.EasingStyle.Quint), {
		Size = Vector3.one * radius * 1.6,
		Transparency = 1,
	}):Play()
	TweenService:Create(shell, TweenInfo.new(0.9, Enum.EasingStyle.Quint), {
		Size = Vector3.one * radius * 2.2,
		Transparency = 1,
	}):Play()
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quint), {
		Size = Vector3.new(0.2, radius * 3, radius * 3),
		Transparency = 1,
	}):Play()
	TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	if not reduced then
		local sparks = Instance.new("ParticleEmitter")
		sparks.Rate = 0
		sparks.Speed = NumberRange.new(radius * 1.5, radius * 3)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Lifetime = NumberRange.new(0.5, 1.2)
		sparks.Size = NumberSequence.new(1.6, 0)
		sparks.Color = ColorSequence.new(WHITE, color)
		sparks.LightEmission = 1
		sparks.LightInfluence = 0
		sparks.Drag = 2
		sparks.Parent = core
		sparks:Emit(80)
		local smoke = Instance.new("ParticleEmitter")
		smoke.Rate = 0
		smoke.Speed = NumberRange.new(radius * 0.3, radius * 0.8)
		smoke.SpreadAngle = Vector2.new(180, 180)
		smoke.Lifetime = NumberRange.new(1.2, 2)
		smoke.Size = NumberSequence.new(radius * 0.25, radius * 0.6)
		smoke.Transparency = NumberSequence.new(0.5, 1)
		smoke.Color = ColorSequence.new(color:Lerp(Color3.new(), 0.6))
		smoke.Drag = 3
		smoke.Parent = core
		smoke:Emit(18)
	end
	task.delay(2.2, function()
		for _, item in { core, ball, shell, ring } do
			item:Destroy()
		end
	end)
	local distance = (Workspace.CurrentCamera.CFrame.Position - at).Magnitude
	if distance < SHAKE_RADIUS then
		ClientState.shake:Fire(3 * (1 - distance / SHAKE_RADIUS))
	end
end

local function onEvent(kind: unknown, id: unknown, at: unknown, a: unknown, b: unknown)
	if type(id) ~= "number" or typeof(at) ~= "Vector3" then
		return
	end
	if kind == "launch" and typeof(a) == "Vector3" then
		local color = if type(b) == "string" then Color3.fromHex(b) else WHITE
		flights[id] = {
			model = missile(at, a.Unit, color),
			origin = at,
			direction = a.Unit,
			started = os.clock(),
		}
	elseif kind == "boom" then
		local flight = flights[id]
		if flight then
			flight.model:Destroy()
			flights[id] = nil
		end
		boom(at, if type(a) == "string" then Color3.fromHex(a) else WHITE)
	end
end

local function step()
	local now = os.clock()
	for id, flight in flights do
		local t = now - flight.started
		if t > K.LIFETIME + 1 then
			flight.model:Destroy()
			flights[id] = nil
			continue
		end
		local at = flight.origin + flight.direction * K.SPEED * t
		local frame = CFrame.lookAt(at, at + flight.direction)
		local body = flight.model:FindFirstChild("Body") :: BasePart?
		local nose = flight.model:FindFirstChild("Nose") :: BasePart?
		if body and nose then
			body.CFrame = frame * CFrame.Angles(0, math.pi / 2, 0)
			nose.CFrame = frame * CFrame.new(0, 0, -2.6)
		end
	end
end

local function fire()
	if ClientState.mode ~= "ship" then
		return
	end
	local readyAt = Players.LocalPlayer:GetAttribute("RocketReadyAt")
	if type(readyAt) == "number" and Workspace:GetServerTimeNow() < readyAt then
		local left = math.ceil(readyAt - Workspace:GetServerTimeNow())
		ClientState.notify:Fire(`Rocket reloading: {left}s`)
		return
	end
	-- At the reticle (the middle of the screen).
	local camera = Workspace.CurrentCamera
	local size = camera.ViewportSize
	Net.RocketRequest:FireServer(camera:ViewportPointToRay(size.X / 2, size.Y / 2).Direction)
end

function RocketController.init() end

function RocketController.start()
	Net.RocketEvent.OnClientEvent:Connect(onEvent)
	Input.pressed:Connect(function(action)
		if action == "Rocket" then
			fire()
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return RocketController
