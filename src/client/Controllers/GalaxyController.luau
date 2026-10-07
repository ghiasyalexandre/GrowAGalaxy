--!strict
-- Galaxy Control: the console beside Collect on your hangar deck (prompt
-- attribute OpenPanel = "Galaxy", StationBuilder) opens one panel for your
-- whole galaxy.
--
--   Galaxy size  your galaxy's size, stars placed out of what it holds, and
--                the next expansion with its price and a Buy button
--                (ShopRequest "expand", as in the Shipyard).
--   Systems      every star you own: type, level, production and orbits in
--                use, with Level up (or Evolve at max level), Manage (the
--                star's own panel: planets, move) and Inspect.
--   Buy a star   opens the Star Shop.
--
-- Only the owner can use their console; a visitor is told whose it is. The
-- server checks every purchase (ShopSystem, StarSystem).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Parent.Input)
local StarController = require(script.Parent.StarController)
local Theme = require(script.Parent.Parent.UI.Theme)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Net = require(Shared:WaitForChild("Net"))
local PlanetInventory = require(Shared:WaitForChild("Logic"):WaitForChild("PlanetInventory"))
local Progression = require(Shared:WaitForChild("Logic"):WaitForChild("Progression"))
local StarMath = require(Shared:WaitForChild("Logic"):WaitForChild("StarMath"))

local S = Config.Stars
local C = Theme.COLORS
local CURRENCY = Config.Economy.CURRENCY_NAME
local PURPLE = Color3.fromRGB(176, 107, 255)

local GalaxyController = {}

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local list: ScrollingFrame
local busy = false

local function fmt(n: number): string
	return Format.abbreviate(n)
end

local function close()
	gui.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local refresh: () -> ()

local function ask(remote: RemoteFunction, ...: any)
	if busy then
		return
	end
	busy = true
	local ok, message = remote:InvokeServer(...)
	busy = false
	ClientState.notify:Fire(
		if type(message) == "string" then message else if ok then "Done" else "Failed"
	)
	refresh()
end

local function button(
	row: Frame,
	text: string,
	style: Theme.ButtonStyle,
	x: number,
	width: number,
	onClick: (() -> ())?
): TextButton
	local made = Theme.button(row, text, style, onClick)
	made.AnchorPoint = Vector2.new(1, 0.5)
	made.Position = UDim2.new(1, -x, 0.5, 0)
	made.Size = UDim2.fromOffset(width, 34)
	made.TextSize = 13
	return made
end

local function sizeCard(order: number, stars: number)
	local profile = ClientState.profile
	local level = if profile then profile.expansion else 1
	local stardust = if profile then profile.stardust else 0
	local current = Config.Galaxy.EXPANSIONS[level]
	local row = Theme.row(list, 72, order)
	local icon = Theme.icon(row, "Galaxy", 52)
	if icon then
		icon.Position = UDim2.fromOffset(10, 10)
	end
	Theme.label(row, {
		Position = UDim2.fromOffset(72, 8),
		Size = UDim2.new(1, -260, 0, 24),
		Text = `Galaxy size {level} of {#Config.Galaxy.EXPANSIONS}`,
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		TextColor3 = PURPLE,
	})
	local cost = Progression.expansionCost(level)
	local nextDef = Config.Galaxy.EXPANSIONS[level + 1]
	Theme.label(row, {
		Position = UDim2.fromOffset(72, 36),
		Size = UDim2.new(1, -260, 0, 30),
		Text = if nextDef
			then `{stars}/{current.maxSystems} stars placed. Next size holds {nextDef.maxSystems} stars and gives you more space.`
			else `{stars}/{current.maxSystems} stars placed. Your galaxy is as big as it gets!`,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.subtle,
	})
	if cost then
		local affordable = stardust >= cost
		button(
			row,
			if affordable then `Expand · {fmt(cost)}` else `Need {fmt(cost)}`,
			if affordable then "special" else "disabled",
			10,
			170,
			if affordable
				then function()
					ask(Net.ShopRequest, "expand")
				end
				else nil
		)
	else
		button(row, "Max size", "disabled", 10, 170, nil)
	end
end

local function starRow(order: number, starId: string, model: Model, stardust: number)
	local typeId = model:GetAttribute("TypeId")
	local level = model:GetAttribute("Level")
	local income = model:GetAttribute("Income")
	if type(typeId) ~= "string" or type(level) ~= "number" then
		return
	end
	local def = S.BY_ID[typeId]
	local top = StarMath.maxLevel(typeId)
	local open = StarMath.slots(typeId)
	local profile = ClientState.profile
	local used = 0
	for _ in
		PlanetInventory.idsOn(if profile and profile.planets then profile.planets else {}, starId)
	do
		used += 1
	end
	local row = Theme.row(list, 56, order)
	local dot = Theme.starIcon(
		row,
		if def then Color3.fromHex(def.color) else C.gold,
		if def then Color3.fromHex(def.light) else C.gold,
		38,
		if typeId == S.ORDER[#S.ORDER] then "blackHole" else "star"
	)
	dot.Position = UDim2.fromOffset(10, 9)
	Theme.label(row, {
		Position = UDim2.fromOffset(58, 7),
		Size = UDim2.new(1, -440, 0, 20),
		Text = `{if def then def.displayName else typeId}  ·  Lv {level}/{top}`,
		TextColor3 = if def then Color3.fromHex(def.light) else C.text,
	})
	Theme.label(row, {
		Position = UDim2.fromOffset(58, 29),
		Size = UDim2.new(1, -440, 0, 18),
		Text = `+{fmt(if type(income) == "number" then income else 0)}/s  ·  planets {used}/{open}`,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = C.subtle,
	})
	-- Right to left: Inspect, Manage, Level up / Evolve.
	button(row, "Inspect", "primary", 8, 84, function()
		close()
		ClientState.inspectStar:Fire(model)
	end)
	button(row, "Manage", "primary", 98, 90, function()
		close()
		StarController.openPanel(model)
	end)
	local upgrade = StarMath.upgradeCost(typeId, level)
	local target = StarMath.evolveTarget(typeId)
	if upgrade then
		local ok = stardust >= upgrade
		button(
			row,
			`Level up · {fmt(upgrade)}`,
			if ok then "buy" else "disabled",
			194,
			150,
			if ok
				then function()
					ask(Net.StarRequest, "upgrade", starId)
				end
				else nil
		)
	elseif target then
		local cost = S.BY_ID[target].cost
		local ok = stardust >= cost
		button(
			row,
			`Evolve · {fmt(cost)}`,
			if ok then "special" else "disabled",
			194,
			150,
			if ok
				then function()
					ask(Net.StarRequest, "evolve", starId)
				end
				else nil
		)
	else
		button(row, "Fully grown", "disabled", 194, 150, nil)
	end
end

refresh = function()
	if not gui.Enabled then
		return
	end
	Theme.clear(list)
	local profile = ClientState.profile
	local stardust = if profile then profile.stardust else 0
	local stars = StarController.myStars()
	local ids: { string } = {}
	local total = 0
	for id, model in stars do
		table.insert(ids, id)
		local income = model:GetAttribute("Income")
		total += if type(income) == "number" then income else 0
	end
	table.sort(ids, function(a, b)
		return (tonumber(string.sub(a, 2)) or 0) < (tonumber(string.sub(b, 2)) or 0)
	end)
	header.Text =
		`{#ids} solar systems  ·  +{fmt(total)} {CURRENCY}/s  ·  you have {fmt(stardust)}`
	sizeCard(1, #ids)
	local order = 2
	for _, id in ids do
		starRow(order, id, stars[id], stardust)
		order += 1
	end
	local shopRow = Theme.row(list, 48, order)
	shopRow.BackgroundTransparency = 1
	local shop = Theme.button(
		shopRow,
		if #ids == 0 then "Buy your first star" else "Buy another star",
		"buy",
		function()
			close()
			ClientState.openStarShop:Fire()
		end
	)
	shop.Size = UDim2.new(0, 220, 1, -6)
	if Input.device() == "gamepad" and GuiService.SelectedObject == nil then
		GuiService.SelectedObject = shop
	end
end

local function open()
	gui.Enabled = true
	refresh()
	Theme.popIn(panel)
end

function GalaxyController.init()
	gui = Theme.screen("GalaxyControl", Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.Enabled = false
	panel = Theme.panel(gui, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.94, 0, 0.84, 0)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(820, 700)
	size.Parent = panel
	local titleX = 16
	local icon = Theme.icon(panel, "Galaxy", 44)
	if icon then
		icon.Position = UDim2.fromOffset(12, 2)
		icon.ZIndex = 2
		titleX = 60
	end
	Theme.label(panel, {
		Position = UDim2.fromOffset(titleX, 10),
		Size = UDim2.new(1, -titleX - 104, 0, 28),
		Text = "Galaxy Control",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextColor3 = PURPLE,
	})
	header = Theme.label(panel, {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 18),
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = C.subtle,
	})
	Theme.closeButton(panel, close)
	list = Theme.list(panel, 6)
	list.Position = UDim2.fromOffset(14, 66)
	list.Size = UDim2.new(1, -28, 1, -78)
end

function GalaxyController.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("OpenPanel") ~= "Galaxy" then
			return
		end
		-- Only your own console: it sits inside your region.
		local owner: Instance? = prompt:FindFirstAncestorOfClass("Model")
		while owner and owner:GetAttribute("OwnerUserId") == nil do
			owner = owner:FindFirstAncestorOfClass("Model")
		end
		if owner and owner:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
			ClientState.notify:Fire("This is someone else's Galaxy Control.")
			return
		end
		open()
	end)
	ClientState.profileChanged:Connect(function(field)
		if field == "stardust" or field == "expansion" or field == "planets" or field == "*" then
			refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and gui.Enabled and input.KeyCode == Enum.KeyCode.Backspace then
			close()
		end
	end)
end

return GalaxyController
