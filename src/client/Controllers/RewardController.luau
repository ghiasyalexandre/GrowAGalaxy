--!strict
-- Makes earning Stardust feel good. On every Reward from the server:
--   * a sparkle burst where it came from (the asteroid, the Collect console),
--   * glowing Stardust orbs burst out on screen and stream into the wallet,
--     which bounces as they land (HudController),
--   * a bouncing "+amount" pop-up with what it was for,
--   * for achievements, a gold banner that slides in from the top with a
--     burst of confetti.
-- Your stars' milestones (ClientState.celebrate) get the same banner in the
-- star's colour, and an evolution also flashes the screen. Banners queue.
-- It also keeps a pulsing "ready to collect" label over your station's
-- Collect console. Presentation only: the server already paid out.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)
local HudController = require(script.Parent.HudController)
local Sprites = require(script.Parent.Parent.UI.Sprites)
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
local bannerTop: () -> number -- defined below the banner code
local bannerHeader: TextLabel
local bannerTitle: TextLabel
local bannerBody: TextLabel
local bannerEdge: UIStroke
local bannerIcon: ImageLabel? = nil
local CONFETTI = 28
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 210, 90),
	Color3.fromRGB(120, 230, 255),
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(150, 255, 160),
	Color3.fromRGB(190, 150, 255),
}
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
-- With the sprite sheet the orb is the Stardust icon, tumbling as it flies.
local function makeOrb(from: Vector2): (GuiObject, number)
	local size = math.floor(ORB_SIZE * 1.8)
	local sprite = Sprites.icon(gui, "Stardust", size)
	if sprite then
		sprite.AnchorPoint = Vector2.new(0.5, 0.5)
		sprite.Position = UDim2.fromOffset(from.X, from.Y)
		sprite.Rotation = math.random(-30, 30)
		sprite.ZIndex = 5
		return sprite, size
	end
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
	return dot, ORB_SIZE
end

local function orb(from: Vector2, delay: number)
	local dot, size = makeOrb(from)

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
			Size = UDim2.fromOffset(size * 0.5, size * 0.5),
			Rotation = dot.Rotation + 180,
		})
		fly:Play()
		fly.Completed:Wait()
		dot:Destroy()
		HudController.bumpWallet()
	end)
end

-- "+1.2k" with a caption, bouncing in at `at` and floating up as it fades.
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

-- Confetti: little coloured chips that burst out of `at` and tumble down.
local function confetti(at: Vector2, color: Color3)
	local amount = if ClientState.reducedEffects then 8 else CONFETTI
	for _ = 1, amount do
		local chip = Instance.new("Frame")
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Position = UDim2.fromOffset(at.X, at.Y)
		chip.Size = UDim2.fromOffset(math.random(6, 11), math.random(10, 16))
		chip.Rotation = math.random(0, 360)
		chip.BackgroundColor3 = if math.random() < 0.5
			then color
			else CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
		chip.BorderSizePixel = 0
		chip.ZIndex = 7
		chip.Parent = gui
		local angle = math.random() * math.pi * 2
		local out = at + Vector2.new(math.cos(angle) * math.random(80, 260), -math.random(30, 160))
		local fall = out + Vector2.new(math.random(-60, 60), math.random(160, 320))
		local burst = TweenService:Create(
			chip,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(out.X, out.Y), Rotation = chip.Rotation + 180 }
		)
		burst:Play()
		burst.Completed:Once(function()
			local drop = TweenService:Create(
				chip,
				TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Position = UDim2.fromOffset(fall.X, fall.Y),
					Rotation = chip.Rotation + 360,
					BackgroundTransparency = 1,
				}
			)
			drop:Play()
			Debris:AddItem(chip, 1.2)
		end)
	end
end

-- A full-screen flash of `color` that fades out.
local function screenFlash(color: Color3)
	if ClientState.reducedEffects then
		return
	end
	local cover = Instance.new("Frame")
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.6)
	cover.BackgroundTransparency = 0.35
	cover.BorderSizePixel = 0
	cover.ZIndex = 1
	cover.Parent = gui
	TweenService:Create(cover, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(cover, 0.9)
end

type BannerItem = { header: string, name: string, details: string, color: Color3, icon: string }
local bannerQueue: { BannerItem } = {}
local bannerBusy = false

-- Shows queued banners one after another, so none hides another.
local function runBanners()
	if bannerBusy then
		return
	end
	bannerBusy = true
	task.spawn(function()
		while #bannerQueue > 0 do
			local item = table.remove(bannerQueue, 1) :: BannerItem
			bannerHeader.Text = item.header
			bannerHeader.TextColor3 = item.color
			bannerTitle.Text = item.name
			bannerBody.Text = item.details
			bannerEdge.Color = item.color
			-- Sprite sheet: the icon for this kind of banner, the frame tinted.
			local icon = bannerIcon
			if icon then
				Sprites.set(icon, item.icon)
				icon.Rotation = -20
				TweenService:Create(icon, POP, { Rotation = 0 }):Play()
			end
			Sprites.tint(banner, Color3.new(1, 1, 1):Lerp(item.color, 0.25))
			banner.Visible = true
			banner.Position = UDim2.new(0.5, 0, 0, -120)
			TweenService:Create(banner, POP, { Position = UDim2.new(0.5, 0, 0, bannerTop()) })
				:Play()
			Theme.popIn(banner)
			task.delay(0.15, function()
				confetti(banner.AbsolutePosition + banner.AbsoluteSize / 2, item.color)
			end)
			task.wait(if #bannerQueue > 0 then 2 else 3.2)
			local away = TweenService:Create(
				banner,
				TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.new(0.5, 0, 0, -120) }
			)
			away:Play()
			away.Completed:Wait()
			banner.Visible = false
		end
		bannerBusy = false
	end)
end

local function showBanner(
	header: string,
	name: string,
	details: string,
	color: Color3,
	icon: string
)
	table.insert(
		bannerQueue,
		{ header = header, name = name, details = details, color = color, icon = icon }
	)
	runBanners()
end

local function onReward(kind: unknown, amount: unknown, position: unknown, label: unknown)
	if type(amount) ~= "number" then
		return
	end
	local world = if typeof(position) == "Vector3" then position :: Vector3 else nil
	local caption = if type(label) == "string" then label else nil
	if kind == "achievement" then
		local name, details = string.match(caption or "", "^(.-)|(.*)$")
		showBanner(
			"ACHIEVEMENT UNLOCKED",
			name or "Achievement unlocked",
			details or "",
			GOLD,
			"Medal"
		)
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
	local icon = Sprites.icon(billboard, "CoinPile", 40)
	if icon then
		text.Position = UDim2.fromOffset(42, 0)
		text.Size = UDim2.new(1, -42, 1, 0)
	end
	collectLabel = billboard
	collectText = text
end

-- Where the banner settles: 70 px from the top, or just under the tutorial
-- card (or its folded tab) when that is showing, so the two never overlap.
local BANNER_TOP = 70
local BANNER_GAP = 10
bannerTop = function(): number
	local tutorial = Players.LocalPlayer.PlayerGui:FindFirstChild("Tutorial")
	local top = BANNER_TOP
	if tutorial and tutorial:IsA("ScreenGui") and tutorial.Enabled then
		local origin = banner.Parent and (banner.Parent :: GuiBase2d).AbsolutePosition
			or Vector2.zero
		for _, name in { "Card", "Tab" } do
			local item = tutorial:FindFirstChild(name)
			-- Only a card at the top of the screen (phones, tablets) is in the way.
			if item and item:IsA("GuiObject") and item.Visible and item.AnchorPoint.Y == 0 then
				local bottom = item.AbsolutePosition.Y + item.AbsoluteSize.Y - origin.Y
				top = math.max(top, bottom + BANNER_GAP)
			end
		end
	end
	return top
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
	bannerEdge = banner:FindFirstChildOfClass("UIStroke") :: UIStroke
	bannerEdge.Color = GOLD
	bannerEdge.Transparency = 0
	bannerEdge.Thickness = 3
	Theme.shine(banner)
	bannerHeader = Theme.label(banner, {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "ACHIEVEMENT UNLOCKED",
		TextSize = 14,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = GOLD,
	})
	-- Sprite sheet: an icon on the left (medal, star or planet).
	local inset = 12
	bannerIcon = Sprites.icon(banner, "Medal", 76)
	if bannerIcon then
		bannerIcon.AnchorPoint = Vector2.new(0, 0.5)
		bannerIcon.Position = UDim2.new(0, 4, 0.5, 0)
		bannerIcon.ZIndex = 3
		inset = 80
	end
	bannerTitle = Theme.label(banner, {
		Position = UDim2.fromOffset(inset, 28),
		Size = UDim2.new(1, -inset - 12, 0, 28),
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	bannerBody = Theme.label(banner, {
		Position = UDim2.fromOffset(inset, 56),
		Size = UDim2.new(1, -inset - 12, 0, 20),
		TextSize = 15,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.COLORS.subtle,
	})
end

function RewardController.start()
	Net.Reward.OnClientEvent:Connect(onReward)
	ClientState.celebrate:Connect(function(header, name, details, color, flash)
		if flash then
			screenFlash(color)
		end
		local icon = if string.find(header, "WORLD")
			then "PlanetUp"
			elseif string.find(header, "EVOLVED") then "RainbowStar"
			elseif string.find(header, "LEVEL") then "LevelUp"
			else "StarPlus"
		showBanner(header, name, details, color, icon)
	end)
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
