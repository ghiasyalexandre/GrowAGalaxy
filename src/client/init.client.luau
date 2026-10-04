--!strict
-- Client entry point. Same two-phase bootstrap as the server: init() every
-- controller (build UI, connect events), load the starting state from the
-- server, then start() every controller. The shared input layer starts first.

local ClientState = require(script.ClientState)
local Input = require(script.Input)

Input.init()

local Controllers = script.Controllers

local loaded: { [string]: any } = {}
for _, child in Controllers:GetChildren() do
	if child:IsA("ModuleScript") then
		loaded[child.Name] = require(child) :: any
	end
end

for _, controller in loaded do
	if typeof(controller.init) == "function" then
		controller.init()
	end
end

ClientState.load()

for _, controller in loaded do
	if typeof(controller.start) == "function" then
		controller.start()
	end
end

print("[Grow a Galaxy] client started")
