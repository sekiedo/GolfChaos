--!strict
-- Messages sent by BallService (English). Keys: golf.aimCancelled.*, golf.reset.*, golf.lipOut, golf.ball.*, golf.penalty.*
return {
	["golf.aimCancelled.stun"] = "You're stunned: aim cancelled.",
	["golf.aimCancelled.horn"] = "The horn made you shoot!",
	["golf.aimCancelled.too_far"] = "You're too far from your ball.",
	["golf.aimCancelled.invalid"] = "Invalid shot, try again.",
	["golf.aimCancelled.unavailable"] = "You can't hit right now.",
	["golf.aimCancelled.respawn"] = "Aim cancelled: you respawned.",
	["golf.aimCancelled.phase"] = "It's not time to hit yet.",
	["golf.aimCancelled.no_target"] = "No target for the guided shot.",
	["golf.aimCancelled.ball_moving"] = "Your ball is still rolling.",
	["golf.aimCancelled.ball_frozen"] = "Your ball is frozen!",
	["golf.aimCancelled.finished"] = "Hole finished!",
	["golf.aimCancelled.vehicle"] = "You can't aim from the kart.",
	["golf.aimCancelled.status"] = "An effect stops you from aiming.",
	["golf.aimCancelled.blocked"] = "Aiming is blocked for a moment.",
	["golf.aimCancelled.cooldown"] = "Not so fast!",
	["golf.aimCancelled.putt_not_allowed"] = "No putt from here: get closer to the green.",
	["golf.aimCancelled.guided_cooldown"] = "Guided shot is recharging.",

	["golf.reset.water"] = "Splash! Your ball is in the water.",
	["golf.reset.oob"] = "Out of bounds: ball replaced.",
	["golf.reset.lava"] = "Too hot! Ball replaced.",
	["golf.reset.void"] = "Ball fell into the void: replaced.",
	["golf.reset.stuck"] = "Ball stuck: replaced.",
	["golf.reset.refused"] = "You can't reset your ball right now.",
	["golf.reset.generic"] = "Ball replaced.",

	["golf.lipOut"] = "So close! The ball lipped out.",
	["golf.ball.frozen"] = "Ball frozen for {n} s",
	["golf.penalty.added"] = "+{n} penalty stroke(s)",
}
