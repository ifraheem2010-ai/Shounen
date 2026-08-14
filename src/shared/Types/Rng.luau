--!strict
--[[
	The injected random number generator.

	This interface is the whole reason Absolute Rule #1 is enforceable. The battle
	engine never calls `math.random` — it takes an Rng and asks it for numbers. That
	single indirection is what makes a battle reproducible from a seed, which in turn
	is what makes a 6v6 battle testable in milliseconds instead of by hand in Studio.

	Every roll in a battle goes through here: accuracy, criticals, damage variance,
	secondary effect chances, multi-hit counts, phazing targets, capture shakes.
	If you find yourself wanting "just one" ungated random value, that battle stops
	being reproducible and the bug you are chasing stops being reproducible with it.

	The implementation lives in src/shared/Battle/ and is owned by battle-engineer.
]]

export type Rng = {
	-- Uniform integer in [min, max], inclusive.
	nextInteger: (self: Rng, min: number, max: number) -> number,
	-- Uniform float in [0, 1).
	nextNumber: (self: Rng) -> number,
	-- True with the given probability, expressed as 0..1.
	nextBoolean: (self: Rng, probability: number) -> boolean,
	-- Uniform choice from a non-empty array.
	pick: <T>(self: Rng, options: { T }) -> T,
	-- An independent generator at the current state, for speculative rollouts that
	-- must not disturb the real battle's stream.
	fork: (self: Rng) -> Rng,
	-- Opaque state, enough to reconstruct this generator exactly.
	getState: (self: Rng) -> number,
}

return {}
