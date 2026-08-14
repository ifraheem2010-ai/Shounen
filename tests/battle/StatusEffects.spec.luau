--!strict
--[[
	Non-volatile status tests.

	One status at a time, and it survives switching — that is what makes these
	different from volatiles, and why a second status must be refused rather than
	silently overwriting the first.

	Every roll goes through the injected RNG, so which statuses consume a draw and
	which do not is itself asserted: a status that quietly took an extra draw would
	desync the whole battle stream from the turn it was inflicted.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local RNG = require(Shared.Battle.RNG)
local StatusEffects = require(Shared.Battle.StatusEffects)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

local ALL_STATUSES = { "Burn", "Poison", "Paralysis", "Sleep", "Freeze" }

describe("StatusEffects / application", function()
	it("accepts any status on a clear creature", function()
		for _, status in ALL_STATUSES do
			expect(StatusEffects.canApply(nil, status)).toBe(true)
		end
	end)

	it("refuses a second status", function()
		for _, existing in ALL_STATUSES do
			for _, incoming in ALL_STATUSES do
				if StatusEffects.canApply(existing, incoming) then
					fail(`allowed {incoming} on top of {existing}; only one status at a time`)
				end
			end
		end
	end)

	it("gives sleep a duration of 1 to 3 turns inclusive", function()
		local rng = RNG.new(4242)
		local seen: { [number]: boolean } = {}
		for _ = 1, 2000 do
			local turns = StatusEffects.initialDuration("Sleep", rng)
			if turns == nil then
				fail("sleep must carry a duration")
			end
			expect(turns).toBeGreaterThanOrEqual(1)
			expect(turns).toBeLessThanOrEqual(3)
			seen[turns] = true
		end
		expect(seen[1]).toBe(true)
		expect(seen[2]).toBe(true)
		expect(seen[3]).toBe(true)
	end)

	it("gives the other statuses no duration", function()
		local rng = RNG.new(1)
		for _, status in { "Burn", "Poison", "Paralysis", "Freeze" } do
			expect(StatusEffects.initialDuration(status, rng)).toBeNil()
		end
	end)

	it("only spends a draw on the status that needs one", function()
		local rng = RNG.new(9)
		local probe = RNG.new(9)
		for _, status in { "Burn", "Poison", "Paralysis", "Freeze" } do
			StatusEffects.initialDuration(status, rng)
		end
		expect(rng:getState()).toBe(probe:getState())

		StatusEffects.initialDuration("Sleep", rng)
		probe:nextUInt32()
		expect(rng:getState()).toBe(probe:getState())
	end)
end)

describe("StatusEffects / passive modifiers", function()
	it("halves physical damage under burn and nothing else", function()
		expect(StatusEffects.physicalDamageMultiplier("Burn")).toBe(0.5)
		for _, status in { "Poison", "Paralysis", "Sleep", "Freeze" } do
			expect(StatusEffects.physicalDamageMultiplier(status)).toBe(1)
		end
		expect(StatusEffects.physicalDamageMultiplier(nil)).toBe(1)
	end)

	--[[
		Gen 5 quarters speed under paralysis. This project uses a half instead — a
		deliberate, specified divergence. Changing it is one constant.
	]]
	it("cuts speed under paralysis and nothing else", function()
		expect(StatusEffects.speedMultiplier("Paralysis")).toBe(0.5)
		expect(StatusEffects.PARALYSIS_SPEED_MULTIPLIER).toBe(0.5)
		for _, status in { "Burn", "Poison", "Sleep", "Freeze" } do
			expect(StatusEffects.speedMultiplier(status)).toBe(1)
		end
		expect(StatusEffects.speedMultiplier(nil)).toBe(1)
	end)
end)

describe("StatusEffects / end of turn damage", function()
	it("chips an eighth of max HP for poison", function()
		expect(StatusEffects.endOfTurnDamage("Poison", 200)).toBe(25)
		expect(StatusEffects.endOfTurnDamage("Poison", 100)).toBe(12)
		expect(StatusEffects.endOfTurnDamage("Poison", 8)).toBe(1)
	end)

	it("chips an eighth of max HP for burn", function()
		expect(StatusEffects.endOfTurnDamage("Burn", 200)).toBe(25)
		expect(StatusEffects.endOfTurnDamage("Burn", 100)).toBe(12)
	end)

	it("always takes at least one point off", function()
		-- floor(7 / 8) is zero, and a status that does nothing is worse than no status.
		expect(StatusEffects.endOfTurnDamage("Poison", 7)).toBe(1)
		expect(StatusEffects.endOfTurnDamage("Poison", 1)).toBe(1)
	end)

	it("does nothing for the statuses that are not damaging", function()
		for _, status in { "Paralysis", "Sleep", "Freeze" } do
			expect(StatusEffects.endOfTurnDamage(status, 200)).toBe(0)
		end
		expect(StatusEffects.endOfTurnDamage(nil, 200)).toBe(0)
	end)
end)

describe("StatusEffects / acting under status", function()
	it("lets a clear creature act without spending a draw", function()
		local rng = RNG.new(3)
		local probe = RNG.new(3)
		local check = StatusEffects.checkAction(nil, nil, rng)
		expect(check.canAct).toBe(true)
		expect(rng:getState()).toBe(probe:getState())
	end)

	it("lets burn and poison act freely", function()
		local rng = RNG.new(3)
		for _, status in { "Burn", "Poison" } do
			expect(StatusEffects.checkAction(status, nil, rng).canAct).toBe(true)
		end
	end)

	--[[
		Sleep for N turns must block exactly N action attempts and then wake on the
		next one, acting that same turn. Off-by-one here is the difference between
		sleep being a soft inconvenience and a game-ending lock.
	]]
	it("blocks exactly as many turns as the sleep counter says", function()
		local rng = RNG.new(1)
		for duration = 1, 3 do
			local remaining: number? = duration
			for attempt = 1, duration do
				local check = StatusEffects.checkAction("Sleep", remaining, rng)
				if check.canAct then
					fail(`slept {duration} turns but woke early on attempt {attempt}`)
				end
				expect(check.reason).toBe("Asleep")
				expect(check.clearStatus).toBe(false)
				remaining = check.turnsRemaining
			end

			local waking = StatusEffects.checkAction("Sleep", remaining, rng)
			expect(waking.canAct).toBe(true)
			expect(waking.clearStatus).toBe(true)
		end
	end)

	it("counts sleep down without spending a draw", function()
		local rng = RNG.new(5)
		local probe = RNG.new(5)
		StatusEffects.checkAction("Sleep", 2, rng)
		expect(rng:getState()).toBe(probe:getState())
	end)

	it("fully paralyses about a quarter of the time", function()
		local rng = RNG.new(2024)
		local blocked = 0
		local samples = 40000
		for _ = 1, samples do
			local check = StatusEffects.checkAction("Paralysis", nil, rng)
			if not check.canAct then
				blocked += 1
				expect(check.reason).toBe("FullyParalysed")
				-- Being fully paralysed does not cure the paralysis.
				expect(check.clearStatus).toBe(false)
			end
		end
		expect(StatusEffects.FULL_PARALYSIS_CHANCE).toBe(0.25)
		expect(blocked).toBeGreaterThan(9500)
		expect(blocked).toBeLessThan(10500)
	end)

	it("thaws out of freeze about a fifth of the time, and acts when it does", function()
		local rng = RNG.new(777)
		local thawed = 0
		local samples = 40000
		for _ = 1, samples do
			local check = StatusEffects.checkAction("Freeze", nil, rng)
			if check.canAct then
				thawed += 1
				expect(check.clearStatus).toBe(true)
			else
				expect(check.reason).toBe("Frozen")
				expect(check.clearStatus).toBe(false)
			end
		end
		expect(StatusEffects.FREEZE_THAW_CHANCE).toBe(0.2)
		expect(thawed).toBeGreaterThan(7600)
		expect(thawed).toBeLessThan(8400)
	end)

	it("spends exactly one draw for paralysis and for freeze", function()
		for _, status in { "Paralysis", "Freeze" } do
			local rng = RNG.new(13)
			local probe = RNG.new(13)
			StatusEffects.checkAction(status, nil, rng)
			probe:nextUInt32()
			expect(rng:getState()).toBe(probe:getState())
		end
	end)

	it("is reproducible from a seed", function()
		local first, second = {}, {}
		local a, b = RNG.new(31337), RNG.new(31337)
		for _ = 1, 300 do
			table.insert(first, StatusEffects.checkAction("Paralysis", nil, a).canAct)
			table.insert(second, StatusEffects.checkAction("Paralysis", nil, b).canAct)
		end
		expect(first).toEqual(second)
	end)
end)
