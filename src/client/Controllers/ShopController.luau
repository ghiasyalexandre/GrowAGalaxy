--!strict
-- The Shipyard panel, opened from your station's Shipyard console: buy and
-- select ships, buy equipment, and expand your galaxy, all for Stardust.
-- Prices and ownership come from config and your profile view; the server
-- (ShopSystem) checks and performs every purchase.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Logic"):WaitForChild("Progression"))

local CURRENCY = Config.Economy.CURRENCY_NAME
local STAT_NAMES: { [string]: string } = {
	maxSpeed = "speed",
	acceleration = "acceleration",
	braking = "braking",
	turnRate = "turning",
	beamPower = "laser power",
	beamRange = "laser range",
	heatCapacity = "heat capacity",
	coolingRate = "cooling",
	cargoCapacity = "cargo",
}

local ShopController = {}

local gui: ScreenGui
local list: ScrollingFrame
local firstButton: TextButton? = nil

local function close()
	gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local function request(action: string, id: string?)
	local ok, message = Net.ShopRequest:InvokeServer(action, id)
	ClientState.notify:Fire(
		if type(message) == "string" then message else if ok then "Done" else "Failed"
	)
end

local function heading(text: string, order: number)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 24)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(255, 214, 120)
	label.Text = text
	label.Parent = list
end

-- A row: description on the left, an action button (or status) on the right.
local function row(
	order: number,
	title: string,
	detail: string,
	buttonText: string,
	onClick: (() -> ())?
)
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, 52)
	frame.BackgroundColor3 = Color3.fromRGB(28, 34, 58)
	frame.BackgroundTransparency = 0.2
	frame.Parent = list
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromOffset(10, 4)
	name.Size = UDim2.new(1, -140, 0, 22)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 16
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Text = title
	name.Parent = frame
	local info = name:Clone()
	info.Position = UDim2.fromOffset(10, 26)
	info.Font = Enum.Font.Gotham
	info.TextSize = 13
	info.TextColor3 = Color3.fromRGB(180, 190, 220)
	info.TextTruncate = Enum.TextTruncate.AtEnd
	info.Text = detail
	info.Parent = frame

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -8, 0.5, 0)
	button.Size = UDim2.fromOffset(120, 34)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = buttonText
	button.AutoButtonColor = onClick ~= nil
	button.Active = onClick ~= nil
	button.BackgroundColor3 = if onClick
		then Color3.fromRGB(56, 92, 170)
		else Color3.fromRGB(50, 54, 70)
	button.Parent = frame
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = button
	if onClick then
		button.Activated:Connect(onClick)
		if firstButton == nil then
			firstButton = button
		end
	end
end

local function priceText(cost: number, stardust: number): string
	return if stardust >= cost
		then `Buy: {Format.abbreviate(cost)}`
		else `{Format.abbreviate(cost)} {CURRENCY}`
end

local function refresh()
	local profile = ClientState.profile
	if profile == nil or not gui.Enabled then
		return
	end
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	firstButton = nil
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	heading("Ships", nextOrder())
	for _, shipId in Config.Ships.ORDER do
		local def = Config.Ships.BY_ID[shipId]
		if not def.enabled then
			continue
		end
		local s = def.stats
		local detail =
			`{def.role} · speed {s.maxSpeed} · laser {s.beamPower} · range {s.beamRange} · heat {s.heatCapacity}`
		if profile.activeShip == shipId then
			row(nextOrder(), def.displayName, detail, "Active", nil)
		elseif profile.ownedShips[shipId] then
			row(nextOrder(), def.displayName, detail, "Select", function()
				request("selectShip", shipId)
			end)
		else
			local cost = Progression.shipCost(shipId)
			if cost then
				row(
					nextOrder(),
					def.displayName,
					detail,
					priceText(cost, profile.stardust),
					function()
						request("buyShip", shipId)
					end
				)
			end
		end
	end

	heading("Equipment (fitted to every ship you own)", nextOrder())
	for _, itemId in Config.Equipment.ORDER do
		local def = Config.Equipment.BY_ID[itemId]
		local cost = Progression.equipmentCost(itemId)
		if cost == nil then
			continue
		end
		local effects: { string } = {}
		for stat, multiplier in def.modifiers do
			table.insert(
				effects,
				`+{math.floor((multiplier - 1) * 100 + 0.5)}% {STAT_NAMES[stat] or stat}`
			)
		end
		local detail = table.concat(effects, ", ")
		if profile.ownedEquipment[itemId] then
			row(nextOrder(), def.displayName, detail, "Owned", nil)
		else
			row(nextOrder(), def.displayName, detail, priceText(cost, profile.stardust), function()
				request("buyEquipment", itemId)
			end)
		end
	end

	heading("Galaxy", nextOrder())
	local level = profile.expansion
	local current = Config.Galaxy.EXPANSIONS[level]
	local cost = Progression.expansionCost(level)
	if cost then
		local nextDef = Config.Galaxy.EXPANSIONS[level + 1]
		local detail =
			`Holds {current.maxSystems} stars now; expanding raises it to {nextDef.maxSystems} and grows your region`
		row(
			nextOrder(),
			`Expansion {level + 1}`,
			detail,
			priceText(cost, profile.stardust),
			function()
				request("expand")
			end
		)
	else
		row(nextOrder(), "Galaxy fully expanded", `Holds {current.maxSystems} stars`, "Max", nil)
	end

	if Input.device() == "gamepad" and firstButton then
		GuiService.SelectedObject = firstButton
	end
end

local function open()
	gui.Enabled = true
	refresh()
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Shipyard"
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0.75, 0)
	panel.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	panel.BackgroundTransparency = 0.1
	panel.Parent = gui
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(560, 520)
	size.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(1, -120, 0, 30)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "Shipyard"
	title.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 8)
	closeButton.Size = UDim2.fromOffset(90, 30)
	closeButton.BackgroundColor3 = Color3.fromRGB(90, 50, 60)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 14
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.Text = "Close"
	closeButton.Parent = panel
	closeButton.Activated:Connect(close)

	list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(12, 46)
	list.Size = UDim2.new(1, -24, 1, -58)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function ShopController.init()
	build()
end

function ShopController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("TycoonAction") ~= "Shipyard" then
			return
		end
		-- The console sits inside its owner's region model.
		local owner: Instance? = prompt:FindFirstAncestorOfClass("Model")
		while owner and owner:GetAttribute("OwnerUserId") == nil do
			owner = owner:FindFirstAncestorOfClass("Model")
		end
		if owner and owner:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
			ClientState.notify:Fire("This is someone else's Shipyard.")
			return
		end
		open()
	end)
	ClientState.profileChanged:Connect(function(field)
		if
			field == "stardust"
			or field == "ownedShips"
			or field == "activeShip"
			or field == "ownedEquipment"
			or field == "expansion"
			or field == "*"
		then
			refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and gui.Enabled and input.KeyCode == Enum.KeyCode.Backspace then
			close()
		end
	end)
end

return ShopController
