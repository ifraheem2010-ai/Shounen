--!strict
--[[
	The seeded generator every roll in the engine flows through.

	ABSOLUTE RULE #1 LIVES HERE. There is no `math.random` in this file and there must
	never be one anywhere under src/shared/Battle/. A battle is a long chain of
	probabilistic events; without a seeded, injected generator a bug that shows up one
	time in forty is effectively unfixable, because you cannot reproduce it, cannot
	write a regression test for it, and cannot prove you fixed it. With one, a bug
	report is a seed plus a list of intents and it replays in milliseconds anywhere.

	ALGORITHM: mulberry32.

	The choice is forced by an existing contract, not by preference. `Types/Rng.luau`
	declares `getState(): number` and `Types/BattleState.luau` stores `rngState:
	number` — a single number, so the generator gets 32 bits of state and no more.
	Within that budget mulberry32 is the strongest well-specified option: it has a
	full 2^32 period and passes PractRand out to that bound, which is far beyond the
	few hundred draws a battle consumes. xorshift32 would also fit but has known
	linear structure in its low bits, which is exactly where small ranges like a
	damage roll read from.

	If 32 bits ever stops being enough — it will not, for a turn-based game — the
	upgrade is a wider state, and that means changing `Rng.getState` and
	`BattleState.rngState` to carry a state table. Both live in `src/shared/Types/`,
	which is data-architect's, so that is their call and not one to make from here.

	ARITHMETIC: Luau numbers are doubles, so there is no native 32-bit multiply.
	mul32 below splits the left operand into 16-bit halves; every intermediate stays
	under 2^53 and is therefore exact. This reproduces `Math.imul` bit for bit, which
	is what lets the test suite assert against an independent reference implementation
	rather than against itself.
]]

local RngContract = require(script.Parent.Parent.Types.Rng)

export type RNG = {
	-- The raw primitive. Everything else is derived from it, and it is the level the
	-- tests assert against because it is the only one with an external reference.
	nextUInt32: (self: RNG) -> number,
	nextNumber: (self: RNG) -> number,
	nextInteger: (self: RNG, min: number, max: number) -> number,
	nextBoolean: (self: RNG, probability: number) -> boolean,
	pick: <T>(self: RNG, options: { T }) -> T,
	fork: (self: RNG) -> RNG,
	getState: (self: RNG) -> number,
}

local TWO_POW_32 = 4294967296
local TWO_POW_16 = 65536
-- The mulberry32 Weyl increment, 0x6D2B79F5.
local INCREMENT = 1831565813

--[[ 32-bit arithmetic ------------------------------------------------------ ]]

-- Accepts any number and folds it into [0, 2^32). Negative seeds wrap rather than
-- explode, and a fractional seed truncates, so a caller cannot produce a generator
-- in an invalid state by passing something careless.
local function toUInt32(value: number): number
	return math.floor(value) % TWO_POW_32
end

-- (a * b) mod 2^32, computed exactly. Equivalent to JavaScript's Math.imul.
local function mul32(a: number, b: number): number
	local low = a % TWO_POW_16
	local high = (a - low) / TWO_POW_16
	-- low * b peaks at 65535 * 4294967295, about 2.8e14, well inside the 2^53 the
	-- mantissa represents exactly. Nothing here rounds.
	return (low * b + ((high * b) % TWO_POW_16) * TWO_POW_16) % TWO_POW_32
end

--[[ The generator ---------------------------------------------------------- ]]

local function create(initialState: number): RNG
	local state = toUInt32(initialState)

	local function nextUInt32(): number
		state = (state + INCREMENT) % TWO_POW_32

		local t = state
		t = mul32(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(1, t))
		t = bit32.bxor(
			(t + mul32(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(61, t))) % TWO_POW_32,
			t
		)
		return bit32.bxor(t, bit32.rshift(t, 14))
	end

	local function nextNumber(): number
		return nextUInt32() / TWO_POW_32
	end

	local function nextInteger(min: number, max: number): number
		if min % 1 ~= 0 or max % 1 ~= 0 then
			error(`RNG.nextInteger: bounds must be integer, got {min} and {max}`)
		end
		if min > max then
			error(`RNG.nextInteger: min must be <= max, got {min} and {max}`)
		end
		-- nextNumber is strictly below 1, so this can never reach max + 1.
		--
		-- There is a modulo bias here in principle. In practice every range the engine
		-- uses is a power of two (the damage roll is 16 wide, party slots are 6) or so
		-- small against 2^32 that the bias is unmeasurable — for a 16-wide range it is
		-- exactly zero, since 2^32 divides evenly.
		return min + math.floor(nextNumber() * (max - min + 1))
	end

	local function nextBoolean(probability: number): boolean
		if probability < 0 or probability > 1 then
			error(`RNG.nextBoolean: probability must be within [0, 1], got {probability}`)
		end
		-- Always consumes a draw, including at 0 and 1. A generator whose stream
		-- depends on the *value* of a probability would desync the moment a balance
		-- change made some effect certain.
		return nextNumber() < probability
	end

	local function pick<T>(options: { T }): T
		local count = #options
		if count == 0 then
			error("RNG.pick: cannot pick from an empty list")
		end
		return options[nextInteger(1, count)]
	end

	return {
		nextUInt32 = function(_self: RNG): number
			return nextUInt32()
		end,
		nextNumber = function(_self: RNG): number
			return nextNumber()
		end,
		nextInteger = function(_self: RNG, min: number, max: number): number
			return nextInteger(min, max)
		end,
		nextBoolean = function(_self: RNG, probability: number): boolean
			return nextBoolean(probability)
		end,
		pick = function<T>(_self: RNG, options: { T }): T
			return pick(options)
		end,
		-- A copy at the current state. Rolling on the fork cannot touch the parent's
		-- stream, which is the point: speculative work — AI lookahead, a damage-range
		-- preview — must not change what actually happens in the battle.
		fork = function(_self: RNG): RNG
			return create(state)
		end,
		getState = function(_self: RNG): number
			return state
		end,
	}
end

--[[
	Compile-time proof that RNG satisfies the engine-facing contract in
	Types/Rng.luau. If that interface drifts, this stops type-checking — which is a
	much better failure than discovering the mismatch at the first call site.
]]
local function _satisfiesContract(rng: RNG): RngContract.Rng
	return rng
end

return {
	new = create,
	-- Rebuilds a generator mid-stream from a persisted BattleState.rngState.
	restore = create,
	_satisfiesContract = _satisfiesContract,
}
