--!strict
-- The premium shortcut in the HUD's top-right row: a round, pulsing window with a
-- spinning rainbow ring that shows, alternating every SWAP_SECONDS, a
-- late-game ship (its imported model, turning) or a black hole with a
-- swirling accretion disk. Clicking opens the Galaxy Store on that offer's
-- tab (Ships or Passes). It never opens anything by itself. A small gold
-- tag on its corner shows the offer's current Robux price (UI/Prices).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.Parent.ClientState)
local Prices = require(script.Parent.Parent.UI.Prices)
local Theme = require(script.Parent.Parent.UI.Theme)
local Layout = require(script.Parent.Parent.UI.Layout)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ShipModel = require(Shared:WaitForChild("Util"):WaitForChild("ShipModel"))

local SWAP_SECONDS = 15
local SIZE = 96
local SHIP_ID = "MeteorSlicer" -- the flagship, sold as a Robux pass
local GOLD = Color3.fromRGB(255, 211, 107)
local CYAN = Color3.fromRGB(95, 227, 255)
local VIOLET = Color3.fromRGB(176, 120, 255)
local MAGENTA = Color3.fromRGB(255, 110, 200)
local FADE = TweenInfo.new(0.6, Enum.EasingStyle.Quad)

type Slide = {
	view: ViewportFrame,
	title: string,
	tab: string,
	product: string, -- Config.Products key whose price the tag shows
	spin: (number) -> (),
}

local PremiumController = {}

local slides: { Slide } = {}
local refreshPrice: () -> ()
local current = 1
local caption: TextLabel
local priceTag: TextLabel

local function viewport(parent: Instance): ViewportFrame
	local view = Instance.new("ViewportFrame")
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(170, 170, 200)
	view.LightColor = Color3.new(1, 1, 1)
	view.LightDirection = Vector3.new(-1, -1.5, -1)
	view.ImageTransparency = 1
	view.ZIndex = 2
	view.Parent = parent
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = view
	return view
end

local function camera(view: ViewportFrame, reach: number, height: number)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.CFrame = CFrame.lookAt(Vector3.new(0, height, reach), Vector3.zero)
	cam.Parent = view
	view.CurrentCamera = cam
end

local function part(
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- A black hole: a dark core inside two tilted, counter-spinning disks.
local function blackHoleSlide(parent: Instance): Slide
	local view = viewport(parent)
	view.Ambient = Color3.fromRGB(255, 255, 255)
	local core = part(
		Enum.PartType.Ball,
		Vector3.one * 4,
		Color3.new(0, 0, 0),
		Enum.Material.SmoothPlastic,
		view
	)
	core.CFrame = CFrame.identity
	local halo = part(Enum.PartType.Ball, Vector3.one * 4.6, VIOLET, Enum.Material.Neon, view)
	halo.Transparency = 0.6
	local disk = part(
		Enum.PartType.Cylinder,
		Vector3.new(0.15, 10, 10),
		Color3.fromRGB(255, 150, 60),
		Enum.Material.Neon,
		view
	)
	local outer =
		part(Enum.PartType.Cylinder, Vector3.new(0.1, 13, 13), MAGENTA, Enum.Material.Neon, view)
	outer.Transparency = 0.5
	core.Parent = view -- drawn last-ish: the core sits in front of the disk's middle
	camera(view, 13, 3.5)
	local tilt = CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(-18), 0, 0)
	return {
		view = view,
		title = "2x Star Production",
		tab = "pass",
		product = "StarMultiplier",
		spin = function(t)
			disk.CFrame = CFrame.Angles(math.rad(14), t * 1.6, 0) * tilt
			outer.CFrame = CFrame.Angles(math.rad(14), -t * 0.9, 0) * tilt
			local pulse = 1 + 0.06 * math.sin(t * 3)
			halo.Size = Vector3.one * 4.6 * pulse
		end,
	}
end

-- The ship's imported model turning, or its icon if the model isn't there.
local function shipSlide(parent: Instance): Slide
	local view = viewport(parent)
	local def = Config.Ships.BY_ID[SHIP_ID]
	local source = if def then ShipModel.find(def) else nil
	local ok, model, size = false, nil :: Model?, Vector3.one
	if source and def then
		ok, model, size = pcall(ShipModel.fit, source, def, nil)
	end
	local base = CFrame.identity
	if ok and model then
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") and def and not ShipModel.textured(item) then
				item.Color = Color3.fromHex(def.paint)
			end
		end
		model.Parent = view
		base = model:GetPivot()
		camera(view, math.max(size.X, size.Z) * 1.6, math.max(size.X, size.Z) * 0.5)
	else
		local icon = Theme.icon(view, "Ship", 70)
		if icon then
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
	return {
		view = view,
		title = if def then def.displayName else "Ships",
		tab = "ship",
		product = if def and def.productKey then def.productKey else "",
		spin = function(t)
			if ok and model then
				model:PivotTo(
					CFrame.Angles(0, t * 0.9, 0)
						* CFrame.Angles(0, 0, math.sin(t * 1.3) * 0.15)
						* base
				)
			end
		end,
	}
end

-- The price tag: the current offer's Robux price, hidden until it loads.
refreshPrice = function()
	local slide = slides[current]
	local robux = if slide then Prices.get(slide.product) else nil
	priceTag.Visible = robux ~= nil
	priceTag.Text = if robux then `R$ {robux}` else ""
end

local function show(index: number)
	current = index
	for i, slide in slides do
		local on = i == index
		TweenService:Create(slide.view, FADE, { ImageTransparency = if on then 0 else 1 }):Play()
		for _, child in slide.view:GetChildren() do
			if child:IsA("ImageLabel") then
				TweenService:Create(child, FADE, { ImageTransparency = if on then 0 else 1 }):Play()
			end
		end
	end
	caption.Text = slides[index].title
	refreshPrice()
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Premium"
	gui.ResetOnSpawn = false
	-- Below every panel (they're DisplayOrder 0 and up): the icon never
	-- covers a panel the player opened.
	gui.DisplayOrder = -1
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local button = Instance.new("TextButton")
	button.Name = "PremiumShortcut"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Size = UDim2.fromOffset(SIZE, SIZE)
	button.BackgroundColor3 = Color3.fromRGB(12, 10, 34)
	button.AutoButtonColor = false
	button.Text = ""
	-- The HUD's top-right row (UI/Layout).
	Layout.place(button, "TopRight", 4)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = button

	-- A rainbow ring that spins, and a soft glow that breathes.
	local ring = Instance.new("UIStroke")
	ring.Thickness = 4
	ring.Color = Color3.new(1, 1, 1)
	ring.Parent = button
	local rainbow = Instance.new("UIGradient")
	rainbow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CYAN),
		ColorSequenceKeypoint.new(0.33, VIOLET),
		ColorSequenceKeypoint.new(0.66, MAGENTA),
		ColorSequenceKeypoint.new(1, GOLD),
	})
	rainbow.Parent = ring
	Theme.spin(rainbow, 120)
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1.35, 1.35)
	glow.BackgroundColor3 = VIOLET
	glow.BackgroundTransparency = 0.8
	glow.ZIndex = 0
	glow.Parent = button
	local glowRound = Instance.new("UICorner")
	glowRound.CornerRadius = UDim.new(1, 0)
	glowRound.Parent = glow

	slides = { shipSlide(button), blackHoleSlide(button) }

	local tag = Theme.label(button, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.fromOffset(84, 20),
		Text = "PREMIUM",
		Font = Enum.Font.GothamBlack,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = MAGENTA,
		BackgroundTransparency = 0,
		ZIndex = 4,
	})
	local tagRound = Instance.new("UICorner")
	tagRound.CornerRadius = UDim.new(1, 0)
	tagRound.Parent = tag
	local tagFill = Instance.new("UIGradient")
	tagFill.Color = ColorSequence.new(MAGENTA, VIOLET)
	tagFill.Parent = tag
	priceTag = Theme.label(button, {
		Name = "Price",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 8, 0, -6),
		Size = UDim2.fromOffset(54, 20),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0,
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(40, 24, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6,
		Visible = false,
	})
	local priceRound = Instance.new("UICorner")
	priceRound.CornerRadius = UDim.new(1, 0)
	priceRound.Parent = priceTag
	local priceEdge = Instance.new("UIStroke")
	priceEdge.Color = Color3.new(1, 1, 1)
	priceEdge.Thickness = 1.5
	priceEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	priceEdge.Parent = priceTag
	Prices.changed:Connect(refreshPrice)

	caption = Theme.label(button, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(130, 18),
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.3,
		ZIndex = 4,
	})

	-- Pulse, spin the scenes, and swap every SWAP_SECONDS.
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local started = os.clock()
	Theme.animate(button, function(t)
		local beat = 0.5 + 0.5 * math.sin(t * 3.2)
		scale.Scale = 1 + 0.07 * beat
		glow.BackgroundTransparency = 0.88 - 0.25 * beat
		glow.Size = UDim2.fromScale(1.25 + 0.2 * beat, 1.25 + 0.2 * beat)
		for _, slide in slides do
			slide.spin(t)
		end
		local index = math.floor((t - started) / SWAP_SECONDS) % #slides + 1
		if index ~= current then
			show(index)
		end
	end)
	show(1)

	Theme.hover(button, function()
		ClientState.openStore:Fire(slides[current].tab)
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function PremiumController.start()
	build()
end

return PremiumController
