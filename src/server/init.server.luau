--!strict
-- Server entry point. Validates config, then runs a two-phase bootstrap over
-- every ModuleScript in Systems: init() on all of them (create instances),
-- then start() on all of them (connect events). Neither phase may yield, so
-- every system is listening before any player's data starts loading.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ConfigCheck = require(ReplicatedStorage.Shared.Logic.ConfigCheck)

for _, problem in ConfigCheck.run(Config) do
	warn(`[Config] {problem}`)
end

local Systems = script:WaitForChild("Systems")

local loaded: { [string]: any } = {}
for _, child in Systems:GetChildren() do
	if child:IsA("ModuleScript") then
		loaded[child.Name] = require(child) :: any
	end
end

for _, system in loaded do
	if typeof(system.init) == "function" then
		system.init()
	end
end

for _, system in loaded do
	if typeof(system.start) == "function" then
		system.start()
	end
end

print("[Grow a Galaxy] server started")
