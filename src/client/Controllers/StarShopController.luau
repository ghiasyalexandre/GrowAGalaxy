--!strict
-- The Star Shop panel, opened from your station's Star Shop console, the
-- HUD's Star Shop button or the B key (ClientState.openStarShop). Lists
-- every star tier with its price (rising with each star you own), production
-- and best planet tier. Unlocked, affordable stars start ghost placement
-- (PlacementController); the server re-checks everything when you confirm.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local PlacementController = require(script.Parent.PlacementController)
local StarController = require(script.Parent.StarController)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local RegionMath = require(Shared:WaitForChild("Logic"):WaitForChild("RegionMath"))
local StarMath = require(Shared:WaitForChild("Logic"):WaitForChild("StarMath"))

local S = Config.Stars
local P = Config.Planets
local C = Theme.COLORS
local CURRENCY = Config.Economy.CURRENCY_NAME

local StarShopController = {}

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local list: ScrollingFrame

local function close()
	gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

-- My stars as save-like records, for the tier rules.
local function myRecords(): { [string]: any }
	local records = {}
	for id, model in StarController.myStars() do
		records[id] = { typeId = model:GetAttribute("TypeId"), level = 1, planets = {} }
	end
	return records
end

local function count(t: { [string]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function refresh()
	local profile = ClientState.profile
	if profile == nil or not gui.Enabled then
		return
	end
	local records = myRecords()
	local owned = count(records)
	local capacity = RegionMath.maxSystems(profile.expansion)
	header.Text = `Your galaxy: {owned} / {capacity} stars`
	Theme.clear(list)
	local first: TextButton? = nil
	for order, typeId in S.ORDER do
		local def = S.BY_ID[typeId]
		if not def.enabled then
			continue
		end
		local row = Theme.row(list, 64, order)
		local dot = Theme.swatch(row, Color3.fromHex(def.color), 38, true)
		dot.Position = UDim2.fromOffset(10, 13)
		local bestPlanet = P.BY_ID[P.ORDER[math.min(def.tier, #P.ORDER)]]
		Theme.label(row, {
			Position = UDim2.fromOffset(60, 6),
			Size = UDim2.new(1, -250, 0, 20),
			Text = `{def.displayName}  ·  tier {def.tier}`,
			TextColor3 = Color3.fromHex(def.light),
		})
		Theme.label(row, {
			Position = UDim2.fromOffset(60, 26),
			Size = UDim2.new(1, -250, 0, 16),
			Text = `+{Format.abbreviate(def.income)} {CURRENCY}/s  ·  planets up to {bestPlanet.displayName}`,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = C.subtle,
		})
		Theme.label(row, {
			Position = UDim2.fromOffset(60, 43),
			Size = UDim2.new(1, -250, 0, 16),
			Text = def.description,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = C.subtle,
		})
		local cost = StarMath.placeCost(typeId, owned) or 0
		local button: TextButton
		if not StarMath.typeUnlocked(typeId, records) then
			local previous = S.BY_ID[S.ORDER[def.tier - 1]]
			button = Theme.button(row, `Needs a {previous.displayName}`, "disabled", nil)
		elseif owned >= capacity then
			button = Theme.button(row, "Galaxy full", "disabled", nil)
		elseif profile.stardust < cost then
			button = Theme.button(row, `{Format.abbreviate(cost)} {CURRENCY}`, "disabled", nil)
		else
			button = Theme.button(row, `Buy · {Format.abbreviate(cost)}`, "buy", function()
				close()
				PlacementController.begin({ mode = "place", typeId = typeId })
			end)
			first = first or button
		end
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
		button.Size = UDim2.fromOffset(170, 38)
	end
	if Input.device() == "gamepad" and first then
		GuiService.SelectedObject = first
	end
end

local function open()
	if PlacementController.isActive() then
		return
	end
	gui.Enabled = true
	local ok, problem = pcall(refresh :: any)
	if not ok then
		warn(`[StarShop] Could not list the stars: {problem}`)
	end
	Theme.popIn(panel)
end

function StarShopController.init()
	gui = Theme.screen("StarShop", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0.8, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(600, 600)
	size.Parent = panel
	Theme.label(panel, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -120, 0, 28),
		Text = "Star Shop",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextColor3 = C.gold,
	})
	header = Theme.label(panel, {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 18),
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = C.subtle,
	})
	local closeButton = Theme.button(panel, "Close", "primary", close)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.fromOffset(80, 30)
	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(14, 66)
	list.Size = UDim2.new(1, -28, 1, -78)
end

function StarShopController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("TycoonAction") ~= "Shop" then
			return
		end
		-- The station sits inside its owner's region model.
		local owner: Instance? = prompt:FindFirstAncestorOfClass("Model")
		while owner and owner:GetAttribute("OwnerUserId") == nil do
			owner = owner:FindFirstAncestorOfClass("Model")
		end
		if owner and owner:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
			ClientState.notify:Fire("This is someone else's Star Shop.")
			return
		end
		open()
	end)
	ClientState.profileChanged:Connect(function(field)
		if field == "stardust" or field == "expansion" or field == "incomeRate" or field == "*" then
			refresh()
		end
	end)
	ClientState.openStarShop:Connect(function()
		if gui.Enabled then
			close()
		else
			open()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if gui.Enabled and input.KeyCode == Enum.KeyCode.Backspace then
			close()
		elseif input.KeyCode == Enum.KeyCode.B then
			ClientState.openStarShop:Fire()
		end
	end)
end

return StarShopController
