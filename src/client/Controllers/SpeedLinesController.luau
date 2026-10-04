--!strict
-- Speed lines while your ship boosts: thin streaks rushing outwards from the
-- centre of the screen, fading in with the boost and out when it ends.
-- Reduced effects draws fewer. Purely local and visual.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)

local COUNT = 26
local REDUCED_COUNT = 8
local SPEED = 1.6 -- screen half-diagonals per second
local START = 0.25 -- streaks appear this far out from the centre
local FADE_RATE = 6

type Streak = { frame: Frame, angle: number, distance: number, length: number }

local SpeedLinesController = {}

local gui: ScreenGui
local streaks: { Streak } = {}
local blend = 0

local function reset(streak: Streak, anywhere: boolean)
	streak.angle = math.random() * math.pi * 2
	streak.distance = if anywhere then START + math.random() * (1 - START) else START
	streak.length = 60 + math.random() * 140
end

local function update(dt: number)
	local target = if ClientState.flight.boosting and ClientState.mode == "ship" then 1 else 0
	blend += (target - blend) * (1 - math.exp(-FADE_RATE * dt))
	if blend < 0.01 then
		gui.Enabled = false
		return
	end
	gui.Enabled = true
	local size = gui.AbsoluteSize
	local center = size / 2
	local reach = center.Magnitude
	local shown = if ClientState.reducedEffects then REDUCED_COUNT else COUNT
	for index, streak in streaks do
		local frame = streak.frame
		if index > shown then
			frame.Visible = false
			continue
		end
		streak.distance += SPEED * dt
		if streak.distance > 1.1 then
			reset(streak, false)
		end
		local direction = Vector2.new(math.cos(streak.angle), math.sin(streak.angle))
		local point = center + direction * streak.distance * reach
		frame.Visible = true
		frame.Position = UDim2.fromOffset(point.X, point.Y)
		frame.Size = UDim2.fromOffset(streak.length * streak.distance, 2)
		frame.Rotation = math.deg(streak.angle)
		-- Faint near the centre, brightest towards the edges.
		frame.BackgroundTransparency = 1 - blend * 0.55 * math.clamp(streak.distance, 0, 1)
	end
end

function SpeedLinesController.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "SpeedLines"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -1
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _ = 1, COUNT do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.fromRGB(220, 240, 255)
		frame.BackgroundTransparency = 1
		frame.Parent = gui
		local streak: Streak = { frame = frame, angle = 0, distance = 0, length = 0 }
		reset(streak, true)
		table.insert(streaks, streak)
	end
end

function SpeedLinesController.start()
	RunService.RenderStepped:Connect(update)
end

return SpeedLinesController
