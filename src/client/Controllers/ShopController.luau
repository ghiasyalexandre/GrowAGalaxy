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
local Theme = require(script.Parent.Parent.UI.Theme)

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
	boostMultiplier = "boost",
	boostDuration = "boost time",
	boostRecharge = "boost recharge",
}

local ShopController = {}

local gui: ScreenGui
local list: ScrollingFrame
local panel: Frame
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

local function heading(text: string, order: number, iconName: string?)
	local holder = Theme.row(list, 28, order)
	holder.BackgroundTransparency = 1
	local icon = if iconName then Theme.icon(holder, iconName, 30) else nil
	local inset = 0
	if icon then
		icon.Position = UDim2.fromOffset(0, -1)
		inset = 36
	end
	Theme.label(holder, {
		Position = UDim2.fromOffset(inset, 0),
		Size = UDim2.new(1, -inset, 1, 0),
		Text = text,
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Theme.COLORS.gold,
	})
end

-- A row: description on the left, an action button (or status) on the right.
local function row(
	order: number,
	title: string,
	detail: string,
	buttonText: string,
	onClick: (() -> ())?
)
	local frame = Theme.row(list, 54, order)
	Theme.label(frame, {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -170, 0, 22),
		Text = title,
	})
	Theme.label(frame, {
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -170, 0, 18),
		Text = detail,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Theme.COLORS.subtle,
	})
	local style: Theme.ButtonStyle = if onClick == nil
		then "disabled"
		elseif string.find(buttonText, "Buy") then "buy"
		else "primary"
	local button = Theme.button(frame, buttonText, style, onClick)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -8, 0.5, 0)
	button.Size = UDim2.fromOffset(140, 36)
	if onClick and firstButton == nil then
		firstButton = button
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
	Theme.clear(list)
	firstButton = nil
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	heading("Ships", nextOrder(), "Ship")
	for _, shipId in Config.Ships.ORDER do
		local def = Config.Ships.BY_ID[shipId]
		if not def.enabled then
			continue
		end
		local s = def.stats
		local detail =
			`{def.role} · speed {s.maxSpeed} · boost x{s.boostMultiplier} for {s.boostDuration}s · laser {s.beamPower} · heat {s.heatCapacity}`
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

	heading("Equipment (fitted to every ship you own)", nextOrder(), "Laser")
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

	heading("Galaxy", nextOrder(), "Galaxy")
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
	Theme.popIn(panel)
end

local function build()
	gui = Theme.screen("Shipyard", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false

	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0.75, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(580, 540)
	size.Parent = panel

	-- Sprite sheet: the ship icon before the title.
	local titleX = 16
	local icon = Theme.icon(panel, "Ship", 50)
	if icon then
		icon.Position = UDim2.fromOffset(10, 0)
		icon.ZIndex = 2
		titleX = 66
	end
	Theme.label(panel, {
		Position = UDim2.fromOffset(titleX, 10),
		Size = UDim2.new(1, -titleX - 104, 0, 30),
		Text = "Shipyard",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextColor3 = Theme.COLORS.gold,
	})
	local closeButton = Theme.button(panel, "Close", "primary", close)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.fromOffset(80, 30)

	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(14, 50)
	list.Size = UDim2.new(1, -28, 1, -62)
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
