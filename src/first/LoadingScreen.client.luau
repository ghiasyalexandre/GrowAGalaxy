--!strict
-- The game's loading screen (ReplicatedFirst, so it runs before anything
-- else has arrived). It replaces Roblox's default screen with the Grow a
-- Galaxy 2 key art, a progress bar, a status line and rotating tips, and
-- fades out once the game has loaded and the client has started (the client
-- sets the local player attribute GaG_ClientReady, init.client.luau).
--
-- The key art is assets/ui/GaG_LoadingScreen.png, uploaded to Roblox by
-- hand: put its image id in IMAGE below. Until then the screen shows a
-- title card in the same colours. (This script can't read Config: it runs
-- before ReplicatedStorage has loaded, so its settings live here.)
--
-- It always shows for at least MIN_SECONDS, offers "Play now" after
-- SKIP_AFTER seconds, and gives up waiting after MAX_SECONDS.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

-- "rbxassetid://<id>" of the uploaded key art, or "" for the title card.
local IMAGE = "rbxassetid://134268172125999"
local MIN_SECONDS = 2.5
local SKIP_AFTER = 10
local MAX_SECONDS = 45
local TIP_SECONDS = 3.5
local GOLD = Color3.fromRGB(255, 205, 90)
local PURPLE = Color3.fromRGB(176, 107, 255)
local TIPS = {
	"Zap the glowing spot on space rocks to get Stardust!",
	"Buy stars in the Star Shop to grow your galaxy.",
	"Planets hatch from eggs at the big space station.",
	"Put planets around your stars to earn lots of Stardust.",
	"Press P to see all your planets.",
	"Spin the Daily Wheel and open your Daily prize every day!",
	"Visit your friends' hangars with the Visit button.",
	"Grab the GIANT BALL in Zero G Dodgeball!",
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local started = os.clock()

local gui = Instance.new("ScreenGui")
gui.Name = "GaG_Loading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(14, 10, 40)
background.BorderSizePixel = 0
background.Parent = gui
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 20, 110)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(16, 12, 52)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 24, 120)),
})
gradient.Rotation = 35
gradient.Parent = background

-- The key art, filling the screen (cropped, never stretched), drifting
-- slowly closer.
local art: ImageLabel? = nil
if IMAGE ~= "" then
	local image = Instance.new("ImageLabel")
	image.Name = "KeyArt"
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.Image = IMAGE
	image.ScaleType = Enum.ScaleType.Crop
	image.Parent = background
	art = image
	TweenService
		:Create(
			image,
			TweenInfo.new(20, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{
				Size = UDim2.fromScale(1.08, 1.08),
			}
		)
		:Play()
else
	-- Title card: the logo words in the key art's colours.
	local function word(text: string, y: number, height: number, color: Color3)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, y)
		label.Size = UDim2.fromScale(0.8, height)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = color
		label.Parent = background
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(30, 20, 70)
		stroke.Thickness = 6
		stroke.Parent = label
		return label
	end
	word("GROW A", 0.28, 0.16, Color3.fromRGB(240, 244, 255))
	local galaxy = word("GALAXY 2", 0.45, 0.2, GOLD)
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(GOLD, PURPLE)
	shine.Rotation = 0
	shine.Parent = galaxy
	TweenService
		:Create(
			shine,
			TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{
				Offset = Vector2.new(0.4, 0),
			}
		)
		:Play()
end

-- Shade under the bar so it reads on top of the art.
local shade = Instance.new("Frame")
shade.AnchorPoint = Vector2.new(0, 1)
shade.Position = UDim2.fromScale(0, 1)
shade.Size = UDim2.fromScale(1, 0.26)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BorderSizePixel = 0
shade.Parent = background
local fade = Instance.new("UIGradient")
fade.Rotation = 90
fade.Transparency = NumberSequence.new(1, 0.25)
fade.Parent = shade

local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.new(0.5, 0, 1, -78)
status.Size = UDim2.new(0.8, 0, 0, 28)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamBlack
status.TextSize = 22
status.TextColor3 = Color3.new(1, 1, 1)
status.TextStrokeTransparency = 0.4
status.Text = "Loading the galaxy..."
status.Parent = background

local track = Instance.new("Frame")
track.AnchorPoint = Vector2.new(0.5, 1)
track.Position = UDim2.new(0.5, 0, 1, -50)
track.Size = UDim2.new(0.6, 0, 0, 16)
track.BackgroundColor3 = Color3.fromRGB(30, 24, 70)
track.BorderSizePixel = 0
track.Parent = background
local trackLimit = Instance.new("UISizeConstraint")
trackLimit.MaxSize = Vector2.new(640, 16)
trackLimit.Parent = track
local trackRound = Instance.new("UICorner")
trackRound.CornerRadius = UDim.new(1, 0)
trackRound.Parent = track
local trackEdge = Instance.new("UIStroke")
trackEdge.Color = GOLD
trackEdge.Thickness = 2
trackEdge.Parent = track
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = GOLD
fill.BorderSizePixel = 0
fill.Parent = track
local fillRound = Instance.new("UICorner")
fillRound.CornerRadius = UDim.new(1, 0)
fillRound.Parent = fill
local fillShine = Instance.new("UIGradient")
fillShine.Color = ColorSequence.new(GOLD, PURPLE)
fillShine.Parent = fill

local tip = Instance.new("TextLabel")
tip.AnchorPoint = Vector2.new(0.5, 1)
tip.Position = UDim2.new(0.5, 0, 1, -16)
tip.Size = UDim2.new(0.9, 0, 0, 24)
tip.BackgroundTransparency = 1
tip.Font = Enum.Font.GothamBold
tip.TextSize = 17
tip.TextColor3 = Color3.fromRGB(220, 226, 255)
tip.TextStrokeTransparency = 0.5
tip.Text = `Tip: {TIPS[math.random(#TIPS)]}`
tip.Parent = background

local skip = Instance.new("TextButton")
skip.AnchorPoint = Vector2.new(1, 0)
skip.Position = UDim2.new(1, -20, 0, 20)
skip.Size = UDim2.fromOffset(150, 44)
skip.BackgroundColor3 = GOLD
skip.Font = Enum.Font.GothamBlack
skip.TextSize = 18
skip.TextColor3 = Color3.fromRGB(30, 20, 60)
skip.Text = "Play now"
skip.Visible = false
skip.Parent = background
local skipRound = Instance.new("UICorner")
skipRound.CornerRadius = UDim.new(0, 10)
skipRound.Parent = skip

gui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- Show the art as soon as it's downloaded.
if art then
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ art :: ImageLabel })
		end)
	end)
end

local skipped = false
skip.Activated:Connect(function()
	skipped = true
end)

local function clientReady(): boolean
	return player:GetAttribute("GaG_ClientReady") == true
end

-- Progress: half for the place loading (with its download queue), half for
-- the client starting up; shown smoothly.
local shown = 0
local nextTip = os.clock() + TIP_SECONDS
while true do
	local elapsed = os.clock() - started
	local loaded = game:IsLoaded()
	local ready = loaded and clientReady()
	local target: number
	if ready then
		target = 1
	elseif loaded then
		target = 0.6 + 0.3 * math.min(elapsed / 15, 1)
		status.Text = "Building your galaxy..."
	else
		local queue = ContentProvider.RequestQueueSize
		target = 0.5 * (1 - math.min(queue, 200) / 200) * math.min(elapsed / 3, 1)
		status.Text = "Loading the galaxy..."
	end
	shown += (math.max(target, shown) - shown) * 0.15
	fill.Size = UDim2.fromScale(shown, 1)
	if os.clock() >= nextTip then
		nextTip = os.clock() + TIP_SECONDS
		tip.Text = `Tip: {TIPS[math.random(#TIPS)]}`
	end
	skip.Visible = elapsed >= SKIP_AFTER and not ready
	if (ready and elapsed >= MIN_SECONDS) or skipped or elapsed >= MAX_SECONDS then
		break
	end
	task.wait()
end

-- Done: fill the bar, then fade everything out.
status.Text = "Let's go!"
fill.Size = UDim2.fromScale(1, 1)
task.wait(0.35)
local out = TweenInfo.new(0.6)
for _, item in gui:GetDescendants() do
	if item:IsA("Frame") then
		TweenService:Create(item, out, { BackgroundTransparency = 1 }):Play()
	elseif item:IsA("TextLabel") or item:IsA("TextButton") then
		TweenService:Create(
			item,
			out,
			{ TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 }
		):Play()
	elseif item:IsA("ImageLabel") then
		TweenService:Create(item, out, { ImageTransparency = 1 }):Play()
	elseif item:IsA("UIStroke") then
		TweenService:Create(item, out, { Transparency = 1 }):Play()
	end
end
task.wait(0.65)
gui:Destroy()
