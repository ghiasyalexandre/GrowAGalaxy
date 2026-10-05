--!strict
-- Every tunable gameplay value, grouped by topic. Replicated to clients, so
-- nothing secret belongs here, and the server never trusts a value a client
-- sends back. Logic/ConfigCheck validates these tables when the server starts.

return {
	World = require(script.World),
	Movement = require(script.Movement),
	Beam = require(script.Beam),
	Combat = require(script.Combat),
	Daily = require(script.Daily),
	Raids = require(script.Raids),
	Asteroids = require(script.Asteroids),
	Materials = require(script.Materials),
	Zones = require(script.Zones),
	Ships = require(script.Ships),
	Equipment = require(script.Equipment),
	Recipes = require(script.Recipes),
	Stars = require(script.Stars),
	Planets = require(script.Planets),
	Celestials = require(script.Celestials),
	SolarSystems = require(script.SolarSystems),
	Galaxy = require(script.Galaxy),
	Hangar = require(script.Hangar),
	Paint = require(script.Paint),
	Economy = require(script.Economy),
	Cosmetics = require(script.Cosmetics),
	Achievements = require(script.Achievements),
	Tutorial = require(script.Tutorial),
	Products = require(script.Products),
	Sprites = require(script.Sprites),
}
