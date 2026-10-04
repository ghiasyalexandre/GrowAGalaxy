--!strict
-- Objective marker: a label with the distance over the current route target,
-- visible from anywhere and local to this client. The route starts at "Your
-- station"; the navigation consoles (prompts tagged "RoutePrompt") switch it
-- between your station and the ISS docking area.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local HIDE_WITHIN = 90 -- studs; the marker hides once you've arrived
local UPDATE_INTERVAL = 0.25

local LABELS: { [string]: string } = {
	Station = "Your station",
	ISS = "ISS docking area",
}

local WaypointController = {}

local billboard: BillboardGui
local label: TextLabel
local trackedKey: string? = nil

local function build()
	billboard = Instance.new("BillboardGui")
	billboard.Name = "RouteWaypoint"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(200, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
	billboard.LightInfluence = 0
	billboard.Enabled = false

	label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 214, 120)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard

	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Waits for the target part to replicate: your station's beacon, or the
-- ISS docking zone.
local function findTarget(route: string, slot: number?): BasePart?
	if route == "ISS" then
		local world = Workspace:WaitForChild("World", 30)
		local iss = world and world:WaitForChild("ISS", 30)
		local zone = iss and iss:FindFirstChild("DockZone", true)
		return if zone and zone:IsA("BasePart") then zone else nil
	end
	if slot == nil then
		return nil
	end
	local regions = Workspace:WaitForChild("Regions", 30)
	local region = regions and regions:WaitForChild(`Region_{slot}`, 30)
	local station = region and region:WaitForChild("Station", 30)
	local beacon = station and station:WaitForChild("Beacon", 30)
	return if beacon and beacon:IsA("BasePart") then beacon else nil
end

local function track()
	local route = ClientState.route
	local slot = ClientState.mySlot()
	local key = `{route}:{slot}`
	if key == trackedKey then
		return
	end
	trackedKey = key
	billboard.Adornee = nil :: any
	billboard.Enabled = false
	task.spawn(function()
		local target = findTarget(route, slot)
		if target and trackedKey == key then
			billboard.Adornee = target
			billboard.Enabled = true
		end
	end)
end

local function refresh()
	local target = billboard.Adornee
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (target and target:IsA("BasePart") and root and root:IsA("BasePart")) then
		return
	end
	local distance = (target.Position - root.Position).Magnitude
	label.Visible = distance > HIDE_WITHIN
	label.Text = `{LABELS[ClientState.route]}\n{math.floor(distance)} studs`
end

function WaypointController.init()
	build()
	ClientState.regionsChanged:Connect(track)
	ClientState.routeChanged:Connect(track)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local target = prompt:GetAttribute("RouteTarget")
		if player == Players.LocalPlayer and (target == "Station" or target == "ISS") then
			ClientState.setRoute(target)
			ClientState.notify:Fire(`Route set: {LABELS[target]}. Follow the marker.`)
		end
	end)
end

function WaypointController.start()
	track()
	task.spawn(function()
		while true do
			refresh()
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return WaypointController
