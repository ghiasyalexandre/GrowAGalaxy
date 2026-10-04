--!strict
-- Makes earning Stardust feel good. On every Reward from the server:
--   * a sparkle burst where it came from (the asteroid, the Collect console),
--   * glowing Stardust orbs burst out on screen and stream into the wallet,
--     which bounces as they land (HudController),
--   * a bouncing "+amount" pop-up with what it was for,
--   * for achievements, a gold banner that slides in from the top.
-- It also keeps a pulsing "ready to collect" label over your station's
-- Collect console. Presentation only: the server already paid out.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local HudController = require(script.Parent.HudController)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))

local CURRENCY = Config.Economy.CURRENCY_NAME
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local GOLD = Color3.fromRGB(255, 210, 90)
local ORB_LIGHT = Color3.fromRGB(255, 245, 200)
local ORB_SIZE = 18
local MAX_ORBS = 18
local BURST = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLY = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local RewardController = {}

local gui: ScreenGui
local banner: Frame
local bannerTitle: TextLabel
local bannerBody: TextLabel
local collectLabel: BillboardGui? = nil
local collectText: TextLabel? = nil

local function screenPoint(position: Vector3?): Vector2
	local camera = Workspace.CurrentCamera
	local size = camera.ViewportSize
	if position then
		local point, onScreen = camera:WorldToViewportPoint(position)
		if onScreen then
			return Vector2.new(point.X, point.Y)
		end
	end
	return Vector2.new(size.X / 2, size.Y * 0.55)
end

-- A burst of sparkles in the world.
local function worldBurst(position: Vector3, amount: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "GaG_RewardBurst"
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(12, 30)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(ORB_LIGHT, GOLD)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = attachment
	emitter:Emit(math.clamp(12 + math.floor(math.log10(amount + 1) * 8), 12, 50))
	Debris:AddItem(attachment, 2)
end

-- One glowing orb: bursts out from `from`, then streams into the wallet.
local function orb(from: Vector2, delay: number)
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(ORB_SIZE, ORB_SIZE)
	dot.Position = UDim2.fromOffset(from.X, from.Y)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BorderSizePixel = 0
	dot.ZIndex = 5
	dot.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = dot
	local fill = Instance.new("UIGradient")
	fill.Color = ColorSequence.new(ORB_LIGHT, GOLD)
	fill.Rotation = 45
	fill.Parent = dot
	local glow = Instance.new("UIStroke")
	glow.Color = GOLD
	glow.Thickness = 3
	glow.Transparency = 0.35
	glow.Parent = dot

	local angle = math.random() * math.pi * 2
	local reach = 40 + math.random() * 70
	local out = from + Vector2.new(math.cos(angle), math.sin(angle)) * reach
	task.delay(delay, function()
		local burst = TweenService:Create(dot, BURST, { Position = UDim2.fromOffset(out.X, out.Y) })
		burst:Play()
		burst.Completed:Wait()
		local target = HudController.walletTarget()
		local fly = TweenService:Create(dot, FLY, {
			Position = UDim2.fromOffset(target.X, target.Y),
			Size = UDim2.fromOffset(ORB_SIZE * 0.5, ORB_SIZE * 0.5),
		})
		fly:Play()
		fly.Completed:Wait()
		dot:Destroy()
		HudController.bumpWallet()
	end)
end

-- "+1.2K" with a caption, bouncing in at `at` and floating up as it fades.
local function popup(at: Vector2, amount: number, caption: string?)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromOffset(at.X, at.Y - 30)
	holder.Size = UDim2.fromOffset(320, 70)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 6
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = holder
	local big = Theme.label(holder, {
		Size = UDim2.new(1, 0, 0, 42),
		Text = `+{Format.abbreviate(amount)} {CURRENCY}`,
		Font = Enum.Font.GothamBlack,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.2,
		TextStrokeColor3 = Color3.fromRGB(80, 40, 0),
		ZIndex = 6,
	})
	local small = Theme.label(holder, {
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 22),
		Text = caption or "",
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		ZIndex = 6,
	})
	TweenService:Create(scale, POP, { Scale = 1 }):Play()
	task.delay(0.9, function()
		local fade = TweenInfo.new(0.6)
		TweenService:Create(holder, fade, { Position = UDim2.fromOffset(at.X, at.Y - 90) }):Play()
		TweenService:Create(big, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(small, fade, { TextTransparency = 1, TextStrokeTransparency = 1 })
			:Play()
		task.wait(0.6)
		holder:Destroy()
	end)
end

local function showBanner(name: string, details: string)
	bannerTitle.Text = name
	bannerBody.Text = details
	banner.Visible = true
	banner.Position = UDim2.new(0.5, 0, 0, -120)
	TweenService:Create(banner, POP, { Position = UDim2.new(0.5, 0, 0, 70) }):Play()
	Theme.popIn(banner)
	task.delay(3.5, function()
		local away = TweenService:Create(
			banner,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, 0, -120) }
		)
		away:Play()
		away.Completed:Wait()
		banner.Visible = false
	end)
end

local function onReward(kind: unknown, amount: unknown, position: unknown, label: unknown)
	if type(amount) ~= "number" then
		return
	end
	local world = if typeof(position) == "Vector3" then position :: Vector3 else nil
	local caption = if type(label) == "string" then label else nil
	if kind == "achievement" then
		local name, details = string.match(caption or "", "^(.-)|(.*)$")
		showBanner(name or "Achievement unlocked", details or "")
		if amount <= 0 then
			return
		end
		caption = nil
	end
	if world then
		worldBurst(world, amount)
	end
	local from = screenPoint(world)
	local orbs = math.clamp(4 + math.floor(math.log10(amount + 1) * 3), 4, MAX_ORBS)
	if ClientState.reducedEffects then
		orbs = math.min(orbs, 5)
	end
	for index = 1, orbs do
		orb(from, (index - 1) * 0.035)
	end
	popup(from, amount, caption)
end

-- "ready to collect" over your own station's Collect console.
local function findCollector()
	local slot = ClientState.mySlot()
	local regions = Workspace:FindFirstChild("Regions")
	local region = if slot and regions then regions:FindFirstChild(`Region_{slot}`) else nil
	local console = if region then region:FindFirstChild("CollectConsole", true) else nil
	if console == nil or not console:IsA("BasePart") then
		return
	end
	if collectLabel and collectLabel.Adornee == console then
		return
	end
	if collectLabel then
		collectLabel:Destroy()
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GaG_CollectReady"
	billboard.Size = UDim2.fromOffset(220, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 250
	billboard.Adornee = console
	-- Billboards don't render inside a ScreenGui; the camera is local-only.
	billboard.Parent = Workspace.CurrentCamera
	local text = Theme.label(billboard, {
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.3,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = text
	collectLabel = billboard
	collectText = text
end

local function refreshCollector()
	findCollector()
	local profile = ClientState.profile
	local billboard, text = collectLabel, collectText
	if billboard == nil or text == nil or profile == nil then
		return
	end
	local ready = math.floor(profile.uncollected)
	billboard.Enabled = ready >= 1
	text.Text = `{Format.abbreviate(ready)} ready to collect`
end

function RewardController.init()
	gui = Theme.screen("Rewards", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10

	banner = Theme.panel(gui, "AchievementBanner")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Size = UDim2.fromOffset(420, 84)
	banner.Visible = false
	local edge = banner:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Color = GOLD
		edge.Transparency = 0
		edge.Thickness = 3
	end
	Theme.label(banner, {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "ACHIEVEMENT UNLOCKED",
		TextSize = 14,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = GOLD,
	})
	bannerTitle = Theme.label(banner, {
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -24, 0, 28),
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	bannerBody = Theme.label(banner, {
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(1, -24, 0, 20),
		TextSize = 15,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.COLORS.subtle,
	})
end

function RewardController.start()
	Net.Reward.OnClientEvent:Connect(onReward)
	ClientState.profileChanged:Connect(function(field)
		if field == "uncollected" or field == "*" then
			refreshCollector()
		end
	end)
	ClientState.regionsChanged:Connect(refreshCollector)
	-- The label gently pulses while there is something to collect.
	task.spawn(function()
		local pulse = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
		while true do
			local text = collectText
			local scale = text and text:FindFirstChildOfClass("UIScale")
			if scale and collectLabel and collectLabel.Enabled then
				TweenService:Create(scale, pulse, { Scale = 1.12 }):Play()
			end
			task.wait(1.4)
			refreshCollector()
		end
	end)
end

return RewardController
