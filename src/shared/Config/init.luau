--!strict
-- Every tunable gameplay value, grouped by topic. Replicated to clients, so
-- nothing secret belongs here, and the server never trusts a value a client
-- sends back. Logic/ConfigCheck validates these tables when the server starts.

return {
	World = require(script.World),
	Materials = require(script.Materials),
	Zones = require(script.Zones),
	Ships = require(script.Ships),
	Equipment = require(script.Equipment),
	Recipes = require(script.Recipes),
	Celestials = require(script.Celestials),
	SolarSystems = require(script.SolarSystems),
	Galaxy = require(script.Galaxy),
	Economy = require(script.Economy),
	Cosmetics = require(script.Cosmetics),
	Achievements = require(script.Achievements),
	Products = require(script.Products),
}
