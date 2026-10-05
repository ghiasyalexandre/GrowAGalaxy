--!strict
-- Spacesuit and ship handling, docking and movement validation. Ship stats
-- themselves live in Config.Ships; these are the rules shared by every ship.

local Movement = {
	-- Spacesuit (zero gravity). Slower than any ship.
	SUIT_MAX_SPEED = 24, -- studs per second
	SUIT_ACCELERATION = 30, -- studs per second squared while thrusting
	SUIT_BRAKING = 70, -- when the brake is held
	SUIT_STABILIZE_DRAG = 25, -- slowdown with no input while stabilization is on

	-- Ships: share of max speed available in other directions.
	SHIP_REVERSE_FACTOR = 0.3,
	SHIP_STRAFE_FACTOR = 0.45,
	-- With no throttle input a ship slows down at this share of its braking.
	SHIP_IDLE_BRAKE_FACTOR = 0.35,
	SHIP_MAX_PITCH_DEGREES = 80,

	-- Ship feel. Visual only: speed and turn rate still come from the ship's
	-- stats. The nose eases onto the aim (higher TURN_RESPONSE is snappier,
	-- never faster than the ship's turn rate), and the hull banks into turns
	-- and strafes.
	SHIP_TURN_RESPONSE = 5,
	SHIP_MAX_BANK_DEGREES = 35,
	SHIP_BANK_PER_TURN = 0.45, -- radians of bank per radian/second of turning
	SHIP_STRAFE_BANK_DEGREES = 15, -- bank at full strafe
	SHIP_BANK_SMOOTHING = 5,

	-- Spacesuit body: leans into the direction of travel while floating.
	SUIT_LEAN_DEGREES = 50, -- forward lean at full speed
	SUIT_ROLL_DEGREES = 15, -- sideways tilt at full sideways speed
	SUIT_LEAN_SMOOTHING = 5,

	-- Chase camera
	CAMERA_HEIGHT = 7,
	CAMERA_DISTANCE = 26,
	CAMERA_SMOOTHING = 12, -- higher follows more tightly
	CAMERA_FOV = 70,
	-- Over-the-shoulder view (tap Alt or D-pad right): the camera slides
	-- this many studs to the right, easing in at SHOULDER_SMOOTHING.
	CAMERA_SHOULDER_OFFSET = 8, -- ship chase camera
	SUIT_SHOULDER_OFFSET = 2.5, -- spacesuit camera
	SHOULDER_SMOOTHING = 8,
	-- Alt released within this many seconds is a tap (shoulder view);
	-- held longer, it frees the mouse cursor while flying.
	ALT_TAP_TIME = 0.3,
	CAMERA_FOV_BOOST = 15, -- extra field of view at top speed
	CAMERA_SPEED_PULLBACK = 6, -- extra studs behind the ship at top speed
	CAMERA_ROLL_SHARE = 0.3, -- share of the ship's bank the camera follows
	LOOK_SENSITIVITY_MOUSE = 0.0035, -- radians per pixel
	LOOK_SENSITIVITY_TOUCH = 0.006,
	LOOK_SPEED_GAMEPAD = 2.4, -- radians per second at full stick

	-- Boost (per-ship amounts in Config.Ships). Acceleration is multiplied
	-- while boosting so the surge is felt at once. An emptied tank can only
	-- boost again once it has refilled to BOOST_RESTART_SHARE.
	BOOST_ACCEL_FACTOR = 3,
	BOOST_RESTART_SHARE = 0.25,
	CAMERA_BOOST_FOV = 14, -- extra field of view while boosting
	CAMERA_BOOST_PULLBACK = 5, -- extra studs behind the ship while boosting
	CAMERA_BOOST_SHAKE = 0.35, -- studs of camera shake while boosting

	-- Assisted docking: inside a docking zone and slower than this.
	DOCK_MAX_SPEED = 25,

	-- Interactions
	LAUNCH_COOLDOWN = 3, -- seconds between ship launches per player
	RECOVER_COOLDOWN = 15, -- seconds between Return to Station uses
	BOARD_DISTANCE = 16,
	-- When every ISS berth is taken, a ship parked there this long without its
	-- pilot is stowed to make room. Its owner can launch it again.
	BERTH_IDLE_STOW = 30,

	-- Flight area: a cylinder around the ISS. Controllers stop thrusting
	-- outwards at the edge, and the flight guard moves anyone well past it
	-- back inside. Must contain every region and stay above the Earth.
	FLIGHT_BOUNDS_RADIUS = 6000,
	FLIGHT_BOUNDS_HEIGHT = 1500, -- studs above and below the ISS

	-- Server movement check: a sample fails when the player moved further than
	-- maxSpeed x elapsed x TOLERANCE + SLACK studs. FLIGHT_GUARD_STRIKES
	-- failures in a row send them back to their last good position.
	FLIGHT_GUARD_INTERVAL = 0.5,
	FLIGHT_GUARD_TOLERANCE = 1.5,
	FLIGHT_GUARD_SLACK = 12,
	FLIGHT_GUARD_STRIKES = 2,
}

return Movement
