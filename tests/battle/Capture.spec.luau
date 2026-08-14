--!strict
--[[
	Capture tests.

	The `a` and `b` values below came from an independent implementation of the Gen-5
	formula run in Node, not from this module. A capture test that asks the module what
	it computes and then asserts it computes that would pass with the exponent upside
	down.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local Capture = require(Shared.Battle.Capture)
local RNG = require(Shared.Battle.RNG)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

local function input(overrides: { [string]: any }?): any
	local o: any = overrides or {}
	return {
		maxHp = o.maxHp or 200,
		currentHp = o.currentHp or 200,
		catchRate = o.catchRate or 45,
		ballMultiplier = o.ballMultiplier or 1,
		status = o.status,
		guaranteed = o.guaranteed,
	}
end

--[[
	Reference table, external to this module.
	  { label, maxHp, currentHp, catchRate, ball, status, expected a, expected b }
]]
local REFERENCE = {
	{ "full HP, rate 45", 200, 200, 45, 1, nil, 15, 38527 },
	{ "1 HP, rate 45", 200, 1, 45, 1, nil, 44, 47141 },
	{ "1 HP, rate 45, asleep", 200, 1, 45, 1, "Sleep", 89, 53797 },
	{ "1 HP, rate 45, paralysed", 200, 1, 45, 1, "Paralysis", 67, 51008 },
	{ "half HP, rate 45, 1.5x ball", 200, 100, 45, 1.5, nil, 45, 47340 },
	{ "full HP, rate 255", 200, 200, 255, 1, nil, 85, 53335 },
	{ "1 HP, rate 255", 200, 1, 255, 1, nil, 254, 65487 },
	{ "1 HP, rate 3", 200, 1, 3, 1, nil, 2, 26405 },
	{ "1 HP, rate 3, 4x ball, asleep", 200, 1, 3, 4, "Sleep", 23, 41742 },
}

describe("Capture / against the external reference", function()
	for _, entry in REFERENCE do
		local label = entry[1] :: string
		it(`matches the reference for {label}`, function()
			local built = input({
				maxHp = entry[2],
				currentHp = entry[3],
				catchRate = entry[4],
				ballMultiplier = entry[5],
				status = entry[6],
			})
			local rate = Capture.modifiedCatchRate(built)
			if rate ~= entry[7] then
				fail(`{label}: expected a = {entry[7]}, got {rate}`)
			end
			local threshold = Capture.shakeThreshold(rate)
			if threshold ~= entry[8] then
				fail(`{label}: expected b = {entry[8]}, got {threshold}`)
			end
		end)
	end
end)

describe("Capture / the shape of the formula", function()
	--[[
		The numerator is 3*maxHp - 2*currentHp, so chipping the target is worth far
		more than it looks. This is the single most important property for a player to
		feel, and the one a wrong sign would quietly invert.
	]]
	it("roughly triples the rate between full HP and 1 HP", function()
		local atFull = Capture.modifiedCatchRate(input({ currentHp = 200 }))
		local atOne = Capture.modifiedCatchRate(input({ currentHp = 1 }))
		expect(atOne).toBeGreaterThan(atFull * 2.5)
		expect(atOne).toBeLessThan(atFull * 3.5)
	end)

	it("rises monotonically as HP falls", function()
		local previous = -1
		for hp = 200, 1, -1 do
			local rate = Capture.modifiedCatchRate(input({ currentHp = hp }))
			if rate < previous then
				fail(`rate fell from {previous} to {rate} at {hp} HP`)
			end
			previous = rate
		end
	end)

	it("doubles for sleep and freeze, and adds half for the rest", function()
		expect(Capture.statusBonus("Sleep")).toBe(2)
		expect(Capture.statusBonus("Freeze")).toBe(2)
		expect(Capture.statusBonus("Paralysis")).toBe(1.5)
		expect(Capture.statusBonus("Burn")).toBe(1.5)
		expect(Capture.statusBonus("Poison")).toBe(1.5)
		expect(Capture.statusBonus(nil)).toBe(1)
	end)

	it("scales with the ball", function()
		local plain = Capture.modifiedCatchRate(input({ currentHp = 1 }))
		local better = Capture.modifiedCatchRate(input({ currentHp = 1, ballMultiplier = 2 }))
		expect(better).toBeGreaterThan(plain)
	end)

	it("rejects a fainted or impossible target", function()
		expect(function()
			Capture.modifiedCatchRate(input({ currentHp = 0 }))
		end).toThrow("fainted")
		expect(function()
			Capture.modifiedCatchRate(input({ maxHp = 0, currentHp = 0 }))
		end).toThrow("maxHp")
	end)
end)

describe("Capture / attempts", function()
	it("catches without rolling when the rate reaches 255", function()
		local rng = RNG.new(5)
		local probe = RNG.new(5)
		local result =
			Capture.attempt(input({ currentHp = 1, catchRate = 255, ballMultiplier = 2 }), rng)
		expect(result.captured).toBe(true)
		expect(result.guaranteed).toBe(true)
		expect(result.shakes).toBe(4)
		-- No rolls means the battle's RNG stream is untouched.
		expect(rng:getState()).toBe(probe:getState())
	end)

	it("catches without rolling when the ball says so", function()
		local result = Capture.attempt(input({ guaranteed = true, catchRate = 3 }), RNG.new(1))
		expect(result.captured).toBe(true)
		expect(result.guaranteed).toBe(true)
	end)

	--[[
		Always four draws, even after a shake has failed. Consuming a variable number
		would shift every later roll in the battle depending on when the ball broke.
	]]
	it("always consumes exactly four draws", function()
		for _, catchRate in { 3, 45, 200 } do
			local rng = RNG.new(77)
			local probe = RNG.new(77)
			Capture.attempt(input({ catchRate = catchRate }), rng)
			for _ = 1, 4 do
				probe:nextUInt32()
			end
			expect(rng:getState()).toBe(probe:getState())
		end
	end)

	it("reports shakes between 0 and 4", function()
		local rng = RNG.new(2024)
		for _ = 1, 500 do
			local result = Capture.attempt(input({ currentHp = 60 }), rng)
			expect(result.shakes).toBeGreaterThanOrEqual(0)
			expect(result.shakes).toBeLessThanOrEqual(4)
			expect(result.captured).toBe(result.shakes == 4)
		end
	end)

	it("is reproducible from a seed", function()
		local first, second = {}, {}
		local a, b = RNG.new(31337), RNG.new(31337)
		for _ = 1, 200 do
			table.insert(first, Capture.attempt(input({ currentHp = 60 }), a).shakes)
			table.insert(second, Capture.attempt(input({ currentHp = 60 }), b).shakes)
		end
		expect(first).toEqual(second)
	end)

	--[[
		The observed catch rate has to land near the fourth power of the per-shake
		probability. This is the test that would catch an exponent applied once instead
		of four times, which no single-attempt assertion can see.
	]]
	it("converges on the predicted catch probability", function()
		local built = input({ currentHp = 1 })
		local rate = Capture.modifiedCatchRate(built)
		local predicted = (Capture.shakeThreshold(rate) / Capture.SHAKE_RANGE) ^ 4

		local rng = RNG.new(4242)
		local caught = 0
		local samples = 20000
		for _ = 1, samples do
			if Capture.attempt(built, rng).captured then
				caught += 1
			end
		end

		local observed = caught / samples
		if math.abs(observed - predicted) > 0.02 then
			fail(`observed {observed} against predicted {predicted}`)
		end
	end)

	it("makes a legendary genuinely hard even at 1 HP", function()
		local built = input({ currentHp = 1, catchRate = 3 })
		local rng = RNG.new(99)
		local caught = 0
		for _ = 1, 4000 do
			if Capture.attempt(built, rng).captured then
				caught += 1
			end
		end
		-- Reference puts this near 2.6%.
		expect(caught / 4000).toBeLessThan(0.05)
		expect(caught).toBeGreaterThan(0)
	end)
end)
