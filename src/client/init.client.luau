--!strict
-- Client entry point. Same two-phase bootstrap as the server: init() every
-- controller (build UI, connect events), load the starting state from the
-- server, then start() every controller. The shared input layer and the HUD
-- layout (UI/Layout) start first.
--
-- Each controller is loaded, initialised and started on its own: one that
-- errors is reported in Output and skipped, and never stops the others.

local ClientState = require(script.ClientState)
local Input = require(script.Input)
local Layout = require(script.UI.Layout)

Input.init()
-- The HUD's docks and scale, before any controller places its buttons.
Layout.init()

local Controllers = script.Controllers

local function run(name: string, phase: string, fn: () -> ()): boolean
	local ok, problem = xpcall(fn :: any, debug.traceback)
	if not ok then
		warn(`[Grow a Galaxy] {name}.{phase} failed: {problem}`)
	end
	return ok
end

local loaded: { [string]: any } = {}
for _, child in Controllers:GetChildren() do
	if child:IsA("ModuleScript") then
		run(child.Name, "require", function()
			loaded[child.Name] = require(child) :: any
		end)
	end
end

for name, controller in loaded do
	if typeof(controller.init) == "function" then
		if not run(name, "init", controller.init) then
			loaded[name] = nil
		end
	end
end

ClientState.load()

for name, controller in loaded do
	if typeof(controller.start) == "function" then
		run(name, "start", controller.start)
	end
end

print("[Grow a Galaxy] client started")
-- Tells the loading screen (ReplicatedFirst) it can fade out.
game:GetService("Players").LocalPlayer:SetAttribute("GaG_ClientReady", true)
