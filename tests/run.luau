-- Runs the pure-logic unit tests outside Roblox Studio.
-- Usage, from the repository root: lune run tests/run

local process = require("@lune/process")

local TestKit = require("./TestKit")
local Loader = require("./Loader")

local SPECS = {
	"ConfigCheck",
	"RegionMath",
	"PlacementRules",
	"ProfileSchema",
	"FlightMath",
	"BeamMath",
	"ShipStats",
	"AsteroidField",
	"MiningMath",
	"StarMath",
	"OrbitTime",
	"Progression",
}

for _, name in SPECS do
	print(`{name}`)
	local spec = require(`./specs/{name}`)
	spec(TestKit, Loader)
end

print(`\n{TestKit.passed} passed, {TestKit.failed} failed`)
if TestKit.failed > 0 then
	process.exit(1)
end
