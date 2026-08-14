--!strict
--[[
	RNG tests.

	The expected values in this file were NOT produced by the implementation under
	test. They come from an independent mulberry32 reference run in Node, which is
	the only way an assertion about a PRNG stream means anything — a test that asks
	the generator what it produces and then asserts it produces that will pass no
	matter how broken the generator is.

	Determinism is the load-bearing property. Everything else in the engine is a pure
	function of state; this is the one place entropy enters, so if the stream is not
	reproducible then no battle is reproducible and no bug report is actionable.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local RNG = require(Shared.Battle.RNG)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

-- Independent mulberry32 reference, seed -> first 8 raw uint32 draws.
local REFERENCE_STREAMS: { [number]: { number } } = {
	[0] = {
		1144304738,
		1416247,
		958946056,
		627933444,
		2007157716,
		2340967985,
		2642484575,
		2787370982,
	},
	[1] = {
		2693262067,
		11749833,
		2265367787,
		4213581821,
		4159151403,
		1207330352,
		2632122864,
		3095568220,
	},
	[12345] = {
		4207900869,
		1317490944,
		2079646450,
		3513001552,
		2187978186,
		1492380277,
		316786230,
		3291647763,
	},
	[2147483647] = {
		1842962257,
		546041740,
		1654754255,
		1702490205,
		513796057,
		4093909556,
		2923511389,
		4276844688,
	},
	[4294967295] = {
		3850105811,
		813802916,
		3073704848,
		4054706436,
		3630262831,
		2315588663,
		2922715533,
		2042566601,
	},
}

local REFERENCE_SEEDS = { 0, 1, 12345, 2147483647, 4294967295 }

describe("RNG / reference stream", function()
	for _, seed in REFERENCE_SEEDS do
		it(`matches the independent reference for seed {seed}`, function()
			local rng = RNG.new(seed)
			local expected = REFERENCE_STREAMS[seed]
			for index, expectedValue in expected do
				local actual = rng:nextUInt32()
				if actual ~= expectedValue then
					fail(
						`seed {seed}, draw {index}: expected {expectedValue}, got {actual}`
							.. ` — the generator has diverged from mulberry32`
					)
				end
			end
		end)
	end

	it("produces uint32 values in range across many draws", function()
		local rng = RNG.new(2024)
		for _ = 1, 5000 do
			local value = rng:nextUInt32()
			expect(value).toBeGreaterThanOrEqual(0)
			expect(value).toBeLessThanOrEqual(4294967295)
			expect(value % 1).toBe(0)
		end
	end)
end)

describe("RNG / determinism", function()
	it("gives two generators on the same seed identical streams", function()
		local a = RNG.new(12345)
		local b = RNG.new(12345)
		for draw = 1, 200 do
			local left, right = a:nextUInt32(), b:nextUInt32()
			if left ~= right then
				fail(`diverged at draw {draw}: {left} vs {right}`)
			end
		end
	end)

	it("gives different seeds different streams", function()
		local a = RNG.new(1)
		local b = RNG.new(2)
		local identical = true
		for _ = 1, 20 do
			if a:nextUInt32() ~= b:nextUInt32() then
				identical = false
				break
			end
		end
		expect(identical).toBe(false)
	end)

	it("advances state to the reference value after N draws", function()
		-- Reference: seed 12345 state after 0/1/2/5/10 draws.
		local checkpoints = { [0] = 12345, [1] = 1831578158, [2] = 3663143971, [5] = 567906818 }
		for _, draws in { 0, 1, 2, 5 } do
			local rng = RNG.new(12345)
			for _ = 1, draws do
				rng:nextUInt32()
			end
			expect(rng:getState()).toBe(checkpoints[draws])
		end
	end)

	it("keeps state a 32-bit unsigned integer", function()
		local rng = RNG.new(4294967295)
		for _ = 1, 500 do
			rng:nextUInt32()
			local state = rng:getState()
			expect(state % 1).toBe(0)
			expect(state).toBeGreaterThanOrEqual(0)
			expect(state).toBeLessThanOrEqual(4294967295)
		end
	end)

	--[[
		This is the property BattleState.rngState exists for: a battle is saved as a
		number, reloaded, and must continue the identical stream.
	]]
	it("resumes the identical stream from a restored state", function()
		local original = RNG.new(777)
		for _ = 1, 37 do
			original:nextUInt32()
		end

		local resumed = RNG.restore(original:getState())
		for draw = 1, 50 do
			local left, right = original:nextUInt32(), resumed:nextUInt32()
			if left ~= right then
				fail(`restored stream diverged at draw {draw}: {left} vs {right}`)
			end
		end
	end)

	it("normalises a seed outside the 32-bit range instead of breaking", function()
		expect(RNG.new(4294967296):getState()).toBe(0)
		expect(RNG.new(-1):getState()).toBe(4294967295)
		expect(RNG.new(12345.9):getState()).toBe(12345)
	end)
end)

describe("RNG / nextNumber", function()
	it("matches the reference floats for seed 12345", function()
		local rng = RNG.new(12345)
		local expected =
			{ 0.9797282677609473, 0.3067522644996643, 0.484205421525985, 0.817934412509203 }
		for index, expectedValue in expected do
			expect(rng:nextNumber()).toBeCloseTo(expectedValue, 1e-12)
		end
	end)

	it("stays within [0, 1)", function()
		local rng = RNG.new(31337)
		for _ = 1, 5000 do
			local value = rng:nextNumber()
			expect(value).toBeGreaterThanOrEqual(0)
			expect(value).toBeLessThan(1)
		end
	end)
end)

describe("RNG / nextInteger", function()
	it("matches the reference for nextInteger(1, 6) on seed 7", function()
		local rng = RNG.new(7)
		local expected = { 1, 1, 6, 5, 4, 3, 3, 2, 4, 5, 2, 1, 5, 4, 2, 3, 2, 4, 2, 6 }
		for index, expectedValue in expected do
			local actual = rng:nextInteger(1, 6)
			if actual ~= expectedValue then
				fail(`draw {index}: expected {expectedValue}, got {actual}`)
			end
		end
	end)

	it("respects inclusive bounds", function()
		local rng = RNG.new(4242)
		local sawMin, sawMax = false, false
		for _ = 1, 2000 do
			local value = rng:nextInteger(3, 9)
			expect(value).toBeGreaterThanOrEqual(3)
			expect(value).toBeLessThanOrEqual(9)
			expect(value % 1).toBe(0)
			if value == 3 then
				sawMin = true
			elseif value == 9 then
				sawMax = true
			end
		end
		-- Inclusive means both endpoints are reachable; an off-by-one at either end is
		-- the classic bug here and it hides for a long time.
		expect(sawMin).toBe(true)
		expect(sawMax).toBe(true)
	end)

	it("returns the only option when min equals max", function()
		local rng = RNG.new(5)
		for _ = 1, 20 do
			expect(rng:nextInteger(4, 4)).toBe(4)
		end
	end)

	it("handles negative ranges", function()
		local rng = RNG.new(6)
		for _ = 1, 200 do
			local value = rng:nextInteger(-6, -1)
			expect(value).toBeGreaterThanOrEqual(-6)
			expect(value).toBeLessThanOrEqual(-1)
		end
	end)

	it("rejects an inverted range", function()
		local rng = RNG.new(1)
		expect(function()
			rng:nextInteger(9, 3)
		end).toThrow("min must be <= max")
	end)

	it("rejects non-integer bounds", function()
		local rng = RNG.new(1)
		expect(function()
			rng:nextInteger(1.5, 6)
		end).toThrow("integer")
	end)

	it("distributes uniformly over a small range", function()
		local rng = RNG.new(99)
		local counts: { [number]: number } = {}
		local samples = 160000
		for _ = 1, samples do
			local value = rng:nextInteger(85, 100)
			counts[value] = (counts[value] or 0) + 1
		end

		local distinct = 0
		for value = 85, 100 do
			local count = counts[value] or 0
			distinct += 1
			-- Expected 10000 each. A 5% band is loose enough never to flake on a fixed
			-- seed and tight enough to catch a genuinely skewed generator.
			if count < 9500 or count > 10500 then
				fail(`value {value} appeared {count} times, expected about 10000`)
			end
		end
		expect(distinct).toBe(16)
	end)
end)

describe("RNG / nextBoolean", function()
	it("is always true at probability 1 and always false at 0", function()
		local rng = RNG.new(11)
		for _ = 1, 200 do
			expect(rng:nextBoolean(1)).toBe(true)
		end
		for _ = 1, 200 do
			expect(rng:nextBoolean(0)).toBe(false)
		end
	end)

	it("lands near the requested probability", function()
		local rng = RNG.new(1234)
		local hits = 0
		for _ = 1, 40000 do
			if rng:nextBoolean(0.25) then
				hits += 1
			end
		end
		expect(hits).toBeGreaterThan(9500)
		expect(hits).toBeLessThan(10500)
	end)

	it("rejects a probability outside [0, 1]", function()
		local rng = RNG.new(1)
		expect(function()
			rng:nextBoolean(1.5)
		end).toThrow("probability")
		expect(function()
			rng:nextBoolean(-0.1)
		end).toThrow("probability")
	end)
end)

describe("RNG / pick", function()
	it("only ever returns a member of the list", function()
		local rng = RNG.new(2)
		local options = { "a", "b", "c", "d" }
		for _ = 1, 500 do
			expect(options).toContain(rng:pick(options))
		end
	end)

	it("reaches every option", function()
		local rng = RNG.new(3)
		local seen: { [string]: boolean } = {}
		local options = { "a", "b", "c", "d" }
		for _ = 1, 500 do
			seen[rng:pick(options)] = true
		end
		for _, option in options do
			expect(seen[option]).toBe(true)
		end
	end)

	it("returns the only element of a single-item list", function()
		local rng = RNG.new(4)
		expect(rng:pick({ "only" })).toBe("only")
	end)

	it("rejects an empty list", function()
		local rng = RNG.new(1)
		expect(function()
			rng:pick({})
		end).toThrow("empty")
	end)
end)

describe("RNG / fork", function()
	--[[
		fork() exists so speculative work — AI lookahead, a damage-range preview —
		can roll dice without consuming the real battle's stream. If it disturbed the
		parent, merely *thinking* about a move would change what happens.
	]]
	it("produces the same stream the parent would have produced", function()
		local parent = RNG.new(555)
		for _ = 1, 10 do
			parent:nextUInt32()
		end

		local forked = parent:fork()
		local expected = {}
		local probe = RNG.restore(parent:getState())
		for _ = 1, 20 do
			table.insert(expected, probe:nextUInt32())
		end
		for index, expectedValue in expected do
			local actual = forked:nextUInt32()
			if actual ~= expectedValue then
				fail(`fork diverged at draw {index}: expected {expectedValue}, got {actual}`)
			end
		end
	end)

	it("does not advance the parent", function()
		local parent = RNG.new(555)
		for _ = 1, 10 do
			parent:nextUInt32()
		end
		local stateBefore = parent:getState()

		local forked = parent:fork()
		for _ = 1, 100 do
			forked:nextUInt32()
		end

		expect(parent:getState()).toBe(stateBefore)
	end)
end)

describe("RNG / contract", function()
	it("implements every method the engine-facing Rng type declares", function()
		local rng = RNG.new(1)
		for _, method in { "nextInteger", "nextNumber", "nextBoolean", "pick", "fork", "getState" } do
			if type((rng :: any)[method]) ~= "function" then
				fail(`RNG is missing the "{method}" method required by Types/Rng.luau`)
			end
		end
	end)
end)
